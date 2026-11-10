begin;

select plan(72);

-- Schema and integrity
select has_table('public', 'profiles', 'profiles table exists');
select col_type_is('public', 'profiles', 'id', 'uuid', 'profiles.id is uuid');
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and confrelid = 'auth.users'::regclass
      and contype = 'f'
      and confdeltype = 'c'
  ),
  'profiles.id references auth.users with cascade delete'
);
select ok((select relrowsecurity from pg_class where oid = 'public.profiles'::regclass), 'profiles has RLS enabled');
select has_table('public', 'crops', 'crops table exists');
select col_type_is('public', 'crops', 'id', 'uuid', 'crops.id is uuid');
select ok((select relrowsecurity from pg_class where oid = 'public.crops'::regclass), 'crops has RLS enabled');
select ok(
  exists (
    select 1 from pg_trigger
    where tgrelid = 'auth.users'::regclass
      and tgname = 'on_auth_user_created'
      and not tgisinternal
  ),
  'auth user profile trigger exists'
);
select ok(
  exists (
    select 1 from pg_index
    where indrelid = 'public.profiles'::regclass
      and indisprimary
      and indkey::text = '1'
  ),
  'profiles.id primary key also indexes the auth foreign key'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.crops'::regclass and conname = 'crops_name_unique' and contype = 'u'
  ),
  'crop names are unique'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.crops'::regclass and conname = 'crops_sort_order_unique' and contype = 'u'
  ),
  'crop sort order is unique'
);
select col_default_is('public', 'profiles', 'nickname', '농부', 'nickname has the safe fallback default');
select col_default_is('public', 'profiles', 'timezone', 'Asia/Seoul', 'timezone defaults to Asia/Seoul');
select ok(
  (select column_default is not null from information_schema.columns
   where table_schema = 'public' and table_name = 'profiles' and column_name = 'created_at'),
  'created_at has a database default'
);

-- Trigger input boundaries
insert into auth.users (id, email, raw_user_meta_data)
values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'profile-a@test.local', '{"nickname":"테스트🌱농부"}'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'profile-b@test.local', '{}'),
  ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'profile-d@test.local', '{"nickname":""}'),
  ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'profile-e@test.local', '{"nickname":"   "}'),
  ('ffffffff-ffff-4fff-8fff-ffffffffffff', 'profile-f@test.local', jsonb_build_object('nickname', repeat('가', 30)));

select is((select count(*) from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 1::bigint, 'signup trigger creates one profile');
select is((select id from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid, 'profile id matches auth user id');
select is((select nickname from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), '테스트🌱농부'::text, 'unicode nickname is preserved');
select is((select nickname from public.profiles where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'), '농부'::text, 'missing nickname uses fallback');
select is((select nickname from public.profiles where id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'), '농부'::text, 'empty nickname uses fallback');
select is((select nickname from public.profiles where id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'), '농부'::text, 'space-only nickname uses fallback');
select is((select char_length(nickname) from public.profiles where id = 'ffffffff-ffff-4fff-8fff-ffffffffffff'), 30, '30-character nickname is preserved');
select lives_ok(
  $$insert into auth.users (id, email, raw_user_meta_data)
    values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'profile-c@test.local', jsonb_build_object('nickname', repeat('가', 31)))$$,
  'overlong nickname does not block signup'
);
select is((select char_length(nickname) from public.profiles where id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'), 30, 'overlong nickname is truncated to 30 characters');

insert into auth.users (id, email) values ('11111111-1111-4111-8111-111111111111', 'cascade@test.local');
select is((select count(*) from public.profiles where id = '11111111-1111-4111-8111-111111111111'), 1::bigint, 'cascade test profile exists before auth deletion');
delete from auth.users where id = '11111111-1111-4111-8111-111111111111';
select is((select count(*) from public.profiles where id = '11111111-1111-4111-8111-111111111111'), 0::bigint, 'auth user deletion cascades to profile');

insert into auth.users (id, email) values ('22222222-2222-4222-8222-222222222222', 'missing@test.local');
delete from public.profiles where id = '22222222-2222-4222-8222-222222222222';

-- RLS and profile RPC. These role/claim tests simulate PostgREST inside SQL.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true);

select is((select count(*) from public.profiles), 1::bigint, 'authenticated user can select only own profile');
select is((select count(*) from public.profiles where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'), 0::bigint, 'authenticated user cannot select another profile');
select results_eq(
  $$select nickname, timezone, onboarded, onboarded_at from public.get_my_profile()$$,
  $$values ('테스트🌱농부'::text, 'Asia/Seoul'::text, false, null::timestamptz)$$,
  'get_my_profile returns the fixed public response'
);
select throws_ok(
  $$insert into public.profiles (id) values ('33333333-3333-4333-8333-333333333333')$$,
  '42501', 'permission denied for table profiles', 'authenticated user cannot insert profiles directly'
);
select throws_ok(
  $$update public.profiles set nickname = '변경' where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$$,
  '42501', 'permission denied for table profiles', 'authenticated user cannot update profiles directly'
);
select throws_ok(
  $$delete from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$$,
  '42501', 'permission denied for table profiles', 'authenticated user cannot delete profiles directly'
);

reset role;
set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select throws_ok($$select * from public.profiles$$, '42501', 'permission denied for table profiles', 'anonymous user cannot read profiles');
select throws_ok($$select * from public.get_my_profile()$$, '42501', 'permission denied for function get_my_profile', 'anonymous user cannot execute get_my_profile');
select throws_ok($$select * from public.crops$$, '42501', 'permission denied for table crops', 'anonymous user cannot read crops');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
select throws_ok($$select * from public.get_my_profile()$$, 'PT401', 'UNAUTHENTICATED', 'profile RPC uses agreed unauthenticated business message');
select throws_ok($$select public.complete_onboarding()$$, 'PT401', 'UNAUTHENTICATED', 'onboarding RPC uses agreed unauthenticated business message');
select throws_ok($$select * from public.list_crops(null)$$, 'PT401', 'UNAUTHENTICATED', 'crop RPC uses agreed unauthenticated business message');

select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
select throws_ok($$select * from public.get_my_profile()$$, 'PT404', 'NOT_FOUND', 'missing profile uses agreed not-found business message');
select throws_ok($$select public.complete_onboarding()$$, 'PT404', 'NOT_FOUND', 'missing onboarding profile uses agreed not-found business message');

reset role;
create temporary table onboarding_first (completed_at timestamptz not null);
grant select, insert on table onboarding_first to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true);
insert into onboarding_first values (public.complete_onboarding());
select ok((select completed_at is not null from onboarding_first), 'first onboarding returns a timestamp');
select is(public.complete_onboarding(), (select completed_at from onboarding_first), 'repeated onboarding keeps the first timestamp');

reset role;
select ok((select onboarded_at is null from public.profiles where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'), 'onboarding does not change another user profile');

-- Crop catalog and RPC
select is((select count(*) from public.crops), 6::bigint, 'catalog contains exactly six crops');
select results_eq(
  $$select id, name, target_seconds, energy_level, sort_order from public.crops order by sort_order$$,
  $$values
    ('10000000-0000-4000-8000-000000000001'::uuid, '새싹채소'::text, 600, 'low'::text, 1),
    ('10000000-0000-4000-8000-000000000002'::uuid, '당근'::text, 1200, 'low'::text, 2),
    ('10000000-0000-4000-8000-000000000003'::uuid, '딸기'::text, 1800, 'medium'::text, 3),
    ('10000000-0000-4000-8000-000000000004'::uuid, '옥수수'::text, 2700, 'medium'::text, 4),
    ('10000000-0000-4000-8000-000000000005'::uuid, '토마토'::text, 3600, 'high'::text, 5),
    ('10000000-0000-4000-8000-000000000006'::uuid, '호박'::text, 5400, 'high'::text, 6)$$,
  'catalog UUIDs, values, and order are stable'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true);
select results_eq($$select name from public.list_crops('low') where recommended order by sort_order$$, $$values ('새싹채소'::text), ('당근'::text)$$, 'low recommendations match');
select results_eq($$select name from public.list_crops('medium') where recommended order by sort_order$$, $$values ('딸기'::text), ('옥수수'::text)$$, 'medium recommendations match');
select results_eq($$select name from public.list_crops('high') where recommended order by sort_order$$, $$values ('토마토'::text), ('호박'::text)$$, 'high recommendations match');
select is((select count(*) from public.list_crops(null) where recommended), 0::bigint, 'null energy recommends nothing');
select is((select count(*) from public.list_crops(null)), 6::bigint, 'null energy still returns all active crops');
select throws_ok($$select * from public.list_crops('invalid')$$, '22023', 'INVALID_INPUT', 'invalid energy is rejected');
select throws_ok($$insert into public.crops (name, target_seconds, energy_level, sort_order) values ('침입', 1, 'low', 99)$$, '42501', 'permission denied for table crops', 'authenticated user cannot insert crops');
select throws_ok($$update public.crops set target_seconds = 1 where name = '당근'$$, '42501', 'permission denied for table crops', 'authenticated user cannot update crops');
select throws_ok($$delete from public.crops where name = '당근'$$, '42501', 'permission denied for table crops', 'authenticated user cannot delete crops');

-- Function privilege and security mode audit
reset role;
select ok(has_function_privilege('authenticated', 'public.get_my_profile()', 'execute'), 'authenticated can execute get_my_profile');
select ok(has_function_privilege('authenticated', 'public.complete_onboarding()', 'execute'), 'authenticated can execute complete_onboarding');
select ok(has_function_privilege('authenticated', 'public.list_crops(text)', 'execute'), 'authenticated can execute list_crops');
select ok(not has_function_privilege('anon', 'public.get_my_profile()', 'execute'), 'anon cannot execute get_my_profile');
select ok(not has_function_privilege('anon', 'public.complete_onboarding()', 'execute'), 'anon cannot execute complete_onboarding');
select ok(not has_function_privilege('anon', 'public.list_crops(text)', 'execute'), 'anon cannot execute list_crops');
select ok(not has_function_privilege('service_role', 'public.get_my_profile()', 'execute'), 'service_role cannot execute get_my_profile');
select ok(not has_function_privilege('service_role', 'public.complete_onboarding()', 'execute'), 'service_role cannot execute complete_onboarding');
select ok(not has_function_privilege('service_role', 'public.list_crops(text)', 'execute'), 'service_role cannot execute list_crops');
select ok(not has_function_privilege('authenticated', 'private.handle_new_user()', 'execute'), 'authenticated cannot execute the trigger function');
select ok(not has_function_privilege('service_role', 'private.handle_new_user()', 'execute'), 'service_role cannot execute the trigger function');
select ok(not has_schema_privilege('authenticated', 'private', 'usage'), 'authenticated cannot use the private schema');
select ok(not has_table_privilege('service_role', 'public.profiles', 'truncate'), 'service_role cannot truncate profiles');
select ok(not has_table_privilege('service_role', 'public.crops', 'truncate'), 'service_role cannot truncate crops');
select ok(
  (select not prosecdef and array_to_string(proconfig, ',') = 'search_path=""' from pg_proc where oid = 'public.get_my_profile()'::regprocedure),
  'get_my_profile is invoker with an empty search_path'
);
select ok(
  (select not prosecdef and array_to_string(proconfig, ',') = 'search_path=""' from pg_proc where oid = 'public.list_crops(text)'::regprocedure),
  'list_crops is invoker with an empty search_path'
);
select ok(
  (select prosecdef and array_to_string(proconfig, ',') = 'search_path=""' from pg_proc where oid = 'public.complete_onboarding()'::regprocedure),
  'complete_onboarding is the only public definer and has an empty search_path'
);
select ok(
  (select prosecdef and array_to_string(proconfig, ',') = 'search_path=""' from pg_proc where oid = 'private.handle_new_user()'::regprocedure),
  'profile trigger is a definer with an empty search_path'
);
select is(
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('get_my_profile', 'complete_onboarding', 'list_crops')),
  3::bigint,
  'public RPC names are not overloaded'
);

select * from finish();
rollback;
