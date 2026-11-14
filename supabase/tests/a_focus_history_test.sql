begin;
select plan(39);

select has_function('public', 'get_focus_history', array['text'], 'history RPC exists');
select ok(has_function_privilege('authenticated', 'public.get_focus_history(text)', 'EXECUTE'), 'authenticated can execute history RPC');
select isnt(has_function_privilege('anon', 'public.get_focus_history(text)', 'EXECUTE'), true, 'anon cannot execute history RPC');
select isnt(has_function_privilege('service_role', 'public.get_focus_history(text)', 'EXECUTE'), true, 'service role has no implicit history RPC access');
select is((select p.provolatile from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'get_focus_history'), 's', 'history RPC is stable');
select isnt((select p.prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'get_focus_history'), true, 'history RPC is security invoker');
select ok((select p.proconfig @> array['search_path=""'] from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'get_focus_history'), 'history RPC has empty search path');

insert into auth.users (id, email) values
  ('a5000000-0000-4000-8000-000000000001', 'history-all@test.local'),
  ('a5000000-0000-4000-8000-000000000002', 'history-other@test.local'),
  ('a5000000-0000-4000-8000-000000000003', 'history-week@test.local'),
  ('a5000000-0000-4000-8000-000000000004', 'history-today@test.local'),
  ('a5000000-0000-4000-8000-000000000005', 'history-empty@test.local'),
  ('a5000000-0000-4000-8000-000000000006', 'history-no-profile@test.local');

set local request.jwt.claim.sub = 'a5000000-0000-4000-8000-000000000001';
set local role authenticated;
select public.ensure_farm();
reset role;
set local request.jwt.claim.sub = 'a5000000-0000-4000-8000-000000000002';
set local role authenticated;
select public.ensure_farm();
reset role;
set local request.jwt.claim.sub = 'a5000000-0000-4000-8000-000000000003';
set local role authenticated;
select public.ensure_farm();
reset role;
set local request.jwt.claim.sub = 'a5000000-0000-4000-8000-000000000004';
set local role authenticated;
select public.ensure_farm();
reset role;

update public.profiles set timezone = 'UTC'
where id = 'a5000000-0000-4000-8000-000000000003';

insert into public.focus_sessions
  (user_id, plot_id, crop_id, status, started_at, target_seconds, focused_seconds, record_date)
select 'a5000000-0000-4000-8000-000000000001', id, '10000000-0000-4000-8000-000000000001', status,
  record_date::timestamptz, 600, focused_seconds, record_date
from public.farm_plots
join (values
  (1, 'seed_saved', 0, date '2025-12-28'),
  (2, 'seed_saved', 10, date '2025-12-29'),
  (3, 'ripe', 20, date '2025-12-31'),
  (4, 'harvested', 30, date '2026-01-01'),
  (5, 'seed_saved', 40, date '2026-01-04'),
  (6, 'ripe', 50, date '2026-01-05'),
  (7, 'focusing', 999, date '2026-01-06')
) as fixture(plot_index, status, focused_seconds, record_date) using (plot_index)
where user_id = 'a5000000-0000-4000-8000-000000000001';

insert into public.focus_sessions
  (user_id, plot_id, crop_id, status, started_at, target_seconds, focused_seconds, record_date)
select 'a5000000-0000-4000-8000-000000000002', id, '10000000-0000-4000-8000-000000000001', 'seed_saved', now(), 600, 700, date '2026-01-07'
from public.farm_plots where user_id = 'a5000000-0000-4000-8000-000000000002' and plot_index = 1;

insert into public.focus_sessions
  (user_id, plot_id, crop_id, status, started_at, target_seconds, focused_seconds, record_date)
select 'a5000000-0000-4000-8000-000000000003', id, '10000000-0000-4000-8000-000000000001', status, now(), 600, focused_seconds,
  (statement_timestamp() at time zone 'UTC')::date - (extract(isodow from (statement_timestamp() at time zone 'UTC')::date)::integer - 1) + day_offset
from public.farm_plots
join (values (1, 'seed_saved', 10, 0), (2, 'ripe', 20, 6)) as fixture(plot_index, status, focused_seconds, day_offset) using (plot_index)
where user_id = 'a5000000-0000-4000-8000-000000000003';

insert into public.focus_sessions
  (user_id, plot_id, crop_id, status, started_at, target_seconds, focused_seconds, record_date)
select 'a5000000-0000-4000-8000-000000000004', id, '10000000-0000-4000-8000-000000000001', status, now(), 600, focused_seconds,
  (statement_timestamp() at time zone 'Asia/Seoul')::date
from public.farm_plots
join (values (1, 'seed_saved', 0), (2, 'ripe', 25)) as fixture(plot_index, status, focused_seconds) using (plot_index)
where user_id = 'a5000000-0000-4000-8000-000000000004';

set local request.jwt.claim.sub = 'a5000000-0000-4000-8000-000000000001';
set local role authenticated;
create temp table all_history as select public.get_focus_history('all') as data;
select is((select data->>'period' from all_history), 'all', 'all response keeps requested period');
select is((select data->'range'->>'start_date' from all_history), '2025-12-28', 'all starts at first finalized record');
select is((select data->'range'->>'end_date' from all_history), '2026-01-05', 'all ends at last finalized record');
select is((select data->'range'->>'timezone' from all_history), 'Asia/Seoul', 'response includes profile timezone');
select is((select data->'summary'->>'focused_seconds' from all_history), '150', 'all sums finalized seconds including zero');
select is((select data->'summary'->>'seed_count' from all_history), '3', 'all counts seed-saved sessions');
select is((select data->'summary'->'harvest_count' from all_history), 'null'::jsonb, 'unsupported harvest count is null');
select is((select data->'capabilities'->>'harvest_count' from all_history), 'false', 'response advertises unavailable harvest count');
select is((select jsonb_array_length(data->'items') from all_history), 6, 'all includes only dates with finalized records');
select is((select data->'items'->0->>'focused_seconds' from all_history), '0', 'zero-second seed is retained');
select is((select data->'items'->0->>'record_date' from all_history), '2025-12-28', 'items are chronological');
select isnt((select data->'summary'->>'focused_seconds' from all_history), '1149', 'active and foreign sessions are excluded');
reset role;

set local request.jwt.claim.sub = 'a5000000-0000-4000-8000-000000000003';
set local role authenticated;
create temp table week_history as select public.get_focus_history('week') as data;
select is((select data->'range'->>'start_date' from week_history), ((statement_timestamp() at time zone 'UTC')::date - (extract(isodow from (statement_timestamp() at time zone 'UTC')::date)::integer - 1))::text, 'UTC week starts Monday');
select is((select data->'range'->>'end_date' from week_history), ((statement_timestamp() at time zone 'UTC')::date - (extract(isodow from (statement_timestamp() at time zone 'UTC')::date)::integer - 1) + 6)::text, 'UTC week ends Sunday');
select is((select data->'range'->>'timezone' from week_history), 'UTC', 'week uses profile timezone');
select is((select jsonb_array_length(data->'items') from week_history), 7, 'week includes seven daily buckets');
select is((select data->'summary'->>'focused_seconds' from week_history), '30', 'week sums its two finalized sessions');
select is((select data->'summary'->>'seed_count' from week_history), '1', 'week counts zero-safe seeds');
select is((select count(*) from week_history, jsonb_array_elements(data->'items') item where (item->>'focused_seconds')::integer = 0), 5::bigint, 'week fills empty days with zeros');
reset role;

set local request.jwt.claim.sub = 'a5000000-0000-4000-8000-000000000004';
set local role authenticated;
create temp table today_history as select public.get_focus_history('today') as data;
select is((select jsonb_array_length(data->'items') from today_history), 1, 'today returns one daily bucket');
select is((select data->'summary'->>'focused_seconds' from today_history), '25', 'today sums finalized seconds');
select is((select data->'summary'->>'seed_count' from today_history), '1', 'today counts zero-second seed');
reset role;

set local request.jwt.claim.sub = 'a5000000-0000-4000-8000-000000000005';
set local role authenticated;
create temp table empty_history as select public.get_focus_history('all') as data;
select is((select data->'range'->'start_date' from empty_history), 'null'::jsonb, 'empty all has null start');
select is((select data->'range'->'end_date' from empty_history), 'null'::jsonb, 'empty all has null end');
select is((select data->'items' from empty_history), '[]'::jsonb, 'empty all has no items');
select is((select data->'summary'->>'focused_seconds' from empty_history), '0', 'empty all has zero seconds');
select is((select data->'summary'->>'seed_count' from empty_history), '0', 'empty all has zero seeds');
select throws_ok($$select public.get_focus_history('month')$$, '22023', 'INVALID_INPUT', 'unknown period rejected');
select throws_ok($$select public.get_focus_history(null)$$, '22023', 'INVALID_INPUT', 'null period rejected');
reset role;

set local request.jwt.claim.sub = '';
set local role authenticated;
select throws_ok($$select public.get_focus_history('all')$$, 'PT401', 'UNAUTHENTICATED', 'missing auth context rejected');
reset role;
delete from public.profiles where id = 'a5000000-0000-4000-8000-000000000006';
set local request.jwt.claim.sub = 'a5000000-0000-4000-8000-000000000006';
set local role authenticated;
select throws_ok($$select public.get_focus_history('all')$$, 'PT404', 'NOT_FOUND', 'missing profile rejected');
reset role;
select is((select status from public.focus_sessions where user_id = 'a5000000-0000-4000-8000-000000000001' and focused_seconds = 999), 'focusing', 'history read does not mutate session state');

select * from finish();
rollback;
