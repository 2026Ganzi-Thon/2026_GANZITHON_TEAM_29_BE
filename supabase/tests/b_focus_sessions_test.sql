begin;
select plan(27);
insert into auth.users (id,email) values ('a4000000-0000-4000-8000-000000000001','focus-sql@test.local');
set local request.jwt.claim.sub = 'a4000000-0000-4000-8000-000000000001';
set local role authenticated;
create temp table focus_plots as select * from public.ensure_farm();
select is(public.get_active_focus()->'session', 'null'::jsonb, 'no active session');
create temp table focus_result as
select public.start_focus(plot_id, '10000000-0000-4000-8000-000000000001') as data
from focus_plots where plot_index = 1;
select is((select data->>'status' from focus_result), 'focusing', 'start returns focusing');
select is((select target_seconds from public.focus_sessions), 600, 'target copied from catalog');
select is((select record_date from public.focus_sessions),
  (select (started_at at time zone 'Asia/Seoul')::date from public.focus_sessions), 'local start date');
select is(public.get_active_focus() ->> 'show_overwork_notice', 'false', 'temporary active overwork fallback');
select throws_ok(
  $$select public.start_focus(plot_id, '10000000-0000-4000-8000-000000000001') from focus_plots where plot_index = 2$$,
  'PT409', '이미 진행 중인 집중 세션이 있습니다.', 'second active start rejected'
);
select is((select public.pause_focus(id)->>'status' from public.focus_sessions), 'paused', 'pauses');
reset role;
update public.focus_sessions
set started_at = statement_timestamp() - interval '25 hours 2 minutes',
    paused_at = statement_timestamp() - interval '25 hours';
set local role authenticated;
select is(public.get_active_focus()->'session', 'null'::jsonb, 'expired pause hidden');
select is((select status from public.focus_sessions), 'paused', 'read does not finalize pause');
select throws_ok($$select public.resume_focus(id) from public.focus_sessions$$,
  'PT409', '일시정지한 지 24시간이 지나 집중을 재개할 수 없습니다.', 'expired resume rejected');
reset role;
update public.focus_sessions
set started_at = statement_timestamp() - interval '10 minutes',
    paused_at = statement_timestamp() - interval '8 minutes';
set local role authenticated;
select is((select public.resume_focus(id)->>'remaining_seconds' from public.focus_sessions), '480',
  'resume excludes the full paused duration');
select ok((select paused_duration >= interval '8 minutes' from public.focus_sessions), 'pause accumulated');
reset role;
update public.focus_sessions set started_at = started_at - interval '1 hour';
set local role authenticated;
select is(public.get_active_focus()->'session', 'null'::jsonb, 'target reached hidden');
select is((select status from public.focus_sessions), 'focusing', 'read does not finalize completion');
select throws_ok($$select public.pause_focus(id) from public.focus_sessions$$,
  'PT409', '현재 상태에서는 집중을 일시정지할 수 없습니다.', 'completed focus cannot pause');
select throws_ok(
  $$select public.start_focus(plot_id, '10000000-0000-4000-8000-000000000001') from focus_plots where plot_index = 1$$,
  'PT409', '이미 작물이 있는 밭입니다.', 'ripe plot cannot be replanted'
);
select is((select status from public.focus_sessions), 'focusing', 'failed start rolls back finalization');
select is(
  (select public.start_focus(plot_id, '10000000-0000-4000-8000-000000000001')->>'status'
   from focus_plots where plot_index = 2), 'focusing', 'completed session releases active slot'
);
select is((select focused_seconds from public.focus_sessions where status = 'ripe'), 600, 'ripe time capped at target');
reset role;
update public.focus_sessions
set status = 'paused', paused_at = statement_timestamp() - interval '23 hours 59 minutes',
    started_at = statement_timestamp() - interval '23 hours 59 minutes'
where status = 'focusing';
set local role authenticated;
select is(public.finalize_my_focus(), null::jsonb, 'pause below 24 hours stays active');
select is((select count(*) from public.focus_sessions where status = 'paused'), 1::bigint, 'unexpired row remains paused');
reset role;
update public.focus_sessions
set paused_at = statement_timestamp() - interval '24 hours',
    started_at = statement_timestamp() - interval '24 hours'
where status = 'paused';
set local role authenticated;
select is(public.finalize_my_focus()->>'status', 'seed_saved', '24-hour pause expires');
select is((select focused_seconds from public.focus_sessions where status = 'seed_saved'), 0, 'zero seconds preserved');
select is(public.finalize_my_focus(), null::jsonb, 'repeated finalization does nothing');
select is(
  (select public.start_focus(plot_id, '10000000-0000-4000-8000-000000000001')->>'status'
   from focus_plots where plot_index = 2), 'focusing', 'seed_saved leaves plot reusable'
);
reset role;
update public.focus_sessions
set status = 'paused', paused_at = statement_timestamp() - interval '24 hours',
    started_at = statement_timestamp() - interval '24 hours 10 minutes'
where status = 'focusing';
set local role authenticated;
select is(public.finalize_my_focus()->>'status', 'ripe', 'target reached takes precedence over expired pause');
select is((select count(*) from public.focus_sessions where status = 'ripe'), 2::bigint, 'both ripe plots persist');
select * from finish();
rollback;
