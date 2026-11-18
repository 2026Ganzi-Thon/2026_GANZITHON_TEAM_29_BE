-- Staging only: klanbfvywwudprunaqdf. Never place this file in supabase/migrations.
do $$
declare
  v_job record;
begin
  if current_user <> 'postgres' then
    raise exception 'Cron registration requires postgres';
  end if;
  -- Pin the cluster observed through the approved project API; fail closed elsewhere.
  if (select system_identifier::text from pg_control_system()) <> '7703760980994770283' then
    raise exception 'Not the approved focus-farm-staging cluster';
  end if;
  if (select array_agg(version order by version) from supabase_migrations.schema_migrations)
     is distinct from array['20261110152140','20261113012151','20261113020509','20261113143508',
       '20261113145323','20261114054245','20261114070324','20261114072516','20261115011444',
       '20261115013511','20261115015534','20261115020000','20261115020500','20261115021000',
       '20261118052002','20261118132003','20261118135436']::text[] then
    raise exception 'Unexpected migration history; review before enabling Cron';
  end if;
  if not has_function_privilege('postgres','public.process_due_harvests()','execute')
     or exists (select 1 from unnest(array['anon','authenticated','service_role']) r
       where has_function_privilege(r,'public.process_due_harvests()','execute')) then
    raise exception 'Unexpected harvest worker privileges';
  end if;

  -- Supabase's extension hook also runs for IF NOT EXISTS; avoid replaying it.
  if not exists (select 1 from pg_extension where extname='pg_cron') then
    create extension pg_cron with schema pg_catalog;
  end if;
  grant usage on schema cron to postgres;
  grant all privileges on all tables in schema cron to postgres;
  if exists (select 1 from unnest(array['anon','authenticated','service_role']) r
    where has_schema_privilege(r,'cron','usage')) then
    raise exception 'Unexpected client access to cron schema';
  end if;
  if exists (select 1 from cron.job where jobname='focus-farm-auto-harvest-staging'
    and username <> 'postgres') then
    raise exception 'Unexpected existing job owner';
  end if;
  if (select count(*) from cron.job where jobname='focus-farm-auto-harvest-staging') > 1 then
    raise exception 'Duplicate existing jobs';
  end if;
  select * into v_job from cron.job where jobname='focus-farm-auto-harvest-staging';
  if not found then
    perform cron.schedule('focus-farm-auto-harvest-staging','* * * * *',
      'SELECT public.process_due_harvests();');
  elsif v_job.schedule <> '* * * * *' or v_job.command <> 'SELECT public.process_due_harvests();'
     or not v_job.active or v_job.database <> current_database() then
    perform cron.alter_job(v_job.jobid, schedule := '* * * * *',
      command := 'SELECT public.process_due_harvests();', database := current_database(), active := true);
  end if;
end;
$$;
