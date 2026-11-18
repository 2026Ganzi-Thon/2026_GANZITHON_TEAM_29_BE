create or replace function public.get_crop_history(p_period text)
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
      count(*) filter (where status = 'seed_saved') as seed_count,
      count(*) filter (where status in ('ripe', 'harvested')) as grown_count
    from filtered group by record_date, crop_id, crop_name, sort_order
  ), daily as (
    select record_date, sum(focused_seconds)::bigint as focused_seconds,
      sum(harvest_count)::bigint as harvest_count,
      jsonb_agg(jsonb_build_object('crop_id', crop_id, 'crop_name', crop_name,
        'focused_seconds', focused_seconds, 'harvest_count', harvest_count,
        'grown_count', grown_count, 'seed_count', seed_count)
        order by sort_order, crop_id) as crops
    from daily_crop group by record_date
  ), days as (
    select v_start + d as record_date from pg_catalog.generate_series(0, v_end - v_start) as d
    where p_period in ('today', 'week')
    union select record_date from daily_crop where p_period = 'all'
  ), monthly_crop as (
    select pg_catalog.to_char(record_date, 'YYYY-MM') as month,
      crop_id, crop_name, sort_order, sum(focused_seconds)::bigint as focused_seconds,
      sum(harvest_count)::bigint as harvest_count,
      sum(grown_count)::bigint as grown_count, sum(seed_count)::bigint as seed_count
    from daily_crop where p_period = 'all'
    group by pg_catalog.to_char(record_date, 'YYYY-MM'), crop_id, crop_name, sort_order
  ), monthly as (
    select month, sum(focused_seconds)::bigint as focused_seconds,
      sum(harvest_count)::bigint as harvest_count,
      jsonb_agg(jsonb_build_object('crop_id', crop_id, 'crop_name', crop_name,
        'focused_seconds', focused_seconds, 'harvest_count', harvest_count,
        'grown_count', grown_count, 'seed_count', seed_count)
        order by sort_order, crop_id) as crops
    from monthly_crop group by month
  ), totals as (
    select crop_id, crop_name, sort_order, sum(focused_seconds)::bigint as focused_seconds,
      sum(harvest_count)::bigint as harvest_count,
      sum(grown_count)::bigint as grown_count, sum(seed_count)::bigint as seed_count
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
      'harvest_count', harvest_count,
        'grown_count', grown_count, 'seed_count', seed_count) order by sort_order, crop_id), '[]'::jsonb) from totals)
  ) into v_result;
  return v_result;
end;
$$;

-- Reuse one aggregate while preserving the legacy focus-history response.
create or replace function public.get_focus_history(p_period text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_data jsonb;
  v_timezone text;
  v_items jsonb;
begin
  -- The shared RPC performs the unchanged auth, period and profile validation.
  v_data := public.get_crop_history(p_period);
  select p.timezone into v_timezone from public.profiles p where p.id = (select auth.uid());

  select coalesce(jsonb_agg(jsonb_build_object(
    'record_date', d.item->'record_date',
    'focused_seconds', d.item->'focused_seconds',
    'seed_count', coalesce(a.seed_count, 0),
    'harvest_count', d.item->'harvest_count',
    'crops', coalesce(a.crops, '[]'::jsonb)) order by d.ordinality), '[]'::jsonb)
  into v_items
  from jsonb_array_elements(v_data->'items') with ordinality as d(item, ordinality)
  cross join lateral (
    select sum((c.item->>'seed_count')::bigint)::bigint as seed_count,
      jsonb_agg(jsonb_build_object(
        'crop_id', c.item->'crop_id', 'crop_name', c.item->'crop_name',
        'focused_seconds', c.item->'focused_seconds',
        'grown_count', c.item->'grown_count', 'seed_count', c.item->'seed_count'
      ) order by c.ordinality) as crops
    from jsonb_array_elements(d.item->'crops') with ordinality as c(item, ordinality)
  ) as a;

  return jsonb_build_object(
    'period', v_data->'period',
    'range', jsonb_build_object(
      'start_date', v_data #> '{items,0,record_date}',
      'end_date', v_data #> '{items,-1,record_date}',
      'timezone', v_timezone),
    'summary', v_data->'summary',
    'items', v_items,
    'capabilities', jsonb_build_object('harvest_count', true)
  );
end;
$$;

-- CREATE OR REPLACE preserves the existing function ownership and EXECUTE ACLs.
comment on function public.get_focus_history(text) is
  'Finalized history with unchanged legacy totals/range and additive daily crop grown/seed counts.';
comment on function public.get_crop_history(text) is
  'Own finalized crop history with actual harvest counts and separate grown/seed session counts.';
