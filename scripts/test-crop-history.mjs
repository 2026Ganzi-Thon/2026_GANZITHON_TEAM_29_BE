import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { randomInt, randomUUID } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

// Hosted fixtures are opt-in and pinned to the approved Staging project.
const staging = process.argv.includes('--staging')
assert.ok(process.argv.slice(2).every(a => a === '--staging'), 'Unknown test option')
const ref = 'klanbfvywwudprunaqdf'
const status = staging ? null : JSON.parse(execFileSync('npx', ['supabase', 'status', '-o', 'json'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }))
const url = staging ? `https://${ref}.supabase.co` : status.API_URL
const key = staging ? process.env.SUPABASE_PUBLISHABLE_KEY : status.PUBLISHABLE_KEY
assert.ok(url && key, 'Publishable key is required; never supply a secret key')
assert.ok(key.startsWith('sb_publishable_'), 'Only publishable keys allowed')
const projectId = readFileSync(new URL('../supabase/config.toml', import.meta.url), 'utf8').match(/^project_id\s*=\s*"([^"]+)"/m)?.[1]

function sql(query, write = false) {
  try {
    if (staging) {
      const result = JSON.parse(execFileSync('npx', ['supabase', 'db', 'query', `--remote=${ref}`, write ? '--yes' : '--read-only', query], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }))
      return result.rows
    }
    return JSON.parse(execFileSync('docker', ['exec', `supabase_db_${projectId}`, 'psql', '-XqAt', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres', '-c', query], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }))
  } catch {
    throw new Error('Fixture SQL failed; output withheld to protect credentials')
  }
}
const client = () => createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } })
const run = randomUUID()
const password = `Crop-${randomUUID()}-Aa1!`
const accounts = []
const responses = {}
const focusResponses = {}
const fixtureCrops = Array.from({ length: 5 }, () => randomUUID())
const sortBase = 1500000000 + randomInt(1000000) * 5
async function rpc(c, name, args) {
  const r = await c.rpc(name, args)
  assert.equal(r.error, null, `${name}: ${r.error?.code} ${r.error?.message}`)
  return r.data
}
async function signup(label) {
  const c = client()
  const email = `crop-${label}-${run}@example.com`
  const r = await c.auth.signUp({ email, password, options: { data: { nickname: 'crop-e2e', crop_history_test_run: run } } })
  assert.equal(r.error, null, `signup: ${r.error?.code}`)
  assert.ok(r.data.user?.id, 'Signup user missing')
  const account = { c, id: r.data.user.id, email }
  accounts.push(account)
  assert.match(account.id, /^[0-9a-f-]{36}$/)
  assert.ok(r.data.session, 'Confirm email must be OFF in this environment')
  const login = await c.auth.signInWithPassword({ email, password })
  assert.equal(login.error, null, `login: ${login.error?.code}`)
  assert.equal((await c.auth.getSession()).data.session?.user.id, account.id)
  return account
}
function check(data, period) {
  assert.deepEqual(Object.keys(data).sort(), ['crop_totals', 'items', 'monthly', 'period', 'summary'])
  assert.equal(data.period, period)
  for (const n of Object.values(data.summary)) assert.ok(Number.isSafeInteger(n) && n >= 0)
  for (const key of ['items', 'monthly', 'crop_totals']) assert.ok(Array.isArray(data[key]))
  for (const field of ['focused_seconds', 'harvest_count']) {
    const sum = rows => rows.reduce((a, r) => a + r[field], 0)
    assert.equal(sum(data.items), data.summary[field])
    assert.equal(sum(data.crop_totals), data.summary[field])
    for (const row of [...data.items, ...data.monthly]) assert.equal(sum(row.crops), row[field])
    if (period === 'all') assert.equal(sum(data.monthly), data.summary[field])
  }
  if (period === 'today') assert.equal(data.items.length, 1)
  if (period === 'week') assert.equal(data.items.length, 7)
  if (period !== 'all') assert.deepEqual(data.monthly, [])
  assert.deepEqual(data.items.map(r => r.record_date), data.items.map(r => r.record_date).sort())
  assert.deepEqual(data.monthly.map(r => r.month), data.monthly.map(r => r.month).sort().reverse())
  for (const row of [...data.items, ...data.monthly, data]) {
    const crops = row.crops ?? row.crop_totals
    for (const crop of crops) {
      assert.match(crop.crop_id, /^[0-9a-f-]{36}$/)
      assert.equal(typeof crop.crop_name, 'string')
      assert.ok(Number.isSafeInteger(crop.focused_seconds) && Number.isSafeInteger(crop.harvest_count))
      assert.ok(Number.isSafeInteger(crop.grown_count) && Number.isSafeInteger(crop.seed_count))
    }
  }
}
let result
try {
  const a = await signup('a')
  const b = await signup('b')
  for (const period of ['today', 'week', 'all']) {
    const empty = await rpc(b.c, 'get_crop_history', { p_period: period })
    check(empty, period)
    assert.deepEqual(empty.summary, { focused_seconds: 0, harvest_count: 0, seed_count: 0 })
    assert.deepEqual(empty.crop_totals, [])
  }
  const farm = await rpc(a.c, 'ensure_farm')
  await rpc(a.c, 'complete_onboarding')
  for (const p of farm) assert.match(p.plot_id, /^[0-9a-f-]{36}$/)
  // Only newly created account-owned rows are written. Shared crops and Cron are untouched.
  sql(`with fixture as (
    insert into public.focus_sessions(user_id,plot_id,crop_id,status,started_at,target_seconds,focused_seconds,record_date)
    select '${a.id}', p.id, ('10000000-0000-4000-8000-'||lpad(v.crop::text,12,'0'))::uuid,
      v.status, now(), 600, v.seconds,
      case when v.day_offset is not null then (now() at time zone 'Asia/Seoul')::date + v.day_offset else v.old_date::date end
    from public.farm_plots p join (values
      (1,1,'seed_saved',0,0,null),(2,2,'seed_saved',10,0,null),
      (3,2,'ripe',20,0,null),(4,2,'harvested',30,0,null),
      (5,2,'harvested',40,0,null),(6,2,'harvested',50,0,null),
      (7,3,'harvested',60,-1,null),(8,4,'seed_saved',70,null,'2025-11-01'),
      (9,4,'harvested',80,null,'2026-11-01'),(10,5,'focusing',999,0,null)
    ) v(plot_index,crop,status,seconds,day_offset,old_date) using(plot_index)
    where p.user_id='${a.id}' returning id,focused_seconds
  ), inserted as (
    insert into public.harvests(session_id,harvested_at,auto_harvested)
    select id,now(),focused_seconds=40 from fixture where focused_seconds in(30,40,50,80) returning id
  ) select json_build_object('sessions',(select count(*) from fixture),'harvests',(select count(*) from inserted)) as result`, true)
  const snapshotQuery = `select json_build_object('sessions',(select jsonb_agg(to_jsonb(s) order by id) from public.focus_sessions s where user_id='${a.id}'),'harvests',(select jsonb_agg(to_jsonb(h) order by h.id) from public.harvests h join public.focus_sessions s on s.id=h.session_id where s.user_id='${a.id}')) as snapshot`
  const before = sql(snapshotQuery)
  for (const period of ['today', 'week', 'all']) {
    const data = await rpc(a.c, 'get_crop_history', { p_period: period })
    const old = await rpc(a.c, 'get_focus_history', { p_period: period })
    check(data, period)
    assert.deepEqual(data.summary, old.summary)
    assert.deepEqual(old.items.map(day => day.crops), data.items.map(day => day.crops.map(({ harvest_count, ...crop }) => crop)))
    assert.deepEqual(old.items.map(({ crops, ...day }) => day), data.items.map(({ crops, ...day }) => ({ ...day, seed_count: crops.reduce((n, c) => n + c.seed_count, 0) })))
    focusResponses[period] = old
    responses[period] = data
    const isolated = await rpc(b.c, 'get_crop_history', { p_period: period })
    assert.equal(isolated.summary.focused_seconds, 0)
  }
  assert.deepEqual(sql(snapshotQuery), before, 'Read-only RPC changes no owned rows')
  assert.deepEqual(responses.all.summary, { focused_seconds: 360, harvest_count: 4, seed_count: 3 })
  assert.equal(responses.today.crop_totals[1].harvest_count, 3)
  assert.equal(responses.today.crop_totals[1].grown_count, 4)
  assert.equal(responses.today.crop_totals[1].seed_count, 1)
  assert.equal(responses.today.crop_totals[0].focused_seconds, 0)
  // Execute the untouched previous SQL definitions in a local temporary schema, then roll back.
  if (!staging) {
    const originals = [
      ['20261115011444_a_focus_history_harvest_count.sql', 'get_focus_history'],
      ['20261118132003_a_crop_history.sql', 'get_crop_history'],
    ].map(([file, name]) => {
      const source = readFileSync(new URL(`../supabase/migrations/${file}`, import.meta.url), 'utf8')
      const definition = source.slice(source.indexOf(`create ${name === 'get_focus_history' ? 'or replace ' : ''}function public.${name}`)).split('$$;')[0] + '$$;'
      return definition.replace(`public.${name}`, `pg_temp.previous_${name}`) + `\ngrant execute on function pg_temp.previous_${name}(text) to authenticated;`
    }).join('\n')
    const previous = sql(`begin; ${originals}
      set local request.jwt.claim.sub='${a.id}'; set local role authenticated;
      select json_object_agg(p,json_build_object('focus',pg_temp.previous_get_focus_history(p),'crop',pg_temp.previous_get_crop_history(p)))
      from unnest(array['today','week','all']) p; rollback;`)
    const stripCounts = crop => { const { grown_count, seed_count, ...old } = crop; return old }
    for (const period of ['today', 'week', 'all']) {
      assert.deepEqual({ ...focusResponses[period], items: focusResponses[period].items.map(({ crops, ...day }) => day) }, previous[period].focus)
      assert.deepEqual({ ...responses[period],
        items: responses[period].items.map(day => ({ ...day, crops: day.crops.map(stripCounts) })),
        monthly: responses[period].monthly.map(month => ({ ...month, crops: month.crops.map(stripCounts) })),
        crop_totals: responses[period].crop_totals.map(stripCounts),
      }, previous[period].crop)
    }
  }
  const foreign = await b.c.from('focus_sessions').select('id').eq('user_id', a.id)
  assert.equal(foreign.error, null)
  assert.deepEqual(foreign.data, [])
  for (const invalid of [null, '', 'month', 'Today']) {
    const r = await a.c.rpc('get_crop_history', { p_period: invalid })
    assert.equal(r.error?.code, '22023')
    assert.equal(r.error?.message, 'INVALID_INPUT')
    assert.equal(r.status, 400)
  }
  const anonymous = await client().rpc('get_crop_history', { p_period: 'all' })
  assert.equal(anonymous.error?.code, '42501')
  assert.equal(anonymous.status, 401)
  await rpc(a.c, 'reset_farm_history')
  for (const period of ['today', 'week', 'all']) {
    const reset = await rpc(a.c, 'get_crop_history', { p_period: period })
    check(reset, period)
    assert.equal(reset.summary.focused_seconds, 0)
    assert.deepEqual(reset.crop_totals, [])
  }
  const otherFarm = await rpc(b.c, 'ensure_farm')
  const values = fixtureCrops.map((id, i) => `('${id}','crop-e2e-${run}-${i}',600,'low',${sortBase + i},false)`).join(',')
  sql(`with catalog as (
    insert into public.crops(id,name,target_seconds,energy_level,sort_order,is_active)
    values ${values} returning id
  ), fixture as (
    insert into public.focus_sessions(user_id,plot_id,crop_id,status,started_at,paused_at,target_seconds,focused_seconds,record_date)
    values
    ('${a.id}','${farm[0].plot_id}','${fixtureCrops[0]}','seed_saved',now(),null,600,0,current_date),
    ('${a.id}','${farm[1].plot_id}','${fixtureCrops[0]}','ripe',now(),null,600,20,current_date),
    ('${a.id}','${farm[2].plot_id}','${fixtureCrops[0]}','harvested',now(),null,600,30,current_date),
    ('${a.id}','${farm[3].plot_id}','${fixtureCrops[3]}','focusing',now(),null,600,999,current_date),
    ('${b.id}','${otherFarm[0].plot_id}','${fixtureCrops[1]}','seed_saved',now(),null,600,7,current_date),
    ('${b.id}','${otherFarm[1].plot_id}','${fixtureCrops[4]}','paused',now(),now(),600,999,current_date)
    returning id,user_id,status
  ), harvested as (
    insert into public.harvests(session_id,harvested_at,auto_harvested)
    select id,now(),false from fixture where status='harvested' returning id
  ) select json_build_object('catalog',(select count(*) from catalog),'sessions',(select count(*) from fixture),'harvests',(select count(*) from harvested)) as result`, true)
  for (const [account, expectedId] of [[a, fixtureCrops[0]], [b, fixtureCrops[1]]]) {
    const visible = await account.c.from('crops').select('*').in('id', fixtureCrops)
    assert.equal(visible.error, null)
    assert.deepEqual(visible.data.map(crop => crop.id), [expectedId])
    assert.deepEqual(Object.keys(visible.data[0]).sort(), ['energy_level', 'id', 'is_active', 'name', 'sort_order', 'target_seconds'])
    const recommended = await rpc(account.c, 'list_crops', { p_energy: 'low' })
    assert.ok(recommended.every(crop => !fixtureCrops.includes(crop.crop_id)))
  }
  const inactive = await rpc(a.c, 'get_crop_history', { p_period: 'all' })
  check(inactive, 'all')
  assert.deepEqual(inactive.summary, { focused_seconds: 50, harvest_count: 1, seed_count: 1 })
  assert.deepEqual(inactive.summary, (await rpc(a.c, 'get_focus_history', { p_period: 'all' })).summary)
  assert.equal(inactive.crop_totals[0].crop_id, fixtureCrops[0])
  assert.equal(inactive.crop_totals[0].crop_name, `crop-e2e-${run}-0`)
  const planting = await a.c.rpc('start_focus', { p_plot_id: farm[11].plot_id, p_crop_id: fixtureCrops[0] })
  assert.equal(planting.error?.code, 'PT404')
  assert.equal(planting.error?.details, 'CROP_NOT_FOUND')
  const anonCatalog = await client().from('crops').select('*').in('id', fixtureCrops)
  assert.equal(anonCatalog.error?.code, '42501')
  await rpc(a.c, 'reset_farm_history')
  const afterReset = await a.c.from('crops').select('id').in('id', fixtureCrops)
  assert.equal(afterReset.error, null)
  assert.deepEqual(afterReset.data, [])
  result = { environment: staging ? 'VERIFIED_REMOTE' : 'VERIFIED_LOCAL_ONLY', auth: 'PASS', periods: 'PASS', parity: 'PASS (summaries and daily crops)', legacyCompatibility: staging ? 'VERIFIED_LOCAL_ONLY (original SQL snapshot comparison)' : 'PASS (both original SQL definitions, today/week/all, only approved fields removed)', isolation: 'PASS', errors: 'PASS', readOnly: 'PASS', reset: 'PASS', inactiveCropRls: 'PASS (own finalized only; foreign/unreferenced/focusing/paused/anon denied; original SELECT columns; active-only list/planting; last-reference removal)', examples: responses, focusExamples: focusResponses }
} finally {
  const failures = []
  for (const a of accounts) {
    try {
      const logout = await a.c.auth.signOut()
      assert.equal(logout.error, null)
      assert.equal((await a.c.auth.getSession()).data.session, null)
      sql(`with removed as (delete from auth.users where id='${a.id}' and email='${a.email}' and raw_user_meta_data->>'crop_history_test_run'='${run}' returning id) select count(*) as removed from removed`, true)
      const rows = sql(`select json_build_object('users',(select count(*) from auth.users where id='${a.id}'),'profiles',(select count(*) from public.profiles where id='${a.id}'),'plots',(select count(*) from public.farm_plots where user_id='${a.id}'),'sessions',(select count(*) from public.focus_sessions where user_id='${a.id}')) as cleanup`)
      const cleanup = staging ? rows[0].cleanup : rows
      assert.ok(Object.values(cleanup).every(n => n === 0), 'Test account cleanup incomplete')
    } catch { failures.push(a.id) }
  }
  try {
    const ids = fixtureCrops.map(id => `'${id}'`).join(',')
    sql(`with removed as (delete from public.crops where id in (${ids}) and name like 'crop-e2e-${run}-%' and not is_active returning id) select count(*) as removed from removed`, true)
    const rows = sql(`select count(*)::int as remaining from public.crops where id in (${ids})`)
    assert.equal(staging ? rows[0].remaining : rows, 0, 'Test crop cleanup incomplete')
  } catch { failures.push(...fixtureCrops) }
  assert.equal(failures.length, 0, `Cleanup failed for test fixture IDs: ${failures.join(',')}`)
}
console.log(JSON.stringify({ ...result, cleanup: 'PASS (both temporary accounts, owned data and five test-only inactive crops removed)' }, null, 2))
