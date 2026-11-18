begin;
select no_plan();

select has_function('public','get_crop_history',array['text'],'crop history exists');
select is((select provolatile from pg_proc where oid='public.get_crop_history(text)'::regprocedure),'s','STABLE');
select ok((select not prosecdef and proconfig @> array['search_path=""','TimeZone=UTC'] from pg_proc where oid='public.get_crop_history(text)'::regprocedure),'invoker with fixed search path/timezone');
select ok(has_function_privilege('authenticated','public.get_crop_history(text)','execute'),'authenticated execute');
select ok(not has_function_privilege('anon','public.get_crop_history(text)','execute'),'anon denied');
select ok(not has_function_privilege('service_role','public.get_crop_history(text)','execute'),'service role denied');
select ok(not exists(select 1 from pg_proc p, lateral aclexplode(p.proacl) a where p.oid='public.get_crop_history(text)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'PUBLIC denied');
select is((select qual from pg_policies where schemaname='public' and tablename='crops' and policyname='crops_select_active'),'is_active','original active policy retained');
select is((select count(*)::int from pg_policies where schemaname='public' and tablename='crops'),2,'only approved extra policy');
select ok(not has_table_privilege('authenticated','public.crops','insert,update,delete'),'no catalog writes');

insert into auth.users(id,email) values
('ac310000-0000-4000-8000-000000000001','crop-a@test.local'),
('ac310000-0000-4000-8000-000000000002','crop-b@test.local'),
('ac310000-0000-4000-8000-000000000003','crop-paused@test.local'),
('ac310000-0000-4000-8000-000000000004','crop-no-profile@test.local'),
('ac310000-0000-4000-8000-000000000005','crop-empty@test.local');
insert into public.farm_plots(user_id,plot_index)
select id,n from auth.users cross join generate_series(1,12) n where id::text like 'ac310000%';
delete from public.profiles where id='ac310000-0000-4000-8000-000000000004';

insert into public.focus_sessions(user_id,plot_id,crop_id,status,started_at,paused_at,target_seconds,focused_seconds,record_date)
select f.user_id,f.id,('10000000-0000-4000-8000-'||lpad(crop::text,12,'0'))::uuid,
 status,now(),null,600,seconds,case when date_value='today' then (now() at time zone 'Asia/Seoul')::date
 when date_value='yesterday' then (now() at time zone 'Asia/Seoul')::date-1 else date_value::date end
from public.farm_plots f join (values
 (1,1,'seed_saved',0,'today'),(2,2,'seed_saved',10,'today'),(3,2,'ripe',20,'today'),
 (4,2,'harvested',30,'today'),(5,2,'harvested',40,'today'),(6,2,'harvested',50,'today'),
 (7,3,'harvested',60,'yesterday'),(8,4,'seed_saved',70,'2025-11-01'),
 (9,4,'harvested',80,'2026-11-01'),(10,5,'focusing',999,'today')
) as v(plot_index,crop,status,seconds,date_value) using(plot_index)
where f.user_id='ac310000-0000-4000-8000-000000000001';
insert into public.focus_sessions(user_id,plot_id,crop_id,status,started_at,paused_at,target_seconds,focused_seconds,record_date)
select user_id,id,'10000000-0000-4000-8000-000000000006',
case when user_id='ac310000-0000-4000-8000-000000000002' then 'seed_saved' else 'paused' end,
now(),case when user_id='ac310000-0000-4000-8000-000000000003' then now() end,600,700,current_date
from public.farm_plots where user_id in ('ac310000-0000-4000-8000-000000000002','ac310000-0000-4000-8000-000000000003') and plot_index=1;
insert into public.harvests(session_id,harvested_at,auto_harvested)
select s.id,now(),s.focused_seconds=40 from public.focus_sessions s
where s.user_id='ac310000-0000-4000-8000-000000000001' and s.focused_seconds in(30,40,50,80);
update public.crops set is_active=false where sort_order in(1,2,5,6);
insert into public.crops(id,name,target_seconds,energy_level,sort_order,is_active)
values('ac310000-0000-4000-8000-000000000007','unreferenced',600,'low',7,false);

create temp table responses(period text primary key,body jsonb,old_body jsonb);
grant all on responses to authenticated;
create temp table before_read as select
 (select md5(jsonb_agg(to_jsonb(s) order by id)::text) from public.focus_sessions s) as sessions,
 (select md5(jsonb_agg(to_jsonb(h) order by id)::text) from public.harvests h) as harvests;

set local request.jwt.claim.sub='ac310000-0000-4000-8000-000000000001';
set local role authenticated;
insert into responses select p,public.get_crop_history(p),public.get_focus_history(p) from unnest(array['today','week','all']) p;
select is((select body->'summary' from responses where period='all'),'{"focused_seconds":360,"harvest_count":4,"seed_count":3}'::jsonb,'all: finalized only, actual harvests, seed included');
select is((select body->'summary' from responses where period='today'),'{"focused_seconds":150,"harvest_count":3,"seed_count":2}'::jsonb,'today includes 0 seed, ripe and 3 actual harvests');
select is((select body#>'{crop_totals,1}' from responses where period='today'),'{"crop_id":"10000000-0000-4000-8000-000000000002","crop_name":"당근","focused_seconds":150,"harvest_count":3}'::jsonb,'same crop three harvests aggregated once');
select is((select body#>>'{crop_totals,0,focused_seconds}' from responses where period='today'),'0','0-second seed crop retained');
select is((select body#>>'{crop_totals,2,harvest_count}' from responses where period='all'),'0','harvested without harvest row is not counted');
select is((select count(*)::int from public.crops where not is_active),2,'only own finalized inactive crops visible');
select ok(not exists(select 1 from public.crops where sort_order in(5,6,7)),'in-progress, foreign-only, unreferenced inactive crops hidden');
select is((select array_agg(k order by k) from jsonb_object_keys((select to_jsonb(c) from public.crops c where sort_order=1)) k),array['energy_level','id','is_active','name','sort_order','target_seconds'],'inactive direct SELECT retains exactly existing catalog columns');
select is((select body->'items' @> '[{"record_date":"2026-11-01","harvest_count":1}]'::jsonb from responses where period='all'),true,'harvest counted at session record_date rather than harvest date');
select is((select count(*)::int from public.list_crops('low')),2,'list_crops remains active only');
select throws_ok($$select public.start_focus((select id from public.farm_plots where plot_index=12),'10000000-0000-4000-8000-000000000001')$$,'PT404',null,'inactive crop cannot be planted despite historical access');
select ok((select bool_and(body->'summary'=old_body->'summary') from responses),'today/week/all same-snapshot summary parity');
select is((select jsonb_array_length(body->'items') from responses where period='today'),1,'today one day');
select is((select jsonb_array_length(body->'items') from responses where period='week'),7,'week exactly seven days');
select is((select extract(isodow from (body#>>'{items,0,record_date}')::date)::int from responses where period='week'),1,'week starts Monday');
select is((select extract(isodow from (body#>>'{items,6,record_date}')::date)::int from responses where period='week'),7,'week ends Sunday');
select ok((select bool_and(body->'monthly'='[]'::jsonb) from responses where period<>'all'),'monthly only for all');
select is((select count(distinct m->>'month')::int from responses,jsonb_array_elements(body->'monthly') m where period='all' and m->>'month' in('2025-11','2026-11')),2,'different years same month remain separate');
select ok((select array_agg(m->>'month' order by n)=array_agg(m->>'month' order by m->>'month' desc) from responses,jsonb_array_elements(body->'monthly') with ordinality a(m,n) where period='all'),'months descending');
select ok((select bool_and((select array_agg(i->>'record_date' order by n)=array_agg(i->>'record_date' order by i->>'record_date') from jsonb_array_elements(body->'items') with ordinality a(i,n))) from responses),'days ascending');
select is((select jsonb_array_length(body->'crop_totals') from responses where period='all'),4,'only recorded crops, no foreign or in-progress crop');
select ok((select bool_and((select array_agg(c->>'crop_id' order by n)=array_agg(c->>'crop_id' order by c->>'crop_id') from jsonb_array_elements(body->'crop_totals') with ordinality a(c,n))) from responses),'crop totals in catalog order');
select ok((select bool_and((select count(*)=5 from jsonb_object_keys(body))) from responses),'exact five top-level fields');
select ok((select bool_and(jsonb_typeof(body->'period')='string' and jsonb_typeof(body->'summary')='object' and jsonb_typeof(body->'items')='array' and jsonb_typeof(body->'monthly')='array' and jsonb_typeof(body->'crop_totals')='array') from responses),'top-level JSON types');
select ok((select bool_and(jsonb_typeof(body#>'{summary,focused_seconds}')='number' and jsonb_typeof(body#>'{summary,harvest_count}')='number' and jsonb_typeof(body#>'{summary,seed_count}')='number') from responses),'summary numeric types');
select ok((select bool_and(jsonb_typeof(c->'crop_id')='string' and jsonb_typeof(c->'crop_name')='string' and jsonb_typeof(c->'focused_seconds')='number' and jsonb_typeof(c->'harvest_count')='number') from responses,jsonb_array_elements(body->'crop_totals') c),'crop fields and numeric types');
select ok((select bool_and((body#>>'{summary,focused_seconds}')::bigint=(select coalesce(sum((i->>'focused_seconds')::bigint),0) from jsonb_array_elements(body->'items') i) and (body#>>'{summary,harvest_count}')::bigint=(select coalesce(sum((i->>'harvest_count')::bigint),0) from jsonb_array_elements(body->'items') i)) from responses),'daily sums match summary');
select ok((select bool_and((body#>>'{summary,focused_seconds}')::bigint=(select coalesce(sum((c->>'focused_seconds')::bigint),0) from jsonb_array_elements(body->'crop_totals') c) and (body#>>'{summary,harvest_count}')::bigint=(select coalesce(sum((c->>'harvest_count')::bigint),0) from jsonb_array_elements(body->'crop_totals') c)) from responses),'crop totals match summary');
select ok((select bool_and((i->>'focused_seconds')::bigint=(select coalesce(sum((c->>'focused_seconds')::bigint),0) from jsonb_array_elements(i->'crops') c) and (i->>'harvest_count')::bigint=(select coalesce(sum((c->>'harvest_count')::bigint),0) from jsonb_array_elements(i->'crops') c)) from responses,jsonb_array_elements(body->'items') i),'daily crops match daily sums');
select ok((select (body#>>'{summary,focused_seconds}')::bigint=(select sum((m->>'focused_seconds')::bigint) from jsonb_array_elements(body->'monthly') m) and (body#>>'{summary,harvest_count}')::bigint=(select sum((m->>'harvest_count')::bigint) from jsonb_array_elements(body->'monthly') m) from responses where period='all'),'monthly sums match summary');
select ok((select bool_and((m->>'focused_seconds')::bigint=(select sum((c->>'focused_seconds')::bigint) from jsonb_array_elements(m->'crops') c)) from responses,jsonb_array_elements(body->'monthly') m),'monthly crop seconds match monthly sums');
select ok((select bool_and((m->>'harvest_count')::bigint=(select sum((c->>'harvest_count')::bigint) from jsonb_array_elements(m->'crops') c)) from responses,jsonb_array_elements(body->'monthly') m),'monthly crop harvests match monthly sums');
select ok((select bool_and((select array_agg(c->>'crop_id' order by n)=array_agg(c->>'crop_id' order by c->>'crop_id') from jsonb_array_elements(i->'crops') with ordinality a(c,n))) from responses cross join lateral (select x as i from jsonb_array_elements(body->'items') x union all select x from jsonb_array_elements(body->'monthly') x) r),'daily and monthly crops retain catalog ordering');
select ok((select bool_and(i->'crops'='[]'::jsonb and i->'harvest_count'='0'::jsonb) from responses,jsonb_array_elements(body->'items') i where period='week' and i->'focused_seconds'='0'::jsonb and i->>'record_date'<>(now() at time zone 'Asia/Seoul')::date::text),'empty weekdays zero-filled');
select throws_ok($$select public.get_crop_history(null)$$,'22023','INVALID_INPUT','null rejected');
select throws_ok($$select public.get_crop_history('')$$,'22023','INVALID_INPUT','empty rejected');
select throws_ok($$select public.get_crop_history('month')$$,'22023','INVALID_INPUT','invalid period rejected');
select throws_ok($$select public.get_crop_history('Today')$$,'22023','INVALID_INPUT','case-sensitive period');
reset role;
select is((select md5(jsonb_agg(to_jsonb(s) order by id)::text) from public.focus_sessions s),(select sessions from before_read),'queries do not change sessions');
select is((select md5(jsonb_agg(to_jsonb(h) order by id)::text) from public.harvests h),(select harvests from before_read),'queries do not change harvests');
select throws_ok($$insert into public.harvests(session_id,harvested_at,auto_harvested) select session_id,now(),false from public.harvests limit 1$$,'23505',null,'one harvest per session enforced');

set local request.jwt.claim.sub='ac310000-0000-4000-8000-000000000002';
set local role authenticated;
select is(public.get_crop_history('all')#>>'{summary,focused_seconds}','700','other account sees only its own history');
select ok(not exists(select 1 from public.crops where sort_order in(1,2)),'other account cannot see owner inactive history crops');
reset role;
set local request.jwt.claim.sub='ac310000-0000-4000-8000-000000000003';
set local role authenticated;
select ok(not exists(select 1 from public.crops where sort_order=6),'paused-only reference does not grant inactive access');
select is(public.get_crop_history('all')->'items','[]'::jsonb,'paused-only history empty');
reset role;
set local request.jwt.claim.sub='ac310000-0000-4000-8000-000000000004';
set local role authenticated;
select throws_ok($$select public.get_crop_history('all')$$,'PT404','NOT_FOUND','missing profile');
reset role;
set local request.jwt.claim.sub='';
set local role authenticated;
select throws_ok($$select public.get_crop_history('all')$$,'PT401','UNAUTHENTICATED','missing JWT');
reset role;
set local role anon;
select throws_ok($$select public.get_crop_history('all')$$,'42501',null,'anonymous RPC blocked');
select throws_ok($$select * from public.crops$$,'42501',null,'anonymous table blocked');
reset role;
set local role service_role;
select throws_ok($$select public.get_crop_history('all')$$,'42501',null,'service role RPC blocked');
reset role;

update public.profiles set timezone='Pacific/Kiritimati' where id='ac310000-0000-4000-8000-000000000005';
set local request.jwt.claim.sub='ac310000-0000-4000-8000-000000000005';
set local role authenticated;
select is(public.get_crop_history('today')#>>'{items,0,record_date}',(statement_timestamp() at time zone 'Pacific/Kiritimati')::date::text,'positive timezone local date');
select is(public.get_crop_history('today')#>'{items,0}','{}'::jsonb || jsonb_build_object('record_date',(now() at time zone 'Pacific/Kiritimati')::date,'focused_seconds',0,'harvest_count',0,'crops','[]'::jsonb),'empty today shape');
select is(jsonb_array_length(public.get_crop_history('week')->'items'),7,'empty week seven dates');
select is(public.get_crop_history('all'),'{"period":"all","summary":{"focused_seconds":0,"harvest_count":0,"seed_count":0},"items":[],"monthly":[],"crop_totals":[]}'::jsonb,'empty all exact shape');
reset role;
update public.profiles set timezone='America/Los_Angeles' where id='ac310000-0000-4000-8000-000000000005';
set local role authenticated;
select is(public.get_crop_history('today')#>>'{items,0,record_date}',(statement_timestamp() at time zone 'America/Los_Angeles')::date::text,'negative timezone local date');
reset role;
insert into public.focus_sessions(user_id,plot_id,crop_id,status,started_at,target_seconds,focused_seconds,record_date)
select user_id,id,'10000000-0000-4000-8000-000000000003','seed_saved',now(),600,2147483647,date '2024-12-31'
from public.farm_plots where user_id='ac310000-0000-4000-8000-000000000005' and plot_index in(1,2);
set local role authenticated;
select is(public.get_crop_history('all')#>>'{summary,focused_seconds}','4294967294','bigint sum exceeds int32 safely');
select is(public.get_crop_history('all')->'summary',public.get_focus_history('all')->'summary','large sum parity');
select is(public.get_crop_history('all')#>>'{items,0,record_date}','2024-12-31','historical record_date not recomputed from timezone');
reset role;
update public.profiles set timezone='Pacific/Kiritimati' where id='ac310000-0000-4000-8000-000000000005';
set local role authenticated;
select is(public.get_crop_history('all')#>>'{items,0,record_date}','2024-12-31','timezone change preserves stored history date');
reset role;

set local request.jwt.claim.sub='ac310000-0000-4000-8000-000000000001';
set local role authenticated;
select public.reset_farm_history();
select ok(not exists(select 1 from public.crops where not is_active),'last reference removed revokes inactive visibility');
select is(public.get_crop_history('all')->'summary','{"focused_seconds":0,"harvest_count":0,"seed_count":0}'::jsonb,'reset clears all totals');
select is(public.get_crop_history('all')->'crop_totals','[]'::jsonb,'reset clears crop totals');
select is(public.get_crop_history('today')#>'{items,0,crops}','[]'::jsonb,'reset today empty');
select is(jsonb_array_length(public.get_crop_history('week')->'items'),7,'reset week retains seven days');
select is(public.get_crop_history('all')->'monthly','[]'::jsonb,'reset monthly empty');
select is(public.get_crop_history('all')->'summary',public.get_focus_history('all')->'summary','reset parity');
reset role;
select * from finish();
rollback;
