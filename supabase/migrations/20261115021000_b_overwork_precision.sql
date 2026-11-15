-- Legacy profiles predate the INSERT/UPDATE time-zone validation trigger.
create function private.overwork_local_date(p_now timestamptz, p_timezone text)
returns date
language sql stable
set search_path = ''
return case when exists (
  select 1 from pg_catalog.pg_timezone_names where name = p_timezone
) then (p_now at time zone p_timezone)::date end;

revoke execute on function private.overwork_local_date(timestamptz, text)
from public, anon, authenticated, service_role;

create or replace function private.overwork_notice_due(p_user uuid, p_session uuid, p_now timestamptz, p_local_date date)
returns boolean
language sql stable
set search_path = ''
return exists (
  select 1
  from public.focus_sessions s
  cross join lateral (
    -- EXTRACT returns numeric, preserving the timestamp's fractional seconds.
    select greatest(0, extract(epoch from (p_now - s.started_at - s.paused_duration))) as elapsed
  ) t
  where s.id = p_session and s.user_id = p_user and s.status = 'focusing'
    and p_local_date is not null
    and t.elapsed < s.target_seconds
    and not exists (
      select 1 from private.overwork_notices n where n.user_id = p_user and n.local_date = p_local_date
    )
    and private.focus_streak_seconds(p_user, s.started_at, t.elapsed) > 5400
);

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
          v_user, (v_session->>'session_id')::uuid, v_now, private.overwork_local_date(v_now, p.timezone)
        )
    );
  end if;
  return jsonb_build_object('session', v_session, 'server_now', v_now, 'show_overwork_notice', v_notice);
end;
$$;

create or replace function public.claim_overwork_notice(p_session_id uuid)
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
    v_local_date := private.overwork_local_date(v_now, v_timezone);
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
