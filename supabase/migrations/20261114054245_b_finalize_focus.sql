create function private.finalize_focus(p_user_id uuid)
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

revoke execute on function private.finalize_focus(uuid) from public, anon, authenticated, service_role;

create function public.finalize_my_focus()
returns jsonb
language plpgsql security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise sqlstate 'PT401' using message = '로그인이 필요합니다.', detail = 'UNAUTHENTICATED';
  end if;
  return private.finalize_focus(v_user);
end;
$$;

revoke execute on function public.finalize_my_focus() from public, anon, authenticated, service_role;
grant execute on function public.finalize_my_focus() to authenticated;

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
