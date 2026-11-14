create extension if not exists pgcrypto with schema extensions;

create table private.focus_stop_previews (
  token_hash bytea primary key,
  session_id uuid not null references public.focus_sessions(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  previewed_at timestamptz not null,
  expires_at timestamptz not null,
  focused_seconds integer not null check (focused_seconds >= 0),
  cancelled_at timestamptz,
  consumed_at timestamptz,
  check (cancelled_at is null or consumed_at is null)
);

create unique index focus_stop_previews_one_pending
on private.focus_stop_previews(session_id)
where cancelled_at is null and consumed_at is null;

alter table private.focus_stop_previews enable row level security;
revoke all on private.focus_stop_previews from public, anon, authenticated, service_role;

create function public.preview_stop_focus(p_session_id uuid)
returns jsonb
language plpgsql security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_user uuid := auth.uid();
  v_session public.focus_sessions%rowtype;
  v_now timestamptz;
  v_expires timestamptz;
  v_elapsed numeric;
  v_token text;
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

  v_now := clock_timestamp();
  v_elapsed := private.focus_elapsed(v_session.started_at, v_session.paused_at, v_session.paused_duration, v_now);
  if v_session.status not in ('focusing', 'paused') or v_elapsed >= v_session.target_seconds
     or v_now - v_session.paused_at >= interval '24 hours' then
    raise sqlstate 'PT409' using message = '중도 종료할 수 없는 세션입니다.', detail = 'INVALID_STATE';
  end if;

  v_expires := v_now + interval '5 minutes';
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  update private.focus_stop_previews set cancelled_at = v_now
  where session_id = p_session_id and cancelled_at is null and consumed_at is null;
  insert into private.focus_stop_previews
    (token_hash, session_id, user_id, previewed_at, expires_at, focused_seconds)
  values (extensions.digest(v_token, 'sha256'), p_session_id, v_user, v_now, v_expires, v_elapsed::integer);

  return jsonb_build_object(
    'session_id', p_session_id, 'stop_token', v_token, 'previewed_at', v_now,
    'expires_at', v_expires, 'focused_seconds', v_elapsed,
    'focus_minutes', floor(v_elapsed / 60),
    'progress_percent', floor(v_elapsed * 100 / v_session.target_seconds), 'result', 'seed'
  );
end;
$$;

create function private.resolve_focus_stop(p_stop_token text, p_confirm boolean)
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
    set status = 'seed_saved', paused_at = null, focused_seconds = v_preview.focused_seconds
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

revoke execute on function private.resolve_focus_stop(text, boolean)
from public, anon, authenticated, service_role;

create function public.confirm_stop_focus(p_stop_token text)
returns jsonb
language sql security definer
set search_path = ''
return private.resolve_focus_stop(p_stop_token, true);

create function public.cancel_stop_focus(p_stop_token text)
returns jsonb
language sql security definer
set search_path = ''
return private.resolve_focus_stop(p_stop_token, false);

revoke execute on function public.preview_stop_focus(uuid), public.confirm_stop_focus(text), public.cancel_stop_focus(text)
from public, anon, authenticated, service_role;
grant execute on function public.preview_stop_focus(uuid), public.confirm_stop_focus(text), public.cancel_stop_focus(text)
to authenticated;

create function private.invalidate_focus_stop_preview()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  update private.focus_stop_previews set cancelled_at = clock_timestamp()
  where session_id = new.id and consumed_at is null and cancelled_at is null;
  return new;
end;
$$;

revoke execute on function private.invalidate_focus_stop_preview()
from public, anon, authenticated, service_role;

create trigger focus_sessions_invalidate_stop_preview
after update of status on public.focus_sessions
for each row when (old.status is distinct from new.status)
execute function private.invalidate_focus_stop_preview();

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
      focused_seconds = least(v_elapsed, v_session.target_seconds)::integer
  where id = v_session.id and user_id = p_user_id
  returning * into v_session;

  return jsonb_build_object(
    'session_id', v_session.id, 'status', v_session.status, 'focused_seconds', v_session.focused_seconds
  );
end;
$$;

