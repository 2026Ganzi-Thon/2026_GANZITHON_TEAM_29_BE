begin;
select plan(17);
insert into auth.users(id,email) values ('a6000000-0000-4000-8000-000000000001','harvest@test.local');
set local request.jwt.claim.sub = 'a6000000-0000-4000-8000-000000000001';
set local role authenticated;
create temp table harvest_plots as select * from public.ensure_farm();
create temp table harvest_session as
select (public.start_focus(plot_id,'10000000-0000-4000-8000-000000000001')->>'session_id')::uuid as id
from harvest_plots where plot_index=1;
select throws_ok($$select public.harvest_crop(id) from harvest_session$$,
 'PT409','현재 상태에서는 작물을 수확할 수 없습니다.','growing crop cannot be harvested');
reset role;
update public.focus_sessions set started_at = clock_timestamp() - interval '2 days 10 minutes';
set local role authenticated;
select is(public.finalize_my_focus()->>'status','ripe','completion leaves a ripe crop');
select ok((select auto_harvest_at = (((ripe_at at time zone 'Asia/Seoul')::date + 1)::timestamp at time zone 'Asia/Seoul')
 from public.focus_sessions),'deadline at next local midnight');
select throws_ok($$select public.start_focus(plot_id,'10000000-0000-4000-8000-000000000001')
 from harvest_plots where plot_index=1$$,'PT409','이미 작물이 있는 밭입니다.','ripe occupies plot');
select is((select public.harvest_crop(id)->>'auto_harvested' from harvest_session),'true','late manual request is classified as auto');
select is((select status from public.focus_sessions),'harvested','session finalized');
select is((select count(*) from public.harvests),1::bigint,'one record');
select is((select public.ack_auto_harvest_notice(array[id,id])->>'acknowledged_count' from public.harvests),
 '1','duplicate IDs acknowledged once');
select is((select public.ack_auto_harvest_notice(array[id])->>'acknowledged_count' from public.harvests),
 '0','ack retry is idempotent');
select is((select public.start_focus(plot_id,'10000000-0000-4000-8000-000000000001')->>'status'
 from harvest_plots where plot_index=1),'focusing','harvested plot reusable');
select ok(not has_function_privilege('authenticated','public.process_due_harvests()','execute'),'worker not callable by clients');
reset role;
update public.focus_sessions set started_at = clock_timestamp() - interval '2 days 10 minutes' where status='focusing';
select is(public.process_due_harvests()->>'processed_count','1','worker finalizes and harvests offline completion');
select is(public.process_due_harvests()->>'processed_count','0','worker retry creates no duplicate');
set local role authenticated;
create temp table manual_session as
select (public.start_focus(plot_id,'10000000-0000-4000-8000-000000000001')->>'session_id')::uuid as id
from harvest_plots where plot_index=1;
reset role;
update public.focus_sessions set status='ripe', focused_seconds=target_seconds
where id=(select id from manual_session);
set local role authenticated;
select is((select public.harvest_crop(id)->>'auto_harvested' from manual_session),
 'false','harvest before deadline is manual');
select throws_ok($$select public.ack_auto_harvest_notice(array[id]) from public.harvests where not auto_harvested$$,
 'PT404','자동 수확 기록을 찾을 수 없습니다.','manual harvest has no auto notice');

create temp table preview_session as
select (public.start_focus(plot_id,'10000000-0000-4000-8000-000000000001')->>'session_id')::uuid as id
from harvest_plots where plot_index=1;
create temp table harvest_preview as
select public.preview_stop_focus(id) from preview_session;
reset role;
update public.focus_sessions set started_at=clock_timestamp()-interval '2 days 10 minutes'
where id=(select id from preview_session);
select is(public.process_due_harvests()->>'processed_count','0','worker respects live stop preview');
select is((select status from public.focus_sessions where id=(select id from preview_session)),
 'focusing','preview keeps focus state');
select * from finish();
rollback;
