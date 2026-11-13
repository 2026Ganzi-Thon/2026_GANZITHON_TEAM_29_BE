begin;
select plan(12);

select has_table('public', 'farm_plots', 'farm_plots table exists');
select ok((select relrowsecurity from pg_catalog.pg_class where oid = 'public.farm_plots'::regclass), 'RLS enabled');
select ok(not has_function_privilege('anon', 'public.ensure_farm()', 'execute'), 'anon cannot initialize');
select ok(not has_function_privilege('service_role', 'public.ensure_farm()', 'execute'), 'service role cannot initialize');
select ok(not has_table_privilege('authenticated', 'public.farm_plots', 'INSERT, UPDATE, DELETE, TRUNCATE'), 'no direct writes');

insert into auth.users (id, email) values
  ('a1000000-0000-4000-8000-000000000001', 'farm-a@test.local'),
  ('a1000000-0000-4000-8000-000000000002', 'farm-b@test.local');

set local role authenticated;
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000001';
select results_eq(
  $$select plot_index from public.ensure_farm()$$,
  $$select generate_series(1, 12)$$,
  'creates and returns initial plots in order'
);
create temporary table original_farm as select * from public.ensure_farm();
select results_eq(
  $$select * from public.ensure_farm()$$,
  $$select * from original_farm order by plot_index$$,
  'repeated calls preserve IDs'
);
select is((select count(*) from public.farm_plots), 12::bigint, 'exactly 12 visible rows');

set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000002';
select is((select count(*) from public.farm_plots), 0::bigint, 'other owner rows hidden');
select is((select count(*) from public.ensure_farm()), 12::bigint, 'second user initializes independently');
select throws_ok(
  $$update public.farm_plots set plot_index = 13 where user_id = 'a1000000-0000-4000-8000-000000000001'$$,
  '42501', 'permission denied for table farm_plots', 'other owner rows cannot be modified'
);

set local role anon;
select throws_ok($$select * from public.ensure_farm()$$, '42501', 'permission denied for function ensure_farm', 'anonymous call denied');

select * from finish();
rollback;
