import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { randomUUID } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const status = JSON.parse(
  execFileSync('npx', ['supabase', 'status', '-o', 'json'], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  }),
)
const apiUrl = status.API_URL
const publishableKey = status.PUBLISHABLE_KEY
assert.ok(apiUrl && publishableKey, 'Local Supabase API credentials are unavailable')

const projectId = readFileSync(new URL('../supabase/config.toml', import.meta.url), 'utf8').match(
  /^project_id\s*=\s*"([^"]+)"/m,
)?.[1]
assert.ok(projectId, 'Local Supabase project_id is unavailable')
const dbContainer = `supabase_db_${projectId}`
assert.equal(
  execFileSync('docker', ['ps', '--filter', `name=^/${dbContainer}$`, '--format', '{{.Names}}'], { encoding: 'utf8' }).trim(),
  dbContainer,
  'Local Supabase database container is unavailable',
)

function runLocalSql(sql) {
  execFileSync('docker', ['exec', dbContainer, 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres', '-c', sql], {
    stdio: 'ignore',
  })
}

function createTestClient() {
  return createClient(apiUrl, publishableKey, {
    auth: { autoRefreshToken: false, detectSessionInUrl: false, persistSession: false },
  })
}

async function rawRpc(name, body) {
  const response = await fetch(`${apiUrl}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: { apikey: publishableKey, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  return { status: response.status, body: await response.json() }
}

const suffix = `${Date.now()}-${randomUUID()}`
const password = `LocalOnly-${randomUUID()}-Aa1!`
const userIds = []
const clients = []

async function signup(label) {
  const client = createTestClient()
  clients.push(client)
  const { data, error } = await client.auth.signUp({
    email: `history-${label}-${suffix}@test.local`,
    password,
    options: { data: { nickname: `history-${label}` } },
  })
  assert.equal(error, null, error?.message)
  assert.ok(data.user?.id && data.session?.access_token)
  userIds.push(data.user.id)
  return { client, id: data.user.id }
}

try {
  const owner = await signup('owner')
  const other = await signup('other')
  const ownerFarm = await owner.client.rpc('ensure_farm')
  const otherFarm = await other.client.rpc('ensure_farm')
  assert.equal(ownerFarm.error, null)
  assert.equal(otherFarm.error, null)

  const uuid = /^[0-9a-f-]{36}$/
  for (const value of [owner.id, other.id, ownerFarm.data[0].plot_id, ownerFarm.data[1].plot_id, ownerFarm.data[2].plot_id, otherFarm.data[0].plot_id]) {
    assert.match(value, uuid)
  }

  runLocalSql(`insert into public.focus_sessions
    (user_id, plot_id, crop_id, status, started_at, target_seconds, focused_seconds, record_date)
    values
    ('${owner.id}', '${ownerFarm.data[0].plot_id}', '10000000-0000-4000-8000-000000000001', 'seed_saved', now(), 600, 0, '2026-01-01'),
    ('${owner.id}', '${ownerFarm.data[1].plot_id}', '10000000-0000-4000-8000-000000000001', 'ripe', now(), 600, 30, '2026-01-02'),
    ('${owner.id}', '${ownerFarm.data[2].plot_id}', '10000000-0000-4000-8000-000000000001', 'focusing', now(), 600, 999, '2026-01-03'),
    ('${other.id}', '${otherFarm.data[0].plot_id}', '10000000-0000-4000-8000-000000000001', 'seed_saved', now(), 600, 700, '2026-01-04')`)

  const history = await owner.client.rpc('get_focus_history', { p_period: 'all' })
  assert.equal(history.error, null, history.error?.message)
  assert.deepEqual(history.data.range, {
    start_date: '2026-01-01',
    end_date: '2026-01-02',
    timezone: 'Asia/Seoul',
  })
  assert.deepEqual(history.data.summary, { focused_seconds: 30, seed_count: 1, harvest_count: null })
  assert.deepEqual(history.data.capabilities, { harvest_count: false })
  assert.deepEqual(history.data.items, [
    { record_date: '2026-01-01', focused_seconds: 0, seed_count: 1, harvest_count: null },
    { record_date: '2026-01-02', focused_seconds: 30, seed_count: 0, harvest_count: null },
  ])

  const invalid = await owner.client.rpc('get_focus_history', { p_period: 'month' })
  assert.equal(invalid.error?.code, '22023')
  assert.equal(invalid.error?.message, 'INVALID_INPUT')

  const anonymous = await rawRpc('get_focus_history', { p_period: 'all' })
  assert.equal(anonymous.status, 401)
  assert.equal(anonymous.body.code, '42501')

  console.log('Focus history integration checks passed')
} finally {
  for (const client of clients) await client.auth.signOut().catch(() => {})
  for (const id of userIds) {
    if (/^[0-9a-f-]{36}$/.test(id)) runLocalSql(`delete from auth.users where id = '${id}'`)
  }
}
