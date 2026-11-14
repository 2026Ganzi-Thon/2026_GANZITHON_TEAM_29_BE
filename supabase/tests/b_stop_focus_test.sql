begin;
select plan(25);
insert into auth.users (id,email) values ('a5000000-0000-4000-8000-000000000001','stop-sql@test.local');
set local request.jwt.claim.sub = 'a5000000-0000-4000-8000-000000000001';
set local role authenticated;
create temp table stop_plots as select * from public.ensure_farm();
create temp table stop_session as
select (public.start_focus(plot_id, '10000000-0000-4000-8000-000000000001')->>'session_id')::uuid as id
from stop_plots where plot_index = 1;
create temp table stop_preview as select public.preview_stop_focus(id) as data from stop_session;
select is((select data->>'focused_seconds' from stop_preview), '0', 'zero seconds accepted');
select is((select data->>'focus_minutes' from stop_preview), '0', 'under one minute rounds down');
select is((select (data->>'expires_at')::timestamptz - (data->>'previewed_at')::timestamptz from stop_preview),
  interval '5 minutes', 'five minute TTL');
select is((select public.cancel_stop_focus(data->>'stop_token')->>'cancelled' from stop_preview), 'true', 'cancel succeeds');
select is((select status from public.focus_sessions), 'focusing', 'cancel preserves running timer');

reset role;
update public.focus_sessions set started_at = clock_timestamp() - interval '629 seconds', paused_duration = interval '30 seconds';
set local role authenticated;
update stop_preview set data = public.preview_stop_focus((select id from stop_session));
select is((select data->>'focused_seconds' from stop_preview), '599', 'one second before target excluding rest');
reset role;
update public.focus_sessions set started_at = started_at - interval '10 seconds';
set local role authenticated;
select is(public.finalize_my_focus(), null::jsonb, 'live preview holds completed focus');
select is((select public.confirm_stop_focus(data->>'stop_token')->>'focused_seconds' from stop_preview),
  '599', 'confirmation preserves snapshot');
select is((select public.confirm_stop_focus(data->>'stop_token')->>'status' from stop_preview),
  'seed_saved', 'retry returns success');

truncate stop_session;
insert into stop_session
select (public.start_focus(plot_id, '10000000-0000-4000-8000-000000000001')->>'session_id')::uuid
from stop_plots where plot_index = 1;
reset role;
update public.focus_sessions set status = 'paused',
  started_at = statement_timestamp() - interval '24 hours 20 seconds',
  paused_at = statement_timestamp() - interval '23 hours 59 minutes 50 seconds'
where status = 'focusing';
set local role authenticated;
update stop_preview set data = public.preview_stop_focus((select id from stop_session));
select is((select data->>'focused_seconds' from stop_preview), '30', 'paused snapshot freezes at pause time');
reset role;
update public.focus_sessions
set paused_at = paused_at - interval '15 seconds', started_at = started_at - interval '15 seconds'
where status = 'paused';
set local role authenticated;
select is(public.finalize_my_focus(), null::jsonb, 'live preview holds expired pause');
reset role;
update private.focus_stop_previews set expires_at = clock_timestamp()
where consumed_at is null and cancelled_at is null;
set local role authenticated;
select throws_ok(
  $$select public.confirm_stop_focus(data->>'stop_token') from stop_preview$$,
  'PT409', '중도 종료 토큰이 만료됐습니다.', 'expired token rejected'
);
select is(public.finalize_my_focus()->>'status', 'seed_saved', 'TTL releases automatic finalization');
select is((select focused_seconds from public.focus_sessions where id = (select id from stop_session)),
  30, 'expiry finalizes focused time');
create temp table renewed_session as
select public.start_focus(plot_id, '10000000-0000-4000-8000-000000000001')
from stop_plots where plot_index = 1;
update stop_preview set data = public.preview_stop_focus((select id from public.focus_sessions where status = 'focusing'));
reset role;
update private.focus_stop_previews set expires_at = clock_timestamp()
where consumed_at is null and cancelled_at is null;
set local role authenticated;
create temp table renewed_preview as
select public.preview_stop_focus(id) as data from public.focus_sessions where status = 'focusing';
select ok((select renewed.data->>'stop_token' <> old.data->>'stop_token'
  from renewed_preview renewed cross join stop_preview old), 'expired preview can be replaced');
select is((select public.cancel_stop_focus(data->>'stop_token')->>'cancelled' from renewed_preview),
  'true', 'replacement cancelled');
select is((select public.cancel_stop_focus(data->>'stop_token')->>'cancelled' from renewed_preview),
  'true', 'repeated cancel reports cancelled state');
reset role;
update public.focus_sessions set started_at = clock_timestamp() - interval '1 hour' where status = 'focusing';
set local role authenticated;
select is(public.finalize_my_focus()->>'status', 'ripe', 'cancelled preview permits ripe finalization');

reset role;
select ok(has_function_privilege('authenticated', 'public.preview_stop_focus(uuid)', 'execute'), 'authenticated can preview');
select ok(not has_function_privilege('authenticated', 'private.resolve_focus_stop(text,boolean)', 'execute'), 'private resolver cannot be called directly');
select ok(not has_function_privilege('authenticated', 'private.invalidate_focus_stop_preview()', 'execute'), 'trigger helper cannot be called directly');
select ok(not has_table_privilege('authenticated', 'private.focus_stop_previews', 'select'), 'preview rows private');
select ok(not has_schema_privilege('authenticated', 'private', 'usage'), 'private schema inaccessible');
select ok(not exists (
  select 1 from unnest(array['anon','service_role']) as roles(role_name)
  cross join unnest(array['public.preview_stop_focus(uuid)','public.confirm_stop_focus(text)',
    'public.cancel_stop_focus(text)']) as r(signature)
  where has_function_privilege(roles.role_name, r.signature, 'execute')
), 'non-client roles cannot execute stop RPCs');
select is((select count(*) from private.focus_stop_previews where consumed_at is not null),
  1::bigint, 'confirmation retry leaves exactly one consumed snapshot');
select * from finish();
rollback;
