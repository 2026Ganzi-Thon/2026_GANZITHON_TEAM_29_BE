-- Phase 2 A foundation: profiles, crop catalog, RPCs, RLS, and explicit grants.

create schema if not exists private;

revoke all on schema private from public;
revoke all on schema private from anon, authenticated;

-- New public objects stay private until a migration grants access explicitly.
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on functions from anon, authenticated, service_role;

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  nickname text not null default '농부',
  timezone text not null default 'Asia/Seoul',
  onboarded_at timestamptz,
  created_at timestamptz not null default now(),
  constraint profiles_nickname_length check (char_length(btrim(nickname)) between 1 and 30),
  constraint profiles_timezone_length check (char_length(btrim(timezone)) between 1 and 64)
);

comment on table public.profiles is 'Application profile keyed by auth.users.id.';
comment on column public.profiles.nickname is 'Display-only name copied from signup metadata; never used for authorization.';
comment on column public.profiles.timezone is 'IANA timezone used for user-local dates; validation rules require team review.';

create table public.crops (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  target_seconds integer not null,
  energy_level text not null,
  sort_order integer not null,
  is_active boolean not null default true,
  constraint crops_name_unique unique (name),
  constraint crops_name_length check (char_length(btrim(name)) between 1 and 50),
  constraint crops_target_seconds_positive check (target_seconds > 0),
  constraint crops_energy_level_valid check (energy_level in ('low', 'medium', 'high')),
  constraint crops_sort_order_positive check (sort_order > 0),
  constraint crops_sort_order_unique unique (sort_order)
);

comment on table public.crops is 'Stable crop catalog shared with focus session creation.';

insert into public.crops (id, name, target_seconds, energy_level, sort_order, is_active)
values
  ('10000000-0000-4000-8000-000000000001', '새싹채소', 600, 'low', 1, true),
  ('10000000-0000-4000-8000-000000000002', '당근', 1200, 'low', 2, true),
  ('10000000-0000-4000-8000-000000000003', '딸기', 1800, 'medium', 3, true),
  ('10000000-0000-4000-8000-000000000004', '옥수수', 2700, 'medium', 4, true),
  ('10000000-0000-4000-8000-000000000005', '토마토', 3600, 'high', 5, true),
  ('10000000-0000-4000-8000-000000000006', '호박', 5400, 'high', 6, true)
on conflict (id) do update
set
  name = excluded.name,
  target_seconds = excluded.target_seconds,
  energy_level = excluded.energy_level,
  sort_order = excluded.sort_order,
  is_active = excluded.is_active;

alter table public.profiles enable row level security;
alter table public.crops enable row level security;

create policy profiles_select_own
on public.profiles
for select
to authenticated
using ((select auth.uid()) = id);

create policy crops_select_active
on public.crops
for select
to authenticated
using (is_active);

revoke all on table public.profiles from public, anon, authenticated, service_role;
revoke all on table public.crops from public, anon, authenticated, service_role;
grant select on table public.profiles to authenticated;
grant select on table public.crops to authenticated;

create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nickname text;
begin
  v_nickname := nullif(btrim(new.raw_user_meta_data ->> 'nickname'), '');
  v_nickname := left(coalesce(v_nickname, '농부'), 30);

  insert into public.profiles (id, nickname)
  values (new.id, v_nickname)
  on conflict (id) do nothing;

  return new;
end;
$$;

revoke execute on function private.handle_new_user() from public, anon, authenticated, service_role;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function private.handle_new_user();

create function public.get_my_profile()
returns table (
  nickname text,
  timezone text,
  onboarded boolean,
  onboarded_at timestamptz
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
    p.nickname,
    p.timezone,
    p.onboarded_at is not null,
    p.onboarded_at
  from public.profiles as p
  where p.id = v_user_id;

  if not found then
    raise exception using errcode = 'PT404', message = 'NOT_FOUND';
  end if;
end;
$$;

create function public.complete_onboarding()
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_onboarded_at timestamptz;
begin
  if v_user_id is null then
    raise exception using errcode = 'PT401', message = 'UNAUTHENTICATED';
  end if;

  update public.profiles
  set onboarded_at = coalesce(onboarded_at, statement_timestamp())
  where id = v_user_id
  returning onboarded_at into v_onboarded_at;

  if not found then
    raise exception using errcode = 'PT404', message = 'NOT_FOUND';
  end if;

  return v_onboarded_at;
end;
$$;

create function public.list_crops(p_energy text)
returns table (
  crop_id uuid,
  name text,
  target_seconds integer,
  recommended boolean,
  sort_order integer
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

  if p_energy is not null and p_energy not in ('low', 'medium', 'high') then
    raise exception using errcode = '22023', message = 'INVALID_INPUT';
  end if;

  return query
  select
    c.id,
    c.name,
    c.target_seconds,
    p_energy is not null and c.energy_level = p_energy,
    c.sort_order
  from public.crops as c
  where c.is_active
  order by c.sort_order;
end;
$$;

revoke execute on function public.get_my_profile() from public, anon, authenticated, service_role;
revoke execute on function public.complete_onboarding() from public, anon, authenticated, service_role;
revoke execute on function public.list_crops(text) from public, anon, authenticated, service_role;

grant execute on function public.get_my_profile() to authenticated;
grant execute on function public.complete_onboarding() to authenticated;
grant execute on function public.list_crops(text) to authenticated;

comment on function public.get_my_profile() is 'Returns the authenticated user profile without internal columns.';
comment on function public.complete_onboarding() is 'Idempotently completes onboarding for the authenticated user.';
comment on function public.list_crops(text) is 'Lists active crops and marks recommendations for the requested energy level.';
