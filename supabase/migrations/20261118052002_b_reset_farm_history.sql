create function public.reset_farm_history()
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
begin
  if v_user is null then
    raise sqlstate 'PT401' using message = 'UNAUTHENTICATED';
  end if;

  perform 1 from public.profiles where id = v_user for no key update;
  if not found then
    raise sqlstate 'PT404' using message = 'NOT_FOUND';
  end if;

  perform public.ensure_farm();
  -- Lock sessions before cascading to previews/harvests, matching focus writers.
  perform 1 from public.focus_sessions where user_id = v_user order by id for update;
  delete from private.overwork_notices where user_id = v_user;
  delete from public.focus_sessions where user_id = v_user;
  -- Session FKs cascade to harvest notes, rests, notices and stop tokens.
  return jsonb_build_object('success', true);
end;
$$;

revoke execute on function public.reset_farm_history() from public, anon, authenticated, service_role;
grant execute on function public.reset_farm_history() to authenticated;

comment on function public.reset_farm_history() is
  'Irreversibly deletes the authenticated owner activity; preserves auth, profile, onboarding and plot identities. Do not automatically retry delayed requests.';
