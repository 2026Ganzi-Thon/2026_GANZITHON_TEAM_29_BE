create table public.farm_plots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  plot_index integer not null check (plot_index > 0),
  constraint farm_plots_user_plot_index_key unique (user_id, plot_index),
  unique (user_id, id)
);

alter table public.farm_plots enable row level security;

create policy farm_plots_select_own
on public.farm_plots
for select
to authenticated
using ((select auth.uid()) = user_id);

revoke all on table public.farm_plots from public, anon, authenticated, service_role;
grant select on table public.farm_plots to authenticated;

create function public.ensure_farm()
returns table (plot_id uuid, plot_index integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception using errcode = 'PT401', message = 'UNAUTHENTICATED';
  end if;

  perform 1 from public.profiles as p where p.id = v_user_id for key share;
  if not found then
    raise exception using errcode = 'PT404', message = 'NOT_FOUND';
  end if;

  insert into public.farm_plots (user_id, plot_index)
  select v_user_id, slots.plot_index
  from pg_catalog.generate_series(1, 12) as slots(plot_index)
  order by slots.plot_index
  on conflict on constraint farm_plots_user_plot_index_key do nothing;

  -- A separate statement sees committed rows from a concurrent initializer.
  return query
  select p.id, p.plot_index
  from public.farm_plots as p
  where p.user_id = v_user_id and p.plot_index between 1 and 12
  order by p.plot_index;
end;
$$;

revoke execute on function public.ensure_farm() from public, anon, authenticated, service_role;
grant execute on function public.ensure_farm() to authenticated;
