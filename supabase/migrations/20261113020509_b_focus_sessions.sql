create table public.focus_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  plot_id uuid not null,
  crop_id uuid not null references public.crops (id),
  status text not null check (status in ('focusing', 'paused', 'seed_saved', 'ripe', 'harvested')),
  started_at timestamptz not null,
  paused_at timestamptz,
  paused_duration interval not null default interval '0' check (paused_duration >= interval '0'),
  target_seconds integer not null check (target_seconds > 0),
  focused_seconds integer not null default 0 check (focused_seconds >= 0),
  record_date date not null,
  foreign key (user_id, plot_id) references public.farm_plots (user_id, id) on delete cascade,
  check ((status = 'paused') = (paused_at is not null)),
  check (paused_at is null or paused_at >= started_at)
);

create unique index focus_sessions_one_active_user
on public.focus_sessions (user_id) where status in ('focusing', 'paused');

create unique index focus_sessions_one_occupant
on public.focus_sessions (user_id, plot_id)
where status in ('focusing', 'paused', 'ripe', 'harvested');

alter table public.focus_sessions enable row level security;
create policy focus_sessions_select_own on public.focus_sessions
for select to authenticated using ((select auth.uid()) = user_id);
revoke all on table public.focus_sessions from public, anon, authenticated, service_role;
grant select on table public.focus_sessions to authenticated;

create function private.focus_elapsed(
  p_started_at timestamptz, p_paused_at timestamptz,
  p_paused_duration interval, p_now timestamptz
)
returns numeric
language sql immutable
set search_path = ''
return greatest(0, floor(extract(epoch from
  (coalesce(p_paused_at, p_now) - p_started_at - p_paused_duration))));

revoke execute on function private.focus_elapsed(timestamptz, timestamptz, interval, timestamptz)
from public, anon, authenticated, service_role;

create function public.start_focus(p_plot_id uuid, p_crop_id uuid)
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

  if exists (
    select 1 from public.focus_sessions s where s.user_id = v_user and s.plot_id = p_plot_id
    and s.status in ('focusing', 'paused', 'ripe', 'harvested')
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
        and s.status in ('focusing', 'paused', 'ripe', 'harvested')
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

create function public.get_active_focus()
returns jsonb
language plpgsql stable security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_user uuid := auth.uid();
  v_now timestamptz := statement_timestamp();
  v_session jsonb;
begin
  if v_user is null then
    raise sqlstate 'PT401' using message = '로그인이 필요합니다.', detail = 'UNAUTHENTICATED';
  end if;
  select jsonb_build_object(
    'session_id', s.id, 'plot_id', s.plot_id, 'crop_id', s.crop_id, 'status', s.status,
    'started_at', s.started_at, 'paused_at', s.paused_at, 'target_seconds', s.target_seconds,
    'focused_seconds', t.elapsed, 'remaining_seconds', s.target_seconds - t.elapsed
  ) into v_session
  from public.focus_sessions s
  cross join lateral (
    select private.focus_elapsed(s.started_at, s.paused_at, s.paused_duration, v_now) as elapsed
  ) t
  where s.user_id = v_user and s.status in ('focusing', 'paused')
    and t.elapsed < s.target_seconds
    and (s.paused_at is null or v_now - s.paused_at < interval '24 hours');

  -- Temporary until the active-session overwork policy is agreed.
  return jsonb_build_object('session', v_session, 'server_now', v_now, 'show_overwork_notice', false);
end;
$$;

create function private.change_focus_pause(p_session_id uuid, p_pause boolean)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_session public.focus_sessions%rowtype;
  v_now timestamptz;
  v_elapsed numeric;
  v_result jsonb;
begin
  if v_user is null then
    raise sqlstate 'PT401' using message = '로그인이 필요합니다.', detail = 'UNAUTHENTICATED';
  end if;
  if p_session_id is null then
    raise sqlstate 'PT400' using message = '집중 세션 ID가 필요합니다.', detail = 'INVALID_INPUT';
  end if;

  select s.* into v_session from public.focus_sessions s
  where s.id = p_session_id and s.user_id = v_user for update;
  if not found then
    raise sqlstate 'PT404' using message = '본인의 집중 세션을 찾을 수 없습니다.', detail = 'SESSION_NOT_FOUND';
  end if;

  v_now := clock_timestamp();
  v_elapsed := private.focus_elapsed(v_session.started_at, v_session.paused_at, v_session.paused_duration, v_now);
  if not p_pause and v_session.status = 'paused' and v_now - v_session.paused_at >= interval '24 hours' then
    raise sqlstate 'PT409' using
      message = '일시정지한 지 24시간이 지나 집중을 재개할 수 없습니다.', detail = 'PAUSE_EXPIRED';
  end if;
  if v_session.status not in ('focusing', 'paused') or v_elapsed >= v_session.target_seconds then
    raise sqlstate 'PT409' using
      message = case when p_pause then '현재 상태에서는 집중을 일시정지할 수 없습니다.'
                     else '현재 상태에서는 집중을 재개할 수 없습니다.' end,
      detail = 'INVALID_STATE';
  end if;

  if p_pause and v_session.status = 'focusing' then
    update public.focus_sessions
    set status = 'paused', paused_at = v_now, focused_seconds = v_elapsed::integer
    where id = p_session_id and user_id = v_user returning * into v_session;
  elsif not p_pause and v_session.status = 'paused' then
    update public.focus_sessions
    set status = 'focusing', paused_at = null, focused_seconds = v_elapsed::integer,
        paused_duration = paused_duration + greatest(interval '0', v_now - paused_at)
    where id = p_session_id and user_id = v_user returning * into v_session;
  end if;

  v_result := jsonb_build_object(
    'session_id', v_session.id, 'status', v_session.status,
    'remaining_seconds', v_session.target_seconds - v_elapsed, 'server_now', v_now
  );
  if p_pause then
    return v_result || jsonb_build_object('paused_at', v_session.paused_at);
  end if;
  return v_result;
end;
$$;

revoke execute on function private.change_focus_pause(uuid, boolean)
from public, anon, authenticated, service_role;

create function public.pause_focus(p_session_id uuid)
returns jsonb
language sql security definer
set search_path = ''
set timezone = 'UTC'
return private.change_focus_pause(p_session_id, true);

create function public.resume_focus(p_session_id uuid)
returns jsonb
language sql security definer
set search_path = ''
set timezone = 'UTC'
return private.change_focus_pause(p_session_id, false);

revoke execute on function public.start_focus(uuid, uuid), public.get_active_focus(),
  public.pause_focus(uuid), public.resume_focus(uuid)
from public, anon, authenticated, service_role;
grant execute on function public.start_focus(uuid, uuid), public.get_active_focus(),
  public.pause_focus(uuid), public.resume_focus(uuid) to authenticated;
