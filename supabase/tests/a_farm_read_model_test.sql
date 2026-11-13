begin;
select plan(25);

select has_function('public', 'get_my_farm', array[]::text[], 'get_my_farm exists');
select ok(has_function_privilege('authenticated', 'public.get_my_farm()', 'execute'), 'authenticated can read own farm');
select ok(not has_function_privilege('anon', 'public.get_my_farm()', 'execute'), 'anon cannot execute get_my_farm');
select ok(not has_function_privilege('service_role', 'public.get_my_farm()', 'execute'), 'service role cannot execute get_my_farm');
select ok(
  (
    select not prosecdef
      and provolatile = 's'
      and array_to_string(proconfig, ',') = 'search_path=""'
    from pg_catalog.pg_proc
    where oid = 'public.get_my_farm()'::regprocedure
  ),
  'get_my_farm is stable invoker with an empty search_path'
);

insert into auth.users (id, email) values
  ('a5000000-0000-4000-8000-000000000001', 'farm-read-a@test.local'),
  ('a5000000-0000-4000-8000-000000000002', 'farm-read-b@test.local');

set local role authenticated;
set local request.jwt.claim.sub = 'a5000000-0000-4000-8000-000000000001';
select is((select count(*) from public.get_my_farm()), 0::bigint, 'user without plots receives an empty result');
select is((select count(*) from public.farm_plots), 0::bigint, 'farm read does not create plots');

create temporary table farm_a as select * from public.ensure_farm();
select is((select count(*) from farm_a), 12::bigint, 'fixture has twelve plots');
select results_eq(
  $$select plot_index from public.get_my_farm()$$,
  $$select generate_series(1, 12)$$,
  'plots are returned in display order'
);
select is((select count(*) from public.get_my_farm() where farm_status = 'empty'), 12::bigint, 'new plots are empty');

reset role;
insert into public.focus_sessions (
  id, user_id, plot_id, crop_id, status, started_at, target_seconds, focused_seconds, record_date
)
values
  ('a5100000-0000-4000-8000-000000000001', 'a5000000-0000-4000-8000-000000000001',
    (select plot_id from farm_a where plot_index = 1), '10000000-0000-4000-8000-000000000001',
    'focusing', statement_timestamp(), 600, 15, current_date),
  ('a5100000-0000-4000-8000-000000000002', 'a5000000-0000-4000-8000-000000000001',
    (select plot_id from farm_a where plot_index = 2), '10000000-0000-4000-8000-000000000002',
    'ripe', statement_timestamp(), 1200, 1200, current_date),
  ('a5100000-0000-4000-8000-000000000003', 'a5000000-0000-4000-8000-000000000001',
    (select plot_id from farm_a where plot_index = 3), '10000000-0000-4000-8000-000000000003',
    'harvested', statement_timestamp(), 1800, 1800, current_date),
  ('a5100000-0000-4000-8000-000000000004', 'a5000000-0000-4000-8000-000000000001',
    (select plot_id from farm_a where plot_index = 4), '10000000-0000-4000-8000-000000000004',
    'seed_saved', statement_timestamp(), 2700, 0, current_date);

set local role authenticated;
set local request.jwt.claim.sub = 'a5000000-0000-4000-8000-000000000001';
select results_eq(
  $$select plot_index, farm_status from public.get_my_farm() where plot_index <= 5$$,
  $$values
    (1, 'growing'::text),
    (2, 'ripe'::text),
    (3, 'harvested'::text),
    (4, 'empty'::text),
    (5, 'empty'::text)$$,
  'session states project to farm display states'
);
select results_eq(
  $$select session_id, session_status from public.get_my_farm() where plot_index = 1$$,
  $$values ('a5100000-0000-4000-8000-000000000001'::uuid, 'focusing'::text)$$,
  'active session identity is included'
);
select results_eq(
  $$select crop_id, crop_name, target_seconds from public.get_my_farm() where plot_index = 1$$,
  $$values ('10000000-0000-4000-8000-000000000001'::uuid, '새싹채소'::text, 600)$$,
  'crop display data uses the session snapshot and catalog name'
);
select ok(
  (select session_id is null and session_status is null and crop_id is null and crop_name is null and target_seconds is null
   from public.get_my_farm() where plot_index = 4),
  'seed_saved does not occupy a plot projection'
);
select is((select count(*) from public.get_my_farm()), 12::bigint, 'one row is returned per plot');
select is((select count(distinct plot_id) from public.get_my_farm()), 12::bigint, 'joins do not duplicate plots');

reset role;
update public.focus_sessions
set status = 'paused', paused_at = statement_timestamp()
where id = 'a5100000-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claim.sub = 'a5000000-0000-4000-8000-000000000001';
select results_eq(
  $$select farm_status, session_status from public.get_my_farm() where plot_index = 1$$,
  $$values ('growing'::text, 'paused'::text)$$,
  'paused sessions remain growing'
);
select is((select farm_status from public.get_my_farm() where plot_index = 2), 'ripe'::text, 'ripe state remains read only');
select is((select farm_status from public.get_my_farm() where plot_index = 3), 'harvested'::text, 'harvested state remains read only');

set local request.jwt.claim.sub = 'a5000000-0000-4000-8000-000000000002';
select is((select count(*) from public.get_my_farm()), 0::bigint, 'other user plots are not exposed');
select is((select count(*) from public.ensure_farm()), 12::bigint, 'second user initializes independently');
select is(
  (select count(*) from public.get_my_farm() as f join farm_a as a on a.plot_id = f.plot_id),
  0::bigint,
  'farm projection contains no foreign plot ids'
);

set local role anon;
select throws_ok(
  $$select * from public.get_my_farm()$$,
  '42501', 'permission denied for function get_my_farm',
  'anonymous call is denied'
);

set local role authenticated;
set local request.jwt.claim.sub = '';
select throws_ok(
  $$select * from public.get_my_farm()$$,
  'PT401', 'UNAUTHENTICATED',
  'missing auth context is rejected'
);

reset role;
select is(
  (select count(*) from pg_catalog.pg_proc where pronamespace = 'public'::regnamespace and proname = 'get_my_farm'),
  1::bigint,
  'get_my_farm is not overloaded'
);

select * from finish();
rollback;
