alter table public.focus_sessions add column focus_ended_at timestamptz;

update public.focus_sessions
set focus_ended_at = ripe_at
where status in ('ripe', 'harvested') and ripe_at is not null;

create function private.set_completed_focus_end()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.focus_ended_at := new.started_at + new.paused_duration + make_interval(secs => new.target_seconds);
  return new;
end;
$$;

revoke execute on function private.set_completed_focus_end() from public, anon, authenticated, service_role;
create trigger focus_sessions_set_completed_focus_end
before update of status on public.focus_sessions
for each row when (new.status = 'ripe' and old.status is distinct from new.status)
execute function private.set_completed_focus_end();

create index focus_sessions_streak_history
on public.focus_sessions (user_id, started_at desc, id desc)
where status in ('ripe', 'harvested', 'seed_saved');

create table private.overwork_notices (
  user_id uuid not null references public.profiles(id) on delete cascade,
  local_date date not null,
  claimed_at timestamptz not null,
  primary key (user_id, local_date)
);
alter table private.overwork_notices enable row level security;
revoke all on private.overwork_notices from public, anon, authenticated, service_role;

-- Traverse only the uninterrupted chain. An unknown historical end breaks it.
create function private.focus_streak_seconds(p_user uuid, p_started_at timestamptz, p_elapsed numeric)
returns numeric
language plpgsql stable
set search_path = ''
as $$
declare
  v_rest_started_at timestamptz;
  v_next_started_at timestamptz := p_started_at;
  v_total numeric := p_elapsed;
  v_previous record;
begin
  select max(h.rest_ends_at) - interval '5 minutes' into v_rest_started_at
  from public.harvests h join public.focus_sessions s on s.id = h.session_id
  where s.user_id = p_user and h.rest_ends_at is not null;

  for v_previous in
    select started_at, focus_ended_at, focused_seconds
    from public.focus_sessions
    where user_id = p_user and status in ('ripe', 'harvested', 'seed_saved')
      and started_at < p_started_at
      and (v_rest_started_at is null or started_at >= v_rest_started_at)
    order by started_at desc, id desc
  loop
    exit when v_previous.focus_ended_at is null
      or v_next_started_at - v_previous.focus_ended_at >= interval '30 minutes';
    v_total := v_total + v_previous.focused_seconds;
    v_next_started_at := v_previous.started_at;
  end loop;
  return v_total;
end;
$$;

create function private.overwork_notice_due(p_user uuid, p_session uuid, p_now timestamptz, p_local_date date)
returns boolean
language sql stable
set search_path = ''
return exists (
  select 1
  from public.focus_sessions s
  cross join lateral (
    select private.focus_elapsed(s.started_at, s.paused_at, s.paused_duration, p_now) as elapsed
  ) t
  where s.id = p_session and s.user_id = p_user and s.status = 'focusing'
    and t.elapsed < s.target_seconds
    and not exists (
      select 1 from private.overwork_notices n where n.user_id = p_user and n.local_date = p_local_date
    )
    and private.focus_streak_seconds(p_user, s.started_at, t.elapsed) > 5400
);

revoke execute on function private.focus_streak_seconds(uuid,timestamptz,numeric),
  private.overwork_notice_due(uuid,uuid,timestamptz,date)
from public, anon, authenticated, service_role;

create or replace function private.resolve_focus_stop(p_stop_token text, p_confirm boolean)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_hash bytea;
  v_session_id uuid;
  v_status text;
  v_preview private.focus_stop_previews%rowtype;
  v_now timestamptz;
begin
  if v_user is null then
    raise sqlstate 'PT401' using message = '로그인이 필요합니다.', detail = 'UNAUTHENTICATED';
  end if;
  if p_stop_token is null or p_stop_token !~ '^[0-9a-f]{64}$' then
    raise sqlstate 'PT400' using message = '중도 종료 토큰이 올바르지 않습니다.', detail = 'INVALID_INPUT';
  end if;

  perform 1 from public.profiles where id = v_user for no key update;
  v_hash := extensions.digest(p_stop_token, 'sha256');
  select session_id into v_session_id from private.focus_stop_previews
  where token_hash = v_hash and user_id = v_user;
  select status into v_status from public.focus_sessions
  where id = v_session_id and user_id = v_user for update;
  if not found then
    raise sqlstate 'PT404' using message = '중도 종료 토큰을 찾을 수 없습니다.', detail = 'STOP_TOKEN_NOT_FOUND';
  end if;
  select * into v_preview from private.focus_stop_previews
  where token_hash = v_hash and user_id = v_user and session_id = v_session_id for update;

  v_now := clock_timestamp();
  if p_confirm and v_preview.consumed_at is null then
    if v_now >= v_preview.expires_at then
      raise sqlstate 'PT409' using message = '중도 종료 토큰이 만료됐습니다.', detail = 'STOP_TOKEN_EXPIRED';
    end if;
    if v_preview.cancelled_at is not null or v_status not in ('focusing', 'paused') then
      raise sqlstate 'PT409' using message = '중도 종료 미리보기가 무효화됐습니다.', detail = 'INVALID_STATE';
    end if;

    update private.focus_stop_previews set consumed_at = v_now where token_hash = v_hash;
    update public.focus_sessions
    set status = 'seed_saved', paused_at = null, focused_seconds = v_preview.focused_seconds,
        focus_ended_at = coalesce(paused_at, v_preview.previewed_at)
    where id = v_session_id and user_id = v_user;
  end if;

  if p_confirm then
    return jsonb_build_object(
      'session_id', v_session_id, 'status', 'seed_saved', 'result', 'seed',
      'focused_seconds', v_preview.focused_seconds, 'plot_status', 'empty'
    );
  end if;

  if v_preview.consumed_at is not null then
    return jsonb_build_object('session_id', v_session_id, 'cancelled', false);
  end if;
  update private.focus_stop_previews set cancelled_at = v_now
  where token_hash = v_hash and cancelled_at is null;
  return jsonb_build_object('session_id', v_session_id, 'cancelled', true);
end;
$$;


create or replace function private.finalize_focus(p_user_id uuid)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_session public.focus_sessions%rowtype;
  v_elapsed numeric;
  v_now timestamptz;
  v_status text;
begin
  -- Serialize starts and standalone finalization for the same owner, even without an active row.
  perform 1 from public.profiles where id = p_user_id for no key update;

  -- Pause and resume also lock this row. Evaluate time only after acquiring it.
  select s.* into v_session from public.focus_sessions s
  where s.user_id = p_user_id and s.status in ('focusing', 'paused')
  for update;
  if not found then
    return null;
  end if;

  v_now := clock_timestamp();
  -- A live preview owns the decision until confirmation, cancellation or expiry.
  if exists (
    select 1 from private.focus_stop_previews
    where session_id = v_session.id and consumed_at is null
      and cancelled_at is null and expires_at > v_now
  ) then
    return null;
  end if;
  v_elapsed := private.focus_elapsed(v_session.started_at, v_session.paused_at, v_session.paused_duration, v_now);
  if v_elapsed >= v_session.target_seconds then
    v_status := 'ripe';
  elsif v_session.status = 'paused' and v_now - v_session.paused_at >= interval '24 hours' then
    v_status := 'seed_saved';
  else
    return null;
  end if;

  update public.focus_sessions
  set status = v_status, paused_at = null,
      focus_ended_at = case when v_status = 'seed_saved' then v_session.paused_at end,
      focused_seconds = least(v_elapsed, v_session.target_seconds)::integer
  where id = v_session.id and user_id = p_user_id
  returning * into v_session;

  return jsonb_build_object(
    'session_id', v_session.id, 'status', v_session.status, 'focused_seconds', v_session.focused_seconds
  );
end;
$$;

create or replace function public.get_active_focus()
returns jsonb
language plpgsql stable security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_user uuid := auth.uid();
  v_now timestamptz := statement_timestamp();
  v_session jsonb;
  v_notice boolean := false;
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

  if v_session->>'status' = 'focusing' then
    v_notice := exists (
      select 1 from public.profiles p where p.id = v_user
        and private.overwork_notice_due(
          v_user, (v_session->>'session_id')::uuid, v_now, (v_now at time zone p.timezone)::date
        )
    );
  end if;
  return jsonb_build_object('session', v_session, 'server_now', v_now, 'show_overwork_notice', v_notice);
end;
$$;

create function public.claim_overwork_notice(p_session_id uuid)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_timezone text;
  v_now timestamptz;
  v_local_date date;
  v_claimed boolean := false;
begin
  if v_user is null then
    raise sqlstate 'PT401' using message = '로그인이 필요합니다.', detail = 'UNAUTHENTICATED';
  end if;
  if p_session_id is null then
    raise sqlstate 'PT400' using message = '집중 세션 ID가 필요합니다.', detail = 'INVALID_INPUT';
  end if;

  select timezone into v_timezone from public.profiles where id = v_user for no key update;
  perform 1 from public.focus_sessions where id = p_session_id and user_id = v_user for update;
  if found then
    v_now := clock_timestamp();
    v_local_date := (v_now at time zone v_timezone)::date;
    if private.overwork_notice_due(v_user, p_session_id, v_now, v_local_date) then
      insert into private.overwork_notices (user_id, local_date, claimed_at)
      values (v_user, v_local_date, v_now)
      on conflict (user_id, local_date) do nothing;
      v_claimed := found;
    end if;
  end if;
  return jsonb_build_object('show_overwork_notice', v_claimed);
end;
$$;

revoke execute on function public.claim_overwork_notice(uuid) from public, anon, authenticated, service_role;
grant execute on function public.claim_overwork_notice(uuid) to authenticated;
