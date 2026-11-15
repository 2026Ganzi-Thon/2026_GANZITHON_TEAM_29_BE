\set ON_ERROR_STOP on
begin;

insert into auth.users(id,email) values
 ('a7000000-0000-4000-8000-000000000001','upgrade-valid@test.local'),
 ('a7000000-0000-4000-8000-000000000002','upgrade-invalid@test.local');
update public.profiles set timezone = case
 when id = 'a7000000-0000-4000-8000-000000000001' then 'America/New_York'
 else 'Invalid/Zone' end
where id in ('a7000000-0000-4000-8000-000000000001','a7000000-0000-4000-8000-000000000002');

insert into public.farm_plots(user_id,plot_index)
select id,1 from public.profiles where id::text like 'a7000000%';

insert into public.focus_sessions(user_id,plot_id,crop_id,status,started_at,paused_duration,target_seconds,focused_seconds,record_date)
select p.user_id,p.id,'10000000-0000-4000-8000-000000000001','ripe',
 '2026-03-08 04:45:00+00',interval '5 minutes',600,600,'2026-03-07'
from public.farm_plots p where p.user_id::text like 'a7000000%';

\ir ../migrations/20261114072516_b_harvest.sql

do $$
declare
  v_user uuid := 'a7000000-0000-4000-8000-000000000001';
  v_invalid uuid := 'a7000000-0000-4000-8000-000000000002';
  v_session public.focus_sessions%rowtype;
begin
  select * into strict v_session from public.focus_sessions where user_id = v_user;
  assert v_session.ripe_at is not distinct from timestamptz '2026-03-08 05:00:00+00';
  assert v_session.auto_harvest_at is not distinct from timestamptz '2026-03-09 04:00:00+00', 'next local midnight after DST jump';
  assert v_session.focused_seconds = 600 and v_session.record_date = date '2026-03-07';
  assert (select auto_harvest_at is null from public.focus_sessions where user_id = v_invalid);
  assert (select count(*) = 0 from public.harvests), 'migration must not harvest';
  assert public.process_due_harvests() = '{"processed_count":1}'::jsonb;
  assert public.process_due_harvests() = '{"processed_count":0}'::jsonb;
  assert (select status = 'harvested' and focused_seconds = 600 and record_date = date '2026-03-07'
          from public.focus_sessions where id = v_session.id);
  assert (select count(*) = 1 and bool_and(auto_harvested)
          from public.harvests where session_id = v_session.id);

  begin
    update public.profiles set timezone = 'Still/Invalid' where id = v_invalid;
    raise exception 'invalid zone accepted';
  exception when invalid_parameter_value then
    null;
  end;
  update public.profiles set timezone = 'Asia/Seoul' where id = v_invalid;
  assert public.process_due_harvests() = '{"processed_count":1}'::jsonb, 'corrected zone restores deadline';
  assert public.process_due_harvests() = '{"processed_count":0}'::jsonb;
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  assert public.start_focus(v_session.plot_id, v_session.crop_id)->>'status' = 'focusing';
end;
$$;

rollback;
