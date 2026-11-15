begin;
select plan(15);
insert into auth.users (id, email) values
  ('a2000000-0000-4000-8000-000000000001', 'rest-owner@test.local'),
  ('a2000000-0000-4000-8000-000000000002', 'rest-other@test.local');
set local request.jwt.claim.sub = 'a2000000-0000-4000-8000-000000000001';
select public.ensure_farm();
insert into public.focus_sessions
  (user_id, plot_id, crop_id, status, started_at, target_seconds, focused_seconds, record_date)
select user_id, id, '10000000-0000-4000-8000-000000000001', 'harvested',
  now() - interval '1 hour', 600, 600, current_date
from public.farm_plots where user_id = auth.uid() and plot_index between 1 and 3;
insert into public.harvests(session_id, harvested_at, auto_harvested)
select s.id, now(), p.plot_index = 3
from public.focus_sessions s join public.farm_plots p on p.id = s.plot_id where s.user_id = auth.uid();

set local role authenticated;
create temp table rest_targets as
select p.plot_index, h.id from public.harvests h
join public.focus_sessions s on s.id = h.session_id
join public.farm_plots p on p.id = s.plot_id;
create temp table history_before_rest as select public.get_focus_history('all') as data;
create temp table first_rest as select public.start_rest(id) as data from rest_targets where plot_index = 1;
select is((select (data->>'rest_ends_at')::timestamptz - (data->>'server_now')::timestamptz from first_rest),
  interval '5 minutes', 'first rest lasts exactly five minutes');
create temp table rest_retry as select public.start_rest(id) as data from rest_targets where plot_index = 1;
select is((select data->>'rest_ends_at' from rest_retry),
  (select data->>'rest_ends_at' from first_rest), 'retry retains original end');
select ok((select (r.data->>'server_now')::timestamptz > (f.data->>'server_now')::timestamptz
  from rest_retry r cross join first_rest f), 'retry returns current server time');
select is(public.get_focus_history('all'), (select data from history_before_rest), 'rest leaves history and counts intact');
select throws_ok($$select public.start_rest(id) from rest_targets where plot_index = 2$$,
  'PT409','현재 상태에서는 수확 후 휴식을 시작할 수 없습니다.','second live rest rejected');
select throws_ok($$select public.start_rest(id) from rest_targets where plot_index = 3$$,
  'PT409','현재 상태에서는 수확 후 휴식을 시작할 수 없습니다.','automatic harvest rejected');
select throws_ok($$select public.start_rest(null)$$, 'PT400','수확 ID가 필요합니다.','null ID rejected');
select throws_ok($$select public.start_rest(gen_random_uuid())$$,
  'PT404','수확 기록을 찾을 수 없습니다.','missing harvest rejected');
set local request.jwt.claim.sub = 'a2000000-0000-4000-8000-000000000002';
select throws_ok($$select public.start_rest(id) from rest_targets where plot_index = 1$$,
  'PT404','수확 기록을 찾을 수 없습니다.','foreign harvest rejected');
set local request.jwt.claim.sub = '';
select throws_ok($$select public.start_rest(null)$$, 'PT401','로그인이 필요합니다.','missing auth rejected first');
set local request.jwt.claim.sub = 'a2000000-0000-4000-8000-000000000001';

create temp table new_focus as
select (public.start_focus(id, '10000000-0000-4000-8000-000000000001')->>'session_id')::uuid as id
from public.farm_plots where plot_index = 1;
select is((select public.start_rest(id)->>'rest_ends_at' from rest_targets where plot_index = 1),
  (select data->>'rest_ends_at' from first_rest), 'retry succeeds with active focus');
reset role;
update public.harvests set rest_ends_at = clock_timestamp() - interval '1 minute'
where id = (select id from rest_targets where plot_index = 1);
set local role authenticated;
select is((select (public.start_rest(id)->>'rest_ends_at')::timestamptz from rest_targets where plot_index = 1),
  (select h.rest_ends_at from public.harvests h join rest_targets t using(id) where t.plot_index = 1),
  'expired rest is not restarted');
select throws_ok($$select public.start_rest(id) from rest_targets where plot_index = 2$$,
  'PT409','현재 상태에서는 수확 후 휴식을 시작할 수 없습니다.','focusing blocks new rest');
create temp table paused_focus as select public.pause_focus(id) from new_focus;
select throws_ok($$select public.start_rest(id) from rest_targets where plot_index = 2$$,
  'PT409','현재 상태에서는 수확 후 휴식을 시작할 수 없습니다.','paused focus blocks new rest');
select ok(not has_table_privilege('authenticated','public.harvests','update')
  and not has_function_privilege('anon','public.start_rest(uuid)','execute')
  and not has_function_privilege('service_role','public.start_rest(uuid)','execute'),
  'write access limited to authenticated RPC');
select * from finish();
rollback;
