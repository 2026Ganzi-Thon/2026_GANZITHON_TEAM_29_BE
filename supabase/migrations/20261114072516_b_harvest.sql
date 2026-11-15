alter table public.focus_sessions
  add column ripe_at timestamptz,
  add column auto_harvest_at timestamptz;

create index focus_sessions_due_harvest
on public.focus_sessions (auto_harvest_at, user_id)
where status = 'ripe' and auto_harvest_at is not null;

drop index public.focus_sessions_one_occupant;
create unique index focus_sessions_one_occupant
on public.focus_sessions (user_id, plot_id)
where status in ('focusing', 'paused', 'ripe');

create table public.harvests (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null unique references public.focus_sessions(id) on delete cascade,
  harvested_at timestamptz not null,
  auto_harvested boolean not null,
  notice_acknowledged_at timestamptz,
  check (notice_acknowledged_at is null or auto_harvested)
);

alter table public.harvests enable row level security;
create policy harvests_select_own on public.harvests for select to authenticated
using (exists (
  select 1 from public.focus_sessions s where s.id = session_id and s.user_id = (select auth.uid())
));
revoke all on public.harvests from public, anon, authenticated, service_role;
grant select on public.harvests to authenticated;

-- Validate against PostgreSQL's installed named time zones. Unknown historical
-- values leave the deadline unset until the profile is repaired.
create function private.harvest_deadline(p_ripe_at timestamptz, p_timezone text)
returns timestamptz
language sql stable
set search_path = ''
return case when exists (
  select 1 from pg_catalog.pg_timezone_names where name = p_timezone
) then (((p_ripe_at at time zone p_timezone)::date + 1)::timestamp at time zone p_timezone)
end;

create function private.set_harvest_deadline()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_timezone text;
begin
  select timezone into v_timezone from public.profiles where id = new.user_id;
  new.ripe_at := new.started_at + new.paused_duration + make_interval(secs => new.target_seconds);
  new.auto_harvest_at := private.harvest_deadline(new.ripe_at, v_timezone);
  return new;
end;
$$;

create trigger focus_sessions_set_harvest_deadline
before update of status on public.focus_sessions
for each row when (new.status = 'ripe' and old.status is distinct from new.status)
execute function private.set_harvest_deadline();

-- Reconstruct actual completion using the session clock and the current profile zone.
update public.focus_sessions s
set ripe_at = s.started_at + s.paused_duration + make_interval(secs => s.target_seconds),
    auto_harvest_at = private.harvest_deadline(
      s.started_at + s.paused_duration + make_interval(secs => s.target_seconds), p.timezone
    )
from public.profiles p
where p.id = s.user_id and s.status = 'ripe';

create function private.validate_profile_timezone()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = new.timezone) then
    raise sqlstate '22023' using message = 'Invalid profile time zone';
  end if;
  return new;
end;
$$;

create trigger profiles_validate_timezone
before insert or update of timezone on public.profiles
for each row execute function private.validate_profile_timezone();

create function private.record_harvest(p_session_id uuid, p_now timestamptz)
returns public.harvests
language plpgsql
set search_path = ''
as $$
declare
  v_session public.focus_sessions%rowtype;
  v_harvest public.harvests%rowtype;
begin
  select * into strict v_session from public.focus_sessions where id = p_session_id for update;
  select * into v_harvest from public.harvests where session_id = p_session_id;
  if found then
    return v_harvest;
  end if;
  if v_session.status <> 'ripe' then
    raise sqlstate 'PT409' using message = '현재 상태에서는 작물을 수확할 수 없습니다.', detail = 'NOT_RIPE';
  end if;

  -- A repaired profile can restore a missing deadline. Existing deadlines stay fixed.
  if v_session.auto_harvest_at is null then
    update public.focus_sessions s
    set auto_harvest_at = private.harvest_deadline(s.ripe_at, p.timezone)
    from public.profiles p
    where s.id = p_session_id and p.id = s.user_id
    returning s.* into v_session;
  end if;

  insert into public.harvests (session_id, harvested_at, auto_harvested)
  values (p_session_id, p_now, coalesce(v_session.auto_harvest_at <= p_now, false))
  returning * into v_harvest;

  update public.focus_sessions set status = 'harvested' where id = p_session_id;
  return v_harvest;
end;
$$;

create function public.harvest_crop(p_session_id uuid)
returns jsonb
language plpgsql security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_user uuid := auth.uid();
  v_session public.focus_sessions%rowtype;
  v_harvest public.harvests%rowtype;
begin
  if v_user is null then
    raise sqlstate 'PT401' using message = '로그인이 필요합니다.', detail = 'UNAUTHENTICATED';
  end if;
  if p_session_id is null then
    raise sqlstate 'PT400' using message = '집중 세션 ID가 필요합니다.', detail = 'INVALID_INPUT';
  end if;

  perform 1 from public.profiles where id = v_user for no key update;
  select * into v_session from public.focus_sessions
  where id = p_session_id and user_id = v_user for update;
  if not found then
    raise sqlstate 'PT404' using message = '본인의 집중 세션을 찾을 수 없습니다.', detail = 'SESSION_NOT_FOUND';
  end if;

  v_harvest := private.record_harvest(p_session_id, clock_timestamp());
  return jsonb_build_object(
    'harvest_id', v_harvest.id, 'session_id', v_session.id, 'plot_id', v_session.plot_id,
    'crop_id', v_session.crop_id, 'focused_seconds', v_session.focused_seconds,
    'harvested_at', v_harvest.harvested_at, 'auto_harvested', v_harvest.auto_harvested
  );
end;
$$;

create function public.process_due_harvests()
returns jsonb
language plpgsql
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_user uuid;
  v_session uuid;
  v_count integer := 0;
begin
  -- Lock owners before sessions, as in start_focus and stop preview.
  for v_user in
    select p.id from public.profiles p
    where exists (
      select 1 from public.focus_sessions s
      where s.user_id = p.id and (
        (s.status = 'ripe' and (
          s.auto_harvest_at <= v_now
          or (s.auto_harvest_at is null and private.harvest_deadline(s.ripe_at, p.timezone) is not null)
        ))
        or (s.status = 'focusing'
            and s.started_at + s.paused_duration + make_interval(secs => s.target_seconds) <= v_now
            and not exists (
              select 1 from private.focus_stop_previews preview
              where preview.session_id = s.id and preview.cancelled_at is null
                and preview.consumed_at is null and preview.expires_at > v_now
            ))
      )
    )
    order by p.id limit 100 for no key update skip locked
  loop
    perform private.finalize_focus(v_user);

    update public.focus_sessions s
    set auto_harvest_at = private.harvest_deadline(s.ripe_at, p.timezone)
    from public.profiles p
    where p.id = v_user and s.user_id = p.id and s.status = 'ripe'
      and s.auto_harvest_at is null
      and private.harvest_deadline(s.ripe_at, p.timezone) is not null;

    for v_session in
      select s.id from public.focus_sessions s
      where s.user_id = v_user and s.status = 'ripe' and s.auto_harvest_at <= v_now
      order by s.auto_harvest_at, s.id
    loop
      perform private.record_harvest(v_session, v_now);
      v_count := v_count + 1;
    end loop;
  end loop;
  return jsonb_build_object('processed_count', v_count);
end;
$$;

create function public.ack_auto_harvest_notice(p_harvest_ids uuid[])
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_count integer;
begin
  if v_user is null then
    raise sqlstate 'PT401' using message = '로그인이 필요합니다.', detail = 'UNAUTHENTICATED';
  end if;
  if coalesce(cardinality(p_harvest_ids), 0) = 0 or exists (
    select 1 from unnest(p_harvest_ids) as requested(id) where id is null
  ) then
    raise sqlstate 'PT400' using message = '수확 ID 목록이 올바르지 않습니다.', detail = 'INVALID_INPUT';
  end if;

  perform 1 from public.profiles where id = v_user for no key update;
  if exists (
    select 1 from unnest(p_harvest_ids) as requested(id)
    where not exists (
      select 1 from public.harvests h join public.focus_sessions s on s.id = h.session_id
      where h.id = requested.id and s.user_id = v_user and h.auto_harvested
    )
  ) then
    raise sqlstate 'PT404' using message = '자동 수확 기록을 찾을 수 없습니다.', detail = 'AUTO_HARVEST_NOT_FOUND';
  end if;

  update public.harvests h set notice_acknowledged_at = clock_timestamp()
  from public.focus_sessions s
  where s.id = h.session_id and s.user_id = v_user and h.auto_harvested
    and h.id = any(p_harvest_ids) and h.notice_acknowledged_at is null;
  get diagnostics v_count = row_count;
  return jsonb_build_object('acknowledged_count', v_count);
end;
$$;

revoke execute on function private.harvest_deadline(timestamptz, text), private.validate_profile_timezone(),
  private.set_harvest_deadline(), private.record_harvest(uuid, timestamptz),
  public.process_due_harvests(), public.harvest_crop(uuid), public.ack_auto_harvest_notice(uuid[])
from public, anon, authenticated, service_role;
grant execute on function public.harvest_crop(uuid), public.ack_auto_harvest_notice(uuid[]) to authenticated;

create or replace function public.start_focus(p_plot_id uuid, p_crop_id uuid)
returns jsonb
language plpgsql security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_user uuid := auth.uid();
  v_timezone text;
  v_target integer;
  v_now timestamptz;
  v_id uuid;
  v_constraint text;
begin
  if v_user is null then
    raise sqlstate 'PT401' using message = '로그인이 필요합니다.', detail = 'UNAUTHENTICATED';
  end if;
  if p_plot_id is null or p_crop_id is null then
    raise sqlstate 'PT400' using message = '밭과 작물을 선택해 주세요.', detail = 'INVALID_INPUT';
  end if;

  select p.timezone into v_timezone
  from public.profiles p join public.farm_plots f on f.user_id = p.id
  where p.id = v_user and f.id = p_plot_id
  for key share of p, f;
  if not found then
    raise sqlstate 'PT404' using message = '본인 농장에서 밭을 찾을 수 없습니다.', detail = 'PLOT_NOT_FOUND';
  end if;

  select c.target_seconds into v_target from public.crops c
  where c.id = p_crop_id and c.is_active for share;
  if not found then
    raise sqlstate 'PT404' using message = '선택할 수 있는 작물을 찾을 수 없습니다.', detail = 'CROP_NOT_FOUND';
  end if;

  perform private.finalize_focus(v_user);

  if exists (
    select 1 from public.focus_sessions s where s.user_id = v_user and s.plot_id = p_plot_id
    and s.status in ('focusing', 'paused', 'ripe')
  ) then
    raise sqlstate 'PT409' using message = '이미 작물이 있는 밭입니다.', detail = 'PLOT_OCCUPIED';
  end if;
  if exists (
    select 1 from public.focus_sessions s where s.user_id = v_user and s.status in ('focusing', 'paused')
  ) then
    raise sqlstate 'PT409' using message = '이미 진행 중인 집중 세션이 있습니다.', detail = 'ACTIVE_SESSION_EXISTS';
  end if;

  v_now := clock_timestamp();
  begin
    insert into public.focus_sessions (user_id, plot_id, crop_id, status, started_at, target_seconds, record_date)
    values (v_user, p_plot_id, p_crop_id, 'focusing', v_now, v_target, (v_now at time zone v_timezone)::date)
    returning id into v_id;
  exception when unique_violation then
    get stacked diagnostics v_constraint = constraint_name;
    if v_constraint = 'focus_sessions_one_occupant' or (
      v_constraint = 'focus_sessions_one_active_user' and exists (
        select 1 from public.focus_sessions s where s.user_id = v_user and s.plot_id = p_plot_id
        and s.status in ('focusing', 'paused', 'ripe')
      )
    ) then
      raise sqlstate 'PT409' using message = '이미 작물이 있는 밭입니다.', detail = 'PLOT_OCCUPIED';
    elsif v_constraint = 'focus_sessions_one_active_user' then
      raise sqlstate 'PT409' using message = '이미 진행 중인 집중 세션이 있습니다.', detail = 'ACTIVE_SESSION_EXISTS';
    end if;
    raise;
  end;
  return jsonb_build_object(
    'session_id', v_id, 'plot_id', p_plot_id, 'crop_id', p_crop_id, 'status', 'focusing',
    'started_at', v_now, 'target_seconds', v_target, 'server_now', v_now
  );
end;
$$;
