create function public.get_my_farm()
returns table (
  plot_id uuid,
  plot_index integer,
  farm_status text,
  session_id uuid,
  session_status text,
  crop_id uuid,
  crop_name text,
  target_seconds integer
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception using errcode = 'PT401', message = 'UNAUTHENTICATED';
  end if;

  return query
  select
    p.id,
    p.plot_index,
    case
      when s.status in ('focusing', 'paused') then 'growing'
      when s.status = 'ripe' then 'ripe'
      when s.status = 'harvested' then 'harvested'
      else 'empty'
    end,
    s.id,
    s.status,
    c.id,
    c.name,
    s.target_seconds
  from public.farm_plots as p
  left join public.focus_sessions as s
    on s.user_id = v_user_id
   and s.plot_id = p.id
   and s.status in ('focusing', 'paused', 'ripe', 'harvested')
  left join public.crops as c on c.id = s.crop_id
  where p.user_id = v_user_id
  order by p.plot_index;
end;
$$;

revoke execute on function public.get_my_farm() from public, anon, authenticated, service_role;
grant execute on function public.get_my_farm() to authenticated;

comment on function public.get_my_farm() is
  'Returns the authenticated user farm projection without creating plots or changing session state.';
