create or replace function public.save_harvest_note(p_harvest_id uuid, p_note text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_note text;
begin
  if v_user_id is null then
    raise sqlstate 'PT401' using message = '로그인이 필요합니다.', detail = 'UNAUTHENTICATED';
  end if;

  v_note := regexp_replace(p_note, '^[[:space:]]+|[[:space:]]+$', '', 'g');
  if p_harvest_id is null or v_note is null or v_note = '' then
    raise sqlstate 'PT400' using message = '수확 ID와 메모가 필요합니다.', detail = 'INVALID_INPUT';
  end if;
  if char_length(v_note) > 50 then
    raise sqlstate 'PT400' using message = '메모는 50자까지 입력할 수 있습니다.', detail = 'NOTE_TOO_LONG';
  end if;

  perform 1
  from public.harvests h
  join public.focus_sessions s on s.id = h.session_id
  where h.id = p_harvest_id and s.user_id = v_user_id;
  if not found then
    raise sqlstate 'PT404' using message = '수확 기록을 찾을 수 없습니다.', detail = 'HARVEST_NOT_FOUND';
  end if;

  -- Keep the initial Figma candidates in sync with docs/development.md.
  if exists (
    select 1
    from unnest(array['죽고 싶', '자살', '사라지고 싶', '살기 싫', '끝내고 싶']) as candidate(phrase)
    where strpos(v_note, candidate.phrase) > 0
  ) then
    return jsonb_build_object('saved', false, 'guidance_required', true);
  end if;

  update public.harvests h
  set note = v_note
  from public.focus_sessions s
  where h.id = p_harvest_id and s.id = h.session_id and s.user_id = v_user_id;
  if not found then
    raise sqlstate 'PT404' using message = '수확 기록을 찾을 수 없습니다.', detail = 'HARVEST_NOT_FOUND';
  end if;

  return jsonb_build_object('saved', true, 'guidance_required', false);
end;
$$;

revoke execute on function public.save_harvest_note(uuid, text)
from public, anon, authenticated, service_role;
grant execute on function public.save_harvest_note(uuid, text) to authenticated;

comment on function public.save_harvest_note(uuid, text) is
  'Checks S10 notes for S13 guidance before saving an owned harvest note.';
