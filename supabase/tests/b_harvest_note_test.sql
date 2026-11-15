begin;
select plan(23);
insert into auth.users (id, email) values
  ('a8000000-0000-4000-8000-000000000001', 'note-owner@test.local'),
  ('a8000000-0000-4000-8000-000000000002', 'note-other@test.local');
set local request.jwt.claim.sub = 'a8000000-0000-4000-8000-000000000001';
select public.ensure_farm();
create temp table note_session as
select (public.start_focus(id, '10000000-0000-4000-8000-000000000001')->>'session_id')::uuid as id
from public.farm_plots where user_id = auth.uid() and plot_index = 1;
update public.focus_sessions set started_at = clock_timestamp() - interval '1 hour'
where id = (select id from note_session);
select public.finalize_my_focus();
create temp table note_harvest as
select (public.harvest_crop(id)->>'harvest_id')::uuid as id from note_session;

select ok(not exists (
  select 1 from unnest(array['anon', 'service_role']) as r(role_name)
  where has_function_privilege(r.role_name, 'public.save_harvest_note(uuid,text)', 'execute')
), 'anon and service role lack execute');
update public.harvests set note = repeat('나',120) where id = (select id from note_harvest);
update public.harvests set harvested_at = harvested_at + interval '1 second' where id = (select id from note_harvest);
select is((select note from public.harvests), repeat('나',120), 'unrelated update preserves legacy note');
select ok(not has_table_privilege('authenticated', 'public.harvests', 'UPDATE'), 'direct update denied');
grant select on note_harvest to authenticated;
set local role authenticated;
select is(public.save_harvest_note((select id from note_harvest), '자살'),
  '{"saved":false,"guidance_required":true}'::jsonb, 'guidance leaves legacy note untouched');
select is((select note from public.harvests), repeat('나',120), 'legacy note retained');
select is(public.save_harvest_note((select id from note_harvest), E' \t가\n '),
  '{"saved":true,"guidance_required":false}'::jsonb, 'one character accepted');
select is((select note from public.harvests), '가', 'boundary whitespace trimmed');
select is(public.save_harvest_note((select id from note_harvest), repeat('나',50)),
  '{"saved":true,"guidance_required":false}'::jsonb, 'edit accepts maximum length');
select is(public.save_harvest_note((select id from note_harvest), repeat('나',50)),
  '{"saved":true,"guidance_required":false}'::jsonb, 'same note retry succeeds');
select is(public.save_harvest_note((select id from note_harvest), '예시: ' || phrase),
  '{"saved":false,"guidance_required":true}'::jsonb, 'detects initial candidate ' || ordinal)
from unnest(array['죽고 싶','자살','사라지고 싶','살기 싫','끝내고 싶']) with ordinality as c(phrase, ordinal);
select is((select note from public.harvests), repeat('나',50), 'all detections preserve the saved note');
select throws_ok($$select public.save_harvest_note(id, '') from note_harvest$$,
  'PT400', '수확 ID와 메모가 필요합니다.', 'empty note rejected');
select throws_ok($$select public.save_harvest_note(id, E' \t\n') from note_harvest$$,
  'PT400', '수확 ID와 메모가 필요합니다.', 'whitespace note rejected');
select throws_ok($$select public.save_harvest_note(id, repeat('가',51)) from note_harvest$$,
  'PT400', '메모는 50자까지 입력할 수 있습니다.', 'overlong note rejected');
select throws_ok($$select public.save_harvest_note(gen_random_uuid(), 'a')$$,
  'PT404', '수확 기록을 찾을 수 없습니다.', 'missing harvest rejected');
set local request.jwt.claim.sub = 'a8000000-0000-4000-8000-000000000002';
select throws_ok($$select public.save_harvest_note(id, 'a') from note_harvest$$,
  'PT404', '수확 기록을 찾을 수 없습니다.', 'foreign harvest rejected');
set local role authenticated;
select is((select count(*) from public.harvests where note is not null), 0::bigint, 'RLS hides foreign note');
reset role;
set local request.jwt.claim.sub = '';
select throws_ok($$select public.save_harvest_note(id, 'a') from note_harvest$$,
  'PT401', '로그인이 필요합니다.', 'missing auth context rejected');
select is((select note from public.harvests), repeat('나',50), 'failed requests preserve last successful note');
select * from finish();
rollback;
