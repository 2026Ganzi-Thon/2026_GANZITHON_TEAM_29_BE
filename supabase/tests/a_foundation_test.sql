begin;

select plan(37);

select has_table('public', 'profiles', 'profiles table exists');
select col_type_is('public', 'profiles', 'id', 'uuid', 'profiles.id is uuid');
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and confrelid = 'auth.users'::regclass
      and contype = 'f'
      and confdeltype = 'c'
  ),
  'profiles.id references auth.users with cascade delete'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.profiles'::regclass),
  'profiles has RLS enabled'
);
select has_table('public', 'crops', 'crops table exists');
select col_type_is('public', 'crops', 'id', 'uuid', 'crops.id is uuid');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.crops'::regclass),
  'crops has RLS enabled'
);
select ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'auth.users'::regclass
      and tgname = 'on_auth_user_created'
      and not tgisinternal
  ),
  'auth user profile trigger exists'
);

insert into auth.users (id, email, raw_user_meta_data)
values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'profile-a@test.local', '{"nickname":"테스트농부"}'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'profile-b@test.local', '{}');

select is(
  (select count(*) from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  1::bigint,
  'signup trigger creates a profile'
);
select is(
  (select id from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid,
  'profile id matches auth user id'
);
select is(
  (select nickname from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  '테스트농부'::text,
  'signup metadata nickname is copied as display data'
);
select is(
  (select nickname from public.profiles where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  '농부'::text,
  'missing nickname uses safe fallback'
);
select lives_ok(
  $$
    insert into auth.users (id, email, raw_user_meta_data)
    values (
      'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      'profile-c@test.local',
      jsonb_build_object('nickname', repeat('가', 100))
    )
  $$,
  'long nickname metadata does not block signup'
);
select is(
  (select char_length(nickname) from public.profiles where id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'),
  30,
  'long nickname is truncated to MVP maximum'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true);

select is(
  (select count(*) from public.profiles),
  1::bigint,
  'authenticated user can select only own profile'
);
select is(
  (select count(*) from public.profiles where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  0::bigint,
  'authenticated user cannot select another profile'
);
select results_eq(
  $$select nickname, timezone, onboarded, onboarded_at from public.get_my_profile()$$,
  $$values ('테스트농부'::text, 'Asia/Seoul'::text, false, null::timestamptz)$$,
  'get_my_profile returns the fixed public response'
);

reset role;
set local role anon;
select set_config('request.jwt.claim.sub', '', true);

select throws_ok(
  $$select * from public.profiles$$,
  '42501',
  'permission denied for table profiles',
  'anonymous user cannot read profiles'
);
select throws_ok(
  $$select * from public.get_my_profile()$$,
  '42501',
  'permission denied for function get_my_profile',
  'anonymous user cannot execute get_my_profile'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true);

select ok(
  public.complete_onboarding() is not null,
  'first onboarding completion returns a timestamp'
);
select is(
  public.complete_onboarding(),
  (select onboarded_at from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  'repeated onboarding keeps the original timestamp'
);

reset role;
select ok(
  (select onboarded_at is null from public.profiles where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  'onboarding does not change another user profile'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true);
select throws_ok(
  $$update public.profiles set nickname = '변경' where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$$,
  '42501',
  'permission denied for table profiles',
  'authenticated user cannot update profiles directly'
);

reset role;
set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select public.complete_onboarding()$$,
  '42501',
  'permission denied for function complete_onboarding',
  'anonymous user cannot execute complete_onboarding'
);

reset role;
select is((select count(*) from public.crops), 6::bigint, 'catalog contains exactly six crops');
select results_eq(
  $$select name, target_seconds, energy_level, sort_order from public.crops order by sort_order$$,
  $$values
    ('새싹채소'::text, 600, 'low'::text, 1),
    ('당근'::text, 1200, 'low'::text, 2),
    ('딸기'::text, 1800, 'medium'::text, 3),
    ('옥수수'::text, 2700, 'medium'::text, 4),
    ('토마토'::text, 3600, 'high'::text, 5),
    ('호박'::text, 5400, 'high'::text, 6)
  $$,
  'catalog values and order are stable'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true);
select results_eq(
  $$select name from public.list_crops('low') where recommended order by sort_order$$,
  $$values ('새싹채소'::text), ('당근'::text)$$,
  'low energy recommends low crops'
);
select results_eq(
  $$select name from public.list_crops('medium') where recommended order by sort_order$$,
  $$values ('딸기'::text), ('옥수수'::text)$$,
  'medium energy recommends medium crops'
);
select results_eq(
  $$select name from public.list_crops('high') where recommended order by sort_order$$,
  $$values ('토마토'::text), ('호박'::text)$$,
  'high energy recommends high crops'
);
select is(
  (select count(*) from public.list_crops(null) where recommended),
  0::bigint,
  'null energy returns no recommendations'
);
select is(
  (select count(*) from public.list_crops(null)),
  6::bigint,
  'null energy still returns all active crops'
);
select throws_ok(
  $$select * from public.list_crops('invalid')$$,
  '22023',
  'INVALID_INPUT',
  'invalid energy is rejected'
);
select throws_ok(
  $$update public.crops set target_seconds = 1 where name = '당근'$$,
  '42501',
  'permission denied for table crops',
  'authenticated user cannot update crops'
);
select ok(
  has_function_privilege('authenticated', 'public.get_my_profile()', 'execute'),
  'authenticated can execute get_my_profile'
);
select ok(
  has_function_privilege('authenticated', 'public.complete_onboarding()', 'execute'),
  'authenticated can execute complete_onboarding'
);
select ok(
  has_function_privilege('authenticated', 'public.list_crops(text)', 'execute'),
  'authenticated can execute list_crops'
);

reset role;
set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select * from public.list_crops('low')$$,
  '42501',
  'permission denied for function list_crops',
  'anonymous user cannot execute list_crops'
);

reset role;

select * from finish();
rollback;
