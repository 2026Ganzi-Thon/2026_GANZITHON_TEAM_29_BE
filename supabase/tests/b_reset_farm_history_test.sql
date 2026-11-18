begin;
select no_plan();
select has_function('public','reset_farm_history',array[]::text[],'reset exists without parameters');
select ok(has_function_privilege('authenticated','public.reset_farm_history()','execute'),'authenticated reset allowed');
select ok(not has_function_privilege('anon','public.reset_farm_history()','execute'),'anon denied');
select ok(not has_function_privilege('service_role','public.reset_farm_history()','execute'),'service_role denied');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.reset_farm_history()'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'PUBLIC execute denied');
select ok((select prosecdef and proconfig=array['search_path=""'] from pg_proc where oid='public.reset_farm_history()'::regprocedure),'definer with empty search_path');
insert into auth.users(id,email) values
 ('a8000000-0000-4000-8000-000000000001','reset-a@test.local'),
 ('a8000000-0000-4000-8000-000000000002','reset-b@test.local');
select set_config('request.jwt.claim.sub','a8000000-0000-4000-8000-000000000001',true);
select is(public.reset_farm_history(),'{"success":true}'::jsonb,'uninitialized farm reset succeeds');
select is((select count(*) from public.farm_plots where user_id=auth.uid()),12::bigint,'missing farm initialized through ensure_farm');
select public.complete_onboarding();
create temp table preserved_profile as select to_jsonb(p) data from public.profiles p where id=auth.uid();
create temp table preserved_plots as select id,plot_index from public.farm_plots where user_id=auth.uid();
select set_config('request.jwt.claim.sub','a8000000-0000-4000-8000-000000000002',true);
select public.ensure_farm();
insert into public.focus_sessions(id,user_id,plot_id,crop_id,status,started_at,target_seconds,focused_seconds,record_date)
select ('a8100000-0000-4000-8000-'||lpad(plot_index::text,12,'0'))::uuid,
 user_id,id,'10000000-0000-4000-8000-000000000001',
 case plot_index when 1 then 'focusing' when 2 then 'ripe' when 3 then 'harvested' else 'seed_saved' end,
 now(),600,case when plot_index=1 then 0 else 600 end,current_date
from public.farm_plots where user_id='a8000000-0000-4000-8000-000000000001' and plot_index<=4;
insert into public.focus_sessions(id,user_id,plot_id,crop_id,status,started_at,target_seconds,focused_seconds,record_date)
select 'a8200000-0000-4000-8000-000000000001',user_id,id,'10000000-0000-4000-8000-000000000001','harvested',now(),600,600,current_date
from public.farm_plots where user_id=auth.uid() and plot_index=1;
insert into public.harvests(session_id,harvested_at,auto_harvested,note,rest_ends_at)
select id,now(),true,'메모',now()+interval '5 minutes' from public.focus_sessions where status='harvested';
insert into private.overwork_notices(user_id,local_date,claimed_at)
select id,current_date,now() from public.profiles where id::text like 'a8000000-%';
select set_config('request.jwt.claim.sub','a8000000-0000-4000-8000-000000000001',true);
create temp table previous_token as select public.preview_stop_focus('a8100000-0000-4000-8000-000000000001')->>'stop_token' token;
create temp table foreign_data as select
 (select jsonb_agg(to_jsonb(s)) from public.focus_sessions s where user_id='a8000000-0000-4000-8000-000000000002') sessions,
 (select jsonb_agg(to_jsonb(h)) from public.harvests h join public.focus_sessions s on s.id=h.session_id where s.user_id='a8000000-0000-4000-8000-000000000002') harvests;
select is(public.reset_farm_history(),'{"success":true}'::jsonb,'populated reset succeeds');
select is((select count(*) from public.focus_sessions where user_id=auth.uid()),0::bigint,'all session states deleted');
select is((select count(*) from public.harvests h where session_id::text like 'a8100000-%'),0::bigint,'harvests notes notices and rests cascaded');
select is((select count(*) from private.focus_stop_previews where user_id=auth.uid()),0::bigint,'preview tokens cascaded');
select is((select count(*) from private.overwork_notices where user_id=auth.uid()),0::bigint,'overwork notices deleted');
select is((select to_jsonb(p) from public.profiles p where id=auth.uid()),(select data from preserved_profile),'profile nickname timezone onboarding unchanged');
select results_eq($$select id,plot_index from public.farm_plots where user_id=auth.uid() order by id$$,$$select id,plot_index from preserved_plots order by id$$,'plot identities unchanged');
select is((select count(*) from auth.users where id=auth.uid()),1::bigint,'auth user preserved');
select is((select count(*) from public.crops),6::bigint,'crop catalog preserved');
select is((select count(*) from public.get_my_farm() where farm_status='empty' and session_id is null),12::bigint,'farm empty');
select is(public.get_active_focus()->'session','null'::jsonb,'no active session');
select is((select jsonb_agg(to_jsonb(s)) from public.focus_sessions s where user_id='a8000000-0000-4000-8000-000000000002'),(select sessions from foreign_data),'other user sessions untouched');
select is((select jsonb_agg(to_jsonb(h)) from public.harvests h join public.focus_sessions s on s.id=h.session_id where s.user_id='a8000000-0000-4000-8000-000000000002'),(select harvests from foreign_data),'other user harvests and notes untouched');
select is((select count(*) from private.overwork_notices where user_id='a8000000-0000-4000-8000-000000000002'),1::bigint,'other overwork state untouched');
select throws_ok($$select public.confirm_stop_focus(token) from previous_token$$,'PT404','중도 종료 토큰을 찾을 수 없습니다.','old token unusable');
select is(public.reset_farm_history(),'{"success":true}'::jsonb,'empty retry succeeds');
select is(public.process_due_harvests()->>'processed_count','0','worker cannot recreate deleted records');
select is(public.get_focus_history('today')->'summary','{"focused_seconds":0,"seed_count":0,"harvest_count":0}'::jsonb,'today totals zero');
select is(public.get_focus_history('week')->'summary','{"focused_seconds":0,"seed_count":0,"harvest_count":0}'::jsonb,'week totals zero');
select is(public.get_focus_history('all')->'items','[]'::jsonb,'all empty array');
select is(public.get_focus_history('all')->'capabilities','{"harvest_count":true}'::jsonb,'harvest capability retained');
select public.start_focus((select id from preserved_plots where plot_index=1),'10000000-0000-4000-8000-000000000001');
select is((select count(*) from public.focus_sessions where user_id=auth.uid()),1::bigint,'new focus can start');
select public.pause_focus((select id from public.focus_sessions where user_id=auth.uid()));
select is(public.reset_farm_history(),'{"success":true}'::jsonb,'paused session reset succeeds');
select is((select count(*) from public.focus_sessions where user_id=auth.uid()),0::bigint,'paused session deleted');

-- Force a deletion failure after overwork deletion; the whole RPC must roll back.
select public.start_focus((select id from preserved_plots where plot_index=1),'10000000-0000-4000-8000-000000000001');
insert into private.overwork_notices values (auth.uid(),current_date,now());
create function pg_temp.fail_reset_delete() returns trigger language plpgsql as $$begin raise exception 'forced reset failure'; end$$;
create trigger reset_failure before delete on public.focus_sessions for each row execute function pg_temp.fail_reset_delete();
select throws_ok($$select public.reset_farm_history()$$,'P0001','forced reset failure','failure propagates');
select is((select count(*) from private.overwork_notices where user_id=auth.uid()),1::bigint,'failure restores earlier overwork deletion');
select is((select count(*) from public.focus_sessions where user_id=auth.uid()),1::bigint,'failure keeps session');
drop trigger reset_failure on public.focus_sessions;

set local role anon;
select throws_ok($$select public.reset_farm_history()$$,'42501','permission denied for function reset_farm_history','anonymous invocation blocked');
reset role;
set local role service_role;
select throws_ok($$select public.reset_farm_history()$$,'42501','permission denied for function reset_farm_history','service_role invocation blocked');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','',true);
select throws_ok($$select public.reset_farm_history()$$,'PT401','UNAUTHENTICATED','missing auth context');
select set_config('request.jwt.claim.sub','a8000000-0000-4000-8000-000000000099',true);
select throws_ok($$select public.reset_farm_history()$$,'PT404','NOT_FOUND','missing profile');
reset role;
select ok(not has_table_privilege('authenticated','public.focus_sessions','delete'),'no direct session DELETE grant');
select * from finish();
rollback;
