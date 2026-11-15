begin;
select plan(29);

insert into auth.users (id, email) values ('a2200000-0000-4000-8000-000000000001', 'streak@test.local');
set local request.jwt.claim.sub = 'a2200000-0000-4000-8000-000000000001';
select public.ensure_farm();

create temp table streak_sessions as
with created as (
  insert into public.focus_sessions (user_id, plot_id, crop_id, status, started_at, target_seconds, focused_seconds, record_date)
  select user_id, id, '10000000-0000-4000-8000-000000000001',
    case when plot_index = 1 then 'focusing' else 'seed_saved' end,
    now() - case when plot_index = 1 then interval '3 hours' else interval '1 hour 30 minutes' end,
    3600, 3600, current_date
  from public.farm_plots where user_id = auth.uid() and plot_index in (1, 2)
  returning id, status
)
select * from created;

select public.finalize_my_focus();
select is(s.focus_ended_at, s.started_at + interval '1 hour', 'completion records logical target time')
from public.focus_sessions s join streak_sessions t using (id) where t.status = 'focusing';

update public.focus_sessions set focus_ended_at = now() - interval '30 minutes'
where id = (select id from streak_sessions where status = 'seed_saved');
select is(private.focus_streak_seconds(auth.uid(), now() - interval '1 second', 1800), 5400::numeric,
  '29:59 gap accumulates prior focus');
select is(private.focus_streak_seconds(auth.uid(), now(), 1800), 1800::numeric,
  '30:00 gap starts a new streak');
select is(private.focus_streak_seconds(auth.uid(), now() - interval '30 minutes', 1800), 5400::numeric,
  'a 30-minute gap earlier in the chain stops traversal');

create temp table active_streak as
with created as (
  insert into public.focus_sessions (user_id, plot_id, crop_id, status, started_at, target_seconds, record_date)
  select user_id, id, '10000000-0000-4000-8000-000000000001', 'focusing',
    now() - interval '30 minutes', 3600, current_date
  from public.farm_plots where user_id = auth.uid() and plot_index = 3
  returning id
) select id from created;

select is(private.overwork_notice_due(auth.uid(), id, now(), current_date), false, '90 minutes exactly is ineligible')
from active_streak;
select is(private.overwork_notice_due(auth.uid(), id, now() + interval '1 second', current_date), true, '90 minutes exceeded')
from active_streak;

select is(private.overwork_notice_due(auth.uid(), id, now() + interval '0.5 second', current_date), true,
  '5400.5 seconds qualifies') from active_streak;
update public.focus_sessions set target_seconds = 5400 where id = (select id from active_streak);
update public.focus_sessions set focused_seconds = 1 where id = (select id from streak_sessions where status = 'seed_saved');
select is(private.overwork_notice_due(auth.uid(), id, now() + interval '3599 seconds', current_date), false,
  'one previous second plus 5399 current seconds does not qualify') from active_streak;
select is(private.overwork_notice_due(auth.uid(), id, now() + interval '3599.5 seconds', current_date), true,
  'one previous second plus 5399.5 current seconds qualifies just before target') from active_streak;
select is(private.overwork_notice_due(auth.uid(), id, now() + interval '1 hour', current_date), false,
  'completed target is ineligible') from active_streak;
update public.focus_sessions set target_seconds = 3600 where id = (select id from active_streak);
update public.focus_sessions set focused_seconds = 3600 where id = (select id from streak_sessions where status = 'seed_saved');


select public.pause_focus(id) from active_streak;
select is(public.get_active_focus()->>'show_overwork_notice', 'false', 'paused session hides S12 candidate');
update public.focus_sessions set paused_at = paused_at - interval '10 seconds' where id = (select id from active_streak);
select public.resume_focus(id) from active_streak;
select ok(paused_duration >= interval '10 seconds' and
  private.focus_elapsed(started_at, paused_at, paused_duration, clock_timestamp()) < 1800,
  'resumed focus excludes paused interval')
from public.focus_sessions where id = (select id from active_streak);

-- Keep the active session under its target and make the accumulated streak eligible.
update public.focus_sessions set started_at = now() - interval '31 minutes' where id = (select id from active_streak);
-- Simulate a row written before the profile timezone validation trigger existed.
alter table public.profiles disable trigger profiles_validate_timezone;
update public.profiles set timezone = 'Invalid/Legacy' where id = auth.uid();
alter table public.profiles enable trigger profiles_validate_timezone;
select is(public.get_active_focus()->'session'->>'session_id', id::text, 'invalid legacy timezone preserves active session')
from active_streak;
select is(public.get_active_focus()->>'show_overwork_notice', 'false', 'invalid legacy timezone suppresses candidate');
select is(public.claim_overwork_notice(id), '{"show_overwork_notice":false}'::jsonb,
  'invalid legacy timezone cannot claim') from active_streak;
select is((select timezone from public.profiles where id = auth.uid()), 'Invalid/Legacy', 'RPCs preserve the profile value');
update public.profiles set timezone = 'Asia/Seoul' where id = auth.uid();
insert into private.overwork_notices
values (auth.uid(), (clock_timestamp() at time zone 'Asia/Seoul')::date - 1, clock_timestamp() - interval '1 day');
select is(public.get_active_focus()->>'show_overwork_notice', 'true', 'yesterday in profile timezone does not block today');
select is(public.claim_overwork_notice(id), '{"show_overwork_notice":true}'::jsonb, 'first claim grants display')
from active_streak;
select is(public.claim_overwork_notice(id), '{"show_overwork_notice":false}'::jsonb, 'repeat claim denied')
from active_streak;
select is(public.get_active_focus()->>'show_overwork_notice', 'false', 'claimed day is hidden in candidate read');
select ok(not has_function_privilege('anon', 'public.claim_overwork_notice(uuid)', 'execute')
  and not has_table_privilege('authenticated', 'private.overwork_notices', 'INSERT'), 'client writes restricted');

create temp table active_stop as select public.preview_stop_focus(id) as snapshot from active_streak;
select public.confirm_stop_focus(snapshot->>'stop_token') from active_stop;
select is(s.focus_ended_at, (p.snapshot->>'previewed_at')::timestamptz, 'stop ends at focus snapshot')
from public.focus_sessions s cross join active_stop p where s.id = (select id from active_streak);
select is(s.focused_seconds, (p.snapshot->>'focused_seconds')::int, 'stop retains existing snapshot focus amount')
from public.focus_sessions s cross join active_stop p where s.id = (select id from active_streak);

update public.focus_sessions set status = 'paused', paused_at = now() - interval '25 hours',
  started_at = now() - interval '25 hours 1 minute'
where id = (select id from active_streak);
select public.finalize_my_focus();
select is(focus_ended_at, now() - interval '25 hours', 'expired pause ends when focus stopped')
from public.focus_sessions where id = (select id from active_streak);

-- Make a recent completed session available for both the rest and streak check.
update public.focus_sessions set started_at = now() - interval '10 minutes',
  focus_ended_at = now() - interval '5 minutes', focused_seconds = 300
where id = (select id from streak_sessions where status = 'seed_saved');
select is(private.focus_streak_seconds(auth.uid(), now(), 10), 310::numeric, 'preceding session contributes before rest');
update public.focus_sessions set auto_harvest_at = now() + interval '1 hour'
where id = (select id from streak_sessions where status = 'focusing');
create temp table streak_harvest as
select (public.harvest_crop(id)->>'harvest_id')::uuid as id from streak_sessions where status = 'focusing';
create temp table streak_rest as select public.start_rest(id) as result from streak_harvest;
select is(private.focus_streak_seconds(auth.uid(), clock_timestamp(), 10), 10::numeric, 'first rest resets streak');
select is(public.start_rest(h.id)->>'rest_ends_at', r.result->>'rest_ends_at', 'retry keeps first rest boundary')
from streak_harvest h cross join streak_rest r;
select is(focused_seconds, 3600, 'rest keeps historical focused seconds')
from public.focus_sessions where id = (select id from streak_sessions where status = 'focusing');
select is((select count(*) from public.harvests), 1::bigint, 'rest keeps harvest history');

select * from finish();
rollback;
