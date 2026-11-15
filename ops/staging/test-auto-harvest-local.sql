-- Local-only rollback fixture; never run against a hosted project.
begin;
do $$
begin
  if inet_server_addr() is not null then
    raise exception 'Use docker exec with local Unix socket';
  end if;
  if (select system_identifier::text from pg_control_system())='7703760980994770283' then
    raise exception 'Hosted Staging is forbidden for this fixture';
  end if;
  if exists(select 1 from auth.users) then
    raise exception 'Requires an empty disposable local test database';
  end if;
end $$;
insert into auth.users(id,email)
select ('c9000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  'cron-local-'||n||'@test.local' from generate_series(1,101) n;
insert into public.farm_plots(user_id,plot_index)
select id,1 from public.profiles where id::text like 'c9000000-%';
insert into public.focus_sessions(user_id,plot_id,crop_id,status,started_at,target_seconds,record_date)
select user_id,id,'10000000-0000-4000-8000-000000000001','focusing',
  clock_timestamp()-interval '3 days',600,current_date-3
from public.farm_plots where user_id::text like 'c9000000-%';
do $$
begin
  if public.process_due_harvests()->>'processed_count' <> '100' then
    raise exception 'First batch must process 100 owners';
  end if;
  if public.process_due_harvests()->>'processed_count' <> '1' then
    raise exception 'Second batch must drain remaining owner';
  end if;
  if public.process_due_harvests()->>'processed_count' <> '0' then
    raise exception 'Retry must be idempotent';
  end if;
  if (select count(*) from public.harvests h join public.focus_sessions s on s.id=h.session_id
      where s.user_id::text like 'c9000000-%' and h.auto_harvested) <> 101 then
    raise exception 'Expected 101 automatic harvest records';
  end if;
end $$;
select 'Local batch 100 + 1, retry 0, 101 unique harvests: PASS' as result;
rollback;
