-- Approved in Issue #31: inactive catalog rows become visible only through own finalized history.
create policy crops_select_own_history
on public.crops as permissive for select to authenticated
using (
  not is_active and exists (
    select 1 from public.focus_sessions as s
    where s.crop_id = crops.id
      and s.user_id = (select auth.uid())
      and s.status in ('seed_saved', 'ripe', 'harvested')
  )
);

create function public.get_crop_history(p_period text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_timezone text;
  v_today date;
  v_start date;
  v_end date;
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception using errcode = 'PT401', message = 'UNAUTHENTICATED';
  end if;
  if p_period is null or p_period not in ('today', 'week', 'all') then
    raise exception using errcode = '22023', message = 'INVALID_INPUT';
  end if;
  select p.timezone into v_timezone from public.profiles as p where p.id = v_user_id;
  if not found then
    raise exception using errcode = 'PT404', message = 'NOT_FOUND';
  end if;
  v_today := (statement_timestamp() at time zone v_timezone)::date;
  v_start := case when p_period = 'week'
    then v_today - (extract(isodow from v_today)::integer - 1) else v_today end;
  v_end := case when p_period = 'week' then v_start + 6 else v_today end;

  with filtered as materialized (
    select s.record_date, s.crop_id, c.name as crop_name, c.sort_order,
      s.focused_seconds, s.status, h.session_id is not null as harvested
    from public.focus_sessions as s
    join public.crops as c on c.id = s.crop_id
    left join public.harvests as h on h.session_id = s.id
    where s.user_id = v_user_id
      and s.status in ('seed_saved', 'ripe', 'harvested')
      and (p_period = 'all' or s.record_date between v_start and v_end)
  ), daily_crop as materialized (
    select record_date, crop_id, crop_name, sort_order,
      sum(focused_seconds)::bigint as focused_seconds,
      count(*) filter (where harvested) as harvest_count,
      count(*) filter (where status = 'seed_saved') as seed_count
    from filtered group by record_date, crop_id, crop_name, sort_order
  ), daily as (
    select record_date, sum(focused_seconds)::bigint as focused_seconds,
      sum(harvest_count)::bigint as harvest_count,
      jsonb_agg(jsonb_build_object('crop_id', crop_id, 'crop_name', crop_name,
        'focused_seconds', focused_seconds, 'harvest_count', harvest_count)
        order by sort_order, crop_id) as crops
    from daily_crop group by record_date
  ), days as (
    select v_start + d as record_date from pg_catalog.generate_series(0, v_end - v_start) as d
    where p_period in ('today', 'week')
    union select record_date from daily_crop where p_period = 'all'
  ), monthly_crop as (
    select pg_catalog.to_char(record_date, 'YYYY-MM') as month,
      crop_id, crop_name, sort_order, sum(focused_seconds)::bigint as focused_seconds,
      sum(harvest_count)::bigint as harvest_count
    from daily_crop where p_period = 'all'
    group by pg_catalog.to_char(record_date, 'YYYY-MM'), crop_id, crop_name, sort_order
  ), monthly as (
    select month, sum(focused_seconds)::bigint as focused_seconds,
      sum(harvest_count)::bigint as harvest_count,
      jsonb_agg(jsonb_build_object('crop_id', crop_id, 'crop_name', crop_name,
        'focused_seconds', focused_seconds, 'harvest_count', harvest_count)
        order by sort_order, crop_id) as crops
    from monthly_crop group by month
  ), totals as (
    select crop_id, crop_name, sort_order, sum(focused_seconds)::bigint as focused_seconds,
      sum(harvest_count)::bigint as harvest_count
    from daily_crop group by crop_id, crop_name, sort_order
  )
  select jsonb_build_object(
    'period', p_period,
    'summary', (select jsonb_build_object(
      'focused_seconds', coalesce(sum(focused_seconds), 0)::bigint,
      'harvest_count', coalesce(sum(harvest_count), 0)::bigint,
      'seed_count', coalesce(sum(seed_count), 0)::bigint) from daily_crop),
    'items', (select coalesce(jsonb_agg(jsonb_build_object(
      'record_date', d.record_date, 'focused_seconds', coalesce(a.focused_seconds, 0),
      'harvest_count', coalesce(a.harvest_count, 0), 'crops', coalesce(a.crops, '[]'::jsonb))
      order by d.record_date), '[]'::jsonb)
      from days as d left join daily as a using (record_date)),
    'monthly', (select coalesce(jsonb_agg(jsonb_build_object(
      'month', month, 'focused_seconds', focused_seconds, 'harvest_count', harvest_count,
      'crops', crops) order by month desc), '[]'::jsonb) from monthly),
    'crop_totals', (select coalesce(jsonb_agg(jsonb_build_object(
      'crop_id', crop_id, 'crop_name', crop_name, 'focused_seconds', focused_seconds,
      'harvest_count', harvest_count) order by sort_order, crop_id), '[]'::jsonb) from totals)
  ) into v_result;
  return v_result;
end;
$$;

revoke execute on function public.get_crop_history(text) from public, anon, authenticated, service_role;
grant execute on function public.get_crop_history(text) to authenticated;
comment on function public.get_crop_history(text) is
  'Read-only own finalized crop history by session record_date, including actual harvests and inactive historical crops.';
