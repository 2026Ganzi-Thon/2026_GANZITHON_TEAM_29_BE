alter table public.harvests add column rest_ends_at timestamptz;

create function public.start_rest(p_harvest_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_user_id uuid := auth.uid();
  v_auto_harvested boolean;
  v_rest_ends_at timestamptz;
  v_now timestamptz;
begin
  if v_user_id is null then
    raise sqlstate 'PT401' using message = '로그인이 필요합니다.', detail = 'UNAUTHENTICATED';
  end if;
  if p_harvest_id is null then
    raise sqlstate 'PT400' using message = '수확 ID가 필요합니다.', detail = 'INVALID_INPUT';
  end if;

  -- Serialize new rests with other rest requests and start_focus for this owner.
  perform 1 from public.profiles where id = v_user_id for no key update;

  select h.auto_harvested, h.rest_ends_at
  into v_auto_harvested, v_rest_ends_at
  from public.harvests h
  join public.focus_sessions s on s.id = h.session_id
  where h.id = p_harvest_id and s.user_id = v_user_id
  for update of h;
  if not found then
    raise sqlstate 'PT404' using message = '수확 기록을 찾을 수 없습니다.', detail = 'HARVEST_NOT_FOUND';
  end if;

  v_now := clock_timestamp();
  if v_rest_ends_at is null then
    if v_auto_harvested or exists (
      select 1 from public.focus_sessions s
      where s.user_id = v_user_id and s.status in ('focusing', 'paused')
    ) or exists (
      select 1 from public.harvests h
      join public.focus_sessions s on s.id = h.session_id
      where s.user_id = v_user_id and h.rest_ends_at > v_now
    ) then
      raise sqlstate 'PT409' using
        message = '현재 상태에서는 수확 후 휴식을 시작할 수 없습니다.', detail = 'INVALID_STATE';
    end if;

    v_rest_ends_at := v_now + interval '5 minutes';
    update public.harvests set rest_ends_at = v_rest_ends_at where id = p_harvest_id;
  end if;

  return jsonb_build_object('rest_ends_at', v_rest_ends_at, 'server_now', v_now);
end;
$$;

revoke execute on function public.start_rest(uuid) from public, anon, authenticated, service_role;
grant execute on function public.start_rest(uuid) to authenticated;
