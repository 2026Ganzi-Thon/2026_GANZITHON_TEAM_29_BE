create function public.get_focus_history(p_period text)
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
  v_start_date date;
  v_end_date date;
  v_focused_seconds bigint;
  v_seed_count bigint;
  v_items jsonb;
begin
  if v_user_id is null then
    raise exception using errcode = 'PT401', message = 'UNAUTHENTICATED';
  end if;

  if p_period is null or p_period not in ('today', 'week', 'all') then
    raise exception using errcode = '22023', message = 'INVALID_INPUT';
  end if;

  select p.timezone
  into v_timezone
  from public.profiles as p
  where p.id = v_user_id;

  if not found then
    raise exception using errcode = 'PT404', message = 'NOT_FOUND';
  end if;

  v_today := (statement_timestamp() at time zone v_timezone)::date;

  if p_period = 'today' then
    v_start_date := v_today;
    v_end_date := v_today;
  elsif p_period = 'week' then
    v_start_date := v_today - (extract(isodow from v_today)::integer - 1);
    v_end_date := v_start_date + 6;
  else
    select min(s.record_date), max(s.record_date)
    into v_start_date, v_end_date
    from public.focus_sessions as s
    where s.user_id = v_user_id
      and s.status in ('seed_saved', 'ripe', 'harvested');
  end if;

  select
    coalesce(sum(s.focused_seconds), 0)::bigint,
    count(*) filter (where s.status = 'seed_saved')::bigint
  into v_focused_seconds, v_seed_count
  from public.focus_sessions as s
  where s.user_id = v_user_id
    and s.status in ('seed_saved', 'ripe', 'harvested')
    and (p_period = 'all' or s.record_date between v_start_date and v_end_date);

  with filtered as (
    select s.record_date, s.focused_seconds, s.status
    from public.focus_sessions as s
    where s.user_id = v_user_id
      and s.status in ('seed_saved', 'ripe', 'harvested')
      and (p_period = 'all' or s.record_date between v_start_date and v_end_date)
  ),
  days as (
    select v_start_date + d as record_date
    from pg_catalog.generate_series(0, v_end_date - v_start_date) as d
    where p_period in ('today', 'week')
    union
    select distinct f.record_date
    from filtered as f
    where p_period = 'all'
  ),
  daily as (
    select
      f.record_date,
      sum(f.focused_seconds)::bigint as focused_seconds,
      count(*) filter (where f.status = 'seed_saved')::bigint as seed_count
    from filtered as f
    group by f.record_date
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'record_date', d.record_date,
        'focused_seconds', coalesce(a.focused_seconds, 0),
        'seed_count', coalesce(a.seed_count, 0),
        'harvest_count', null
      )
      order by d.record_date
    ),
    '[]'::jsonb
  )
  into v_items
  from days as d
  left join daily as a using (record_date);

  return jsonb_build_object(
    'period', p_period,
    'range', jsonb_build_object(
      'start_date', v_start_date,
      'end_date', v_end_date,
      'timezone', v_timezone
    ),
    'summary', jsonb_build_object(
      'focused_seconds', v_focused_seconds,
      'seed_count', v_seed_count,
      'harvest_count', null
    ),
    'items', v_items,
    'capabilities', jsonb_build_object('harvest_count', false)
  );
end;
$$;

revoke execute on function public.get_focus_history(text)
from public, anon, authenticated, service_role;
grant execute on function public.get_focus_history(text) to authenticated;

comment on function public.get_focus_history(text) is
  'Returns finalized focus-session history for the authenticated user; harvest counts remain unavailable until the harvest schema exists.';
