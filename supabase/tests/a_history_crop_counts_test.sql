begin;
select no_plan();
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

create temp table counts as
select p as period, public.get_focus_history(p) as focus, public.get_crop_history(p) as crop
from unnest(array['today','week','all']) p where false;
grant all on counts to authenticated;
set local request.jwt.claim.sub='ac310000-0000-4000-8000-000000000001';
set local role authenticated;
insert into counts select p,public.get_focus_history(p),public.get_crop_history(p) from unnest(array['today','week','all']) p;
select is(jsonb_array_length(focus->'items'),jsonb_array_length(crop->'items'),period||': same dates') from counts;
select is(focus->'summary',crop->'summary',period||': unchanged matching summaries') from counts;
select is((select jsonb_agg(d->'crops' order by n) from jsonb_array_elements(focus->'items') with ordinality x(d,n)),
 (select jsonb_agg((select coalesce(jsonb_agg(c-'harvest_count' order by k),'[]'::jsonb) from jsonb_array_elements(d->'crops') with ordinality y(c,k)) order by n) from jsonb_array_elements(crop->'items') with ordinality x(d,n)),
 period||': identical daily crop stats') from counts;
select is((select crop#>>'{crop_totals,1,grown_count}' from counts where period='today'),'4','ripe and three harvested sessions count as four grown');
select is((select crop#>>'{crop_totals,1,harvest_count}' from counts where period='today'),'3','ripe is grown but excluded from actual harvest count');
select is((select crop#>>'{crop_totals,0,seed_count}' from counts where period='today'),'1','zero-second seed count retained');
select is((select crop#>>'{crop_totals,0,grown_count}' from counts where period='today'),'0','seed is not grown');
select is((select crop#>>'{crop_totals,2,grown_count}' from counts where period='all'),'1','harvested without harvest row still grown');
select is((select sum((c->>'grown_count')::bigint)::text from counts,jsonb_array_elements(crop->'crop_totals') c where period='all'),'6','focusing excluded from grown count');
select is((select sum((c->>'seed_count')::bigint)::text from counts,jsonb_array_elements(crop->'crop_totals') c where period='all'),'3','all seed count matches finalized sessions');
select is((select jsonb_array_length(focus->'items') from counts where period='week'),7,'focus week seven dates');
select ok((select bool_and(d->'crops'='[]'::jsonb) from counts,jsonb_array_elements(focus->'items') d where period='week' and d->'focused_seconds'='0'::jsonb and d->>'record_date'<>(now() at time zone 'Asia/Seoul')::date::text),'empty days have crops array');
select ok((select bool_and((select count(*)=5 from jsonb_object_keys(c))) from counts,jsonb_array_elements(focus->'items') d,jsonb_array_elements(d->'crops') c),'focus crop exactly five approved fields');
select ok((select bool_and((select count(*)=6 from jsonb_object_keys(c))) from counts cross join lateral (select v as c from jsonb_array_elements(crop->'crop_totals') v union all select c from jsonb_array_elements(crop->'items') d,jsonb_array_elements(d->'crops') c union all select c from jsonb_array_elements(crop->'monthly') d,jsonb_array_elements(d->'crops') c) x),'crop objects exactly six approved fields');
select ok((select bool_and(jsonb_typeof(c->'grown_count')='number' and jsonb_typeof(c->'seed_count')='number') from counts,jsonb_array_elements(crop->'crop_totals') c),'new counts numeric, never null/string');
select ok((select bool_and((d->>'seed_count')::bigint=(select coalesce(sum((c->>'seed_count')::bigint),0) from jsonb_array_elements(d->'crops') c)) from counts,jsonb_array_elements(focus->'items') d),'legacy daily seed_count preserved');
select is((select sum((c->>'grown_count')::bigint)::text from counts,jsonb_array_elements(crop->'monthly') m,jsonb_array_elements(m->'crops') c where period='all'),'6','monthly grown totals');
select is((select sum((c->>'seed_count')::bigint)::text from counts,jsonb_array_elements(crop->'monthly') m,jsonb_array_elements(m->'crops') c where period='all'),'3','monthly seed totals');
select is((select focus#>>'{items,0,crops,0,crop_name}' from counts where period='today'),'새싹채소','inactive crop name retained in focus history');
select ok((select bool_and(focus->'capabilities'='{"harvest_count":true}'::jsonb) from counts),'legacy capabilities unchanged');
select ok((select bool_and(focus#>>'{range,timezone}'='Asia/Seoul') from counts),'legacy timezone unchanged');
reset role;
select ok((select bool_and(not prosecdef and provolatile='s' and proconfig @> array['search_path=""','TimeZone=UTC']) from pg_proc where oid in ('public.get_focus_history(text)'::regprocedure,'public.get_crop_history(text)'::regprocedure)),'both invoker/STABLE/empty search_path/UTC');
select ok((select bool_and(has_function_privilege('authenticated',p,'execute') and not has_function_privilege('anon',p,'execute') and not has_function_privilege('service_role',p,'execute')) from unnest(array['public.get_focus_history(text)','public.get_crop_history(text)']) p),'both existing ACL contracts retained');
select is((select count(*)::int from pg_policies where schemaname='public' and tablename='crops'),2,'no new RLS policies');
set local request.jwt.claim.sub='ac310000-0000-4000-8000-000000000002';
set local role authenticated;
select is(public.get_focus_history('all')#>>'{items,0,crops,0,seed_count}','1','other user own seed count only');
select is(public.get_focus_history('all')#>>'{summary,focused_seconds}','700','foreign seconds excluded');
reset role;
set local request.jwt.claim.sub='ac310000-0000-4000-8000-000000000003';
set local role authenticated;
select is(public.get_focus_history('all')->'items','[]'::jsonb,'paused excluded');
reset role;
set local request.jwt.claim.sub='ac310000-0000-4000-8000-000000000001';
set local role authenticated;
select public.reset_farm_history();
select is(public.get_focus_history('today')#>'{items,0,crops}','[]'::jsonb,'reset clears new focus daily crops');
select is(public.get_crop_history('today')#>'{items,0,crops}','[]'::jsonb,'reset clears new crop daily counts');
reset role;
select * from finish();
rollback;
