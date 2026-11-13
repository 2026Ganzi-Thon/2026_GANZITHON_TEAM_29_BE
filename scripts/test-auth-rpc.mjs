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

assert.ok(apiUrl, 'Local Supabase API URL is unavailable')
assert.ok(publishableKey, 'Local Supabase publishable key is unavailable')

const projectId = readFileSync(new URL('../supabase/config.toml', import.meta.url), 'utf8').match(
  /^project_id\s*=\s*"([^"]+)"/m,
)?.[1]
assert.ok(projectId, 'Local Supabase project_id is unavailable')

const dbContainer = execFileSync(
  'docker',
  ['ps', '--filter', `name=^/supabase_db_${projectId}$`, '--format', '{{.Names}}'],
  { encoding: 'utf8' },
).trim()
assert.equal(dbContainer, `supabase_db_${projectId}`, 'Local Supabase database container is unavailable')

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

async function rawRpc(name, body, token) {
  const response = await fetch(`${apiUrl}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: {
      apikey: publishableKey,
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  })
  const text = await response.text()
  return { status: response.status, body: text ? JSON.parse(text) : null }
}

function assertPostgrestError(error, { code, message }) {
  assert.ok(error, `Expected PostgREST error ${message}`)
  assert.equal(error.code, code)
  assert.equal(error.message, message)
  assert.equal(error.details, null)
  assert.equal(error.hint, null)
}

const suffix = `${Date.now()}-${randomUUID()}`
const password = `LocalOnly-${randomUUID()}-Aa1!`
const createdUserIds = []
const clients = []

async function signup(label, nickname, includeNickname = true) {
  const client = createTestClient()
  clients.push(client)
  const credentials = {
    email: `phase25-${label}-${suffix}@test.local`,
    password,
    ...(includeNickname ? { options: { data: { nickname } } } : {}),
  }
  const { data, error } = await client.auth.signUp(credentials)
  assert.equal(error, null, `${label} signup failed: ${error?.message}`)
  assert.ok(data.user?.id, `${label} signup did not return a user`)
  assert.ok(data.session?.access_token, `${label} signup did not return a session`)
  createdUserIds.push(data.user.id)
  return { client, user: data.user, token: data.session.access_token }
}

try {
  const userA = await signup('a', '테스트🌱농부')
  const userB = await signup('b', undefined, false)
  const empty = await signup('empty', '')
  const spaces = await signup('spaces', '   ')
  const boundary = await signup('boundary', '가'.repeat(30))
  const overlong = await signup('overlong', '나'.repeat(31))

  // Both requests race to initialize a farm that does not yet exist.
  const [firstFarm, concurrentFarm] = await Promise.all([
    userA.client.rpc('ensure_farm'),
    userA.client.rpc('ensure_farm'),
  ])
  assert.equal(firstFarm.error, null)
  assert.equal(concurrentFarm.error, null)
  assert.deepEqual(concurrentFarm.data, firstFarm.data)
  assert.deepEqual(firstFarm.data.map((plot) => plot.plot_index), Array.from({ length: 12 }, (_, i) => i + 1))
  assert.equal(new Set(firstFarm.data.map((plot) => plot.plot_id)).size, 12)
  assert.ok(firstFarm.data.every(({ plot_id }) => /^[0-9a-f-]{36}$/.test(plot_id)))
  const repeatedFarm = await userA.client.rpc('ensure_farm')
  assert.equal(repeatedFarm.error, null)
  assert.deepEqual(repeatedFarm.data, firstFarm.data)

  const otherFarm = await userB.client.rpc('ensure_farm')
  assert.equal(otherFarm.error, null)
  assert.equal(otherFarm.data.length, 12)
  const ownPlotIds = new Set(firstFarm.data.map((plot) => plot.plot_id))
  assert.ok(otherFarm.data.every((plot) => !ownPlotIds.has(plot.plot_id)))

  const { data: visiblePlots, error: farmReadError } = await userB.client.from('farm_plots').select('id')
  assert.equal(farmReadError, null)
  assert.deepEqual(new Set(visiblePlots.map((plot) => plot.id)), new Set(otherFarm.data.map((plot) => plot.plot_id)))
  const { error: foreignWriteError } = await userB.client
    .from('farm_plots').update({ plot_index: 13 }).eq('id', firstFarm.data[0].plot_id)
  assert.equal(foreignWriteError?.code, '42501')

  const anonymousFarm = await rawRpc('ensure_farm', {})
  assert.equal(anonymousFarm.status, 401)
  assert.equal(anonymousFarm.body?.code, '42501')

  const profileCases = [
    [userA, '테스트🌱농부'],
    [userB, '농부'],
    [empty, '농부'],
    [spaces, '농부'],
    [boundary, '가'.repeat(30)],
    [overlong, '나'.repeat(30)],
  ]

  for (const [account, expectedNickname] of profileCases) {
    const { data, error } = await account.client
      .from('profiles')
      .select('id,nickname,timezone,onboarded_at')
      .single()
    assert.equal(error, null, error?.message)
    assert.deepEqual(data, {
      id: account.user.id,
      nickname: expectedNickname,
      timezone: 'Asia/Seoul',
      onboarded_at: null,
    })
  }

  const { data: otherProfile, error: otherProfileError } = await userA.client
    .from('profiles')
    .select('id')
    .eq('id', userB.user.id)
  assert.equal(otherProfileError, null)
  assert.deepEqual(otherProfile, [], 'RLS must hide another user profile')

  const { error: profileUpdateError } = await userA.client
    .from('profiles')
    .update({ nickname: '침입' })
    .eq('id', userA.user.id)
  assert.equal(profileUpdateError?.code, '42501')
  const { error: profileDeleteError } = await userA.client.from('profiles').delete().eq('id', userA.user.id)
  assert.equal(profileDeleteError?.code, '42501')

  const concurrentOnboarding = await Promise.all(
    Array.from({ length: 8 }, () => userA.client.rpc('complete_onboarding')),
  )
  for (const result of concurrentOnboarding) assert.equal(result.error, null, result.error?.message)
  const onboardingTimes = concurrentOnboarding.map(({ data }) => data)
  assert.equal(new Set(onboardingTimes).size, 1, 'Concurrent onboarding must preserve one timestamp')
  assert.ok(onboardingTimes[0])

  const repeatedOnboarding = await userA.client.rpc('complete_onboarding')
  assert.equal(repeatedOnboarding.error, null)
  assert.equal(repeatedOnboarding.data, onboardingTimes[0])

  const userBProfile = await userB.client.rpc('get_my_profile')
  assert.equal(userBProfile.error, null)
  assert.equal(userBProfile.data[0].onboarded_at, null, 'User A onboarding must not affect user B')

  const expectedCrops = [
    ['10000000-0000-4000-8000-000000000001', '새싹채소', 600, 1],
    ['10000000-0000-4000-8000-000000000002', '당근', 1200, 2],
    ['10000000-0000-4000-8000-000000000003', '딸기', 1800, 3],
    ['10000000-0000-4000-8000-000000000004', '옥수수', 2700, 4],
    ['10000000-0000-4000-8000-000000000005', '토마토', 3600, 5],
    ['10000000-0000-4000-8000-000000000006', '호박', 5400, 6],
  ]
  const recommendations = {
    low: ['새싹채소', '당근'],
    medium: ['딸기', '옥수수'],
    high: ['토마토', '호박'],
  }

  for (const energy of ['low', 'medium', 'high', null]) {
    const { data, error } = await userA.client.rpc('list_crops', { p_energy: energy })
    assert.equal(error, null, error?.message)
    assert.deepEqual(
      data.map(({ crop_id, name, target_seconds, sort_order }) => [crop_id, name, target_seconds, sort_order]),
      expectedCrops,
    )
    assert.deepEqual(
      data.filter(({ recommended }) => recommended).map(({ name }) => name),
      energy === null ? [] : recommendations[energy],
    )
  }

  const invalidEnergy = await userA.client.rpc('list_crops', { p_energy: 'invalid' })
  assertPostgrestError(invalidEnergy.error, { code: '22023', message: 'INVALID_INPUT' })
  const invalidEnergyHttp = await rawRpc('list_crops', { p_energy: 'invalid' }, userA.token)
  assert.equal(invalidEnergyHttp.status, 400)
  assert.deepEqual(invalidEnergyHttp.body, {
    code: '22023',
    details: null,
    hint: null,
    message: 'INVALID_INPUT',
  })

  const { error: cropInsertError } = await userA.client
    .from('crops')
    .insert({ name: '침입', target_seconds: 1, energy_level: 'low', sort_order: 99 })
  assert.equal(cropInsertError?.code, '42501')
  const { error: cropUpdateError } = await userA.client.from('crops').update({ target_seconds: 1 }).eq('sort_order', 1)
  assert.equal(cropUpdateError?.code, '42501')
  const { error: cropDeleteError } = await userA.client.from('crops').delete().eq('sort_order', 1)
  assert.equal(cropDeleteError?.code, '42501')

  const anonymousClient = createTestClient()
  const anonymousProfile = await anonymousClient.rpc('get_my_profile')
  assertPostgrestError(anonymousProfile.error, {
    code: '42501',
    message: 'permission denied for function get_my_profile',
  })
  const anonymousProfileHttp = await rawRpc('get_my_profile', {})
  assert.equal(anonymousProfileHttp.status, 401)
  assert.deepEqual(anonymousProfileHttp.body, {
    code: '42501',
    details: null,
    hint: null,
    message: 'permission denied for function get_my_profile',
  })

  const invalidJwt = await rawRpc('get_my_profile', {}, 'invalid.jwt.value')
  assert.equal(invalidJwt.status, 401)
  assert.equal(invalidJwt.body?.code, 'PGRST301')

  const missingProfile = await signup('missing-profile', '삭제대상')
  assert.match(missingProfile.user.id, /^[0-9a-f-]{36}$/)
  runLocalSql(`delete from public.profiles where id = '${missingProfile.user.id}'::uuid`)
  const missingFarm = await missingProfile.client.rpc('ensure_farm')
  assertPostgrestError(missingFarm.error, { code: 'PT404', message: 'NOT_FOUND' })
  const missingProfileResult = await missingProfile.client.rpc('get_my_profile')
  assertPostgrestError(missingProfileResult.error, { code: 'PT404', message: 'NOT_FOUND' })
  const missingProfileHttp = await rawRpc('get_my_profile', {}, missingProfile.token)
  assert.equal(missingProfileHttp.status, 404)
  assert.deepEqual(missingProfileHttp.body, {
    code: 'PT404',
    details: null,
    hint: null,
    message: 'NOT_FOUND',
  })

  const oldAccessToken = userA.token
  const signout = await userA.client.auth.signOut()
  assert.equal(signout.error, null)
  const afterSignout = await userA.client.rpc('get_my_profile')
  assert.equal(afterSignout.error?.code, '42501', 'Signed-out client must stop sending authenticated requests')
  const oldTokenRequest = await rawRpc('get_my_profile', {}, oldAccessToken)
  assert.equal(oldTokenRequest.status, 200, 'Existing access JWT remains valid until expiry after signout')

  console.log(
    'Auth/RPC integration: PASS (7 users, profile boundaries, RLS, concurrent onboarding, concurrent farm initialization, crops, error objects/status, JWT, signout)',
  )
} finally {
  await Promise.all(clients.map((client) => client.auth.signOut().catch(() => {})))
  if (createdUserIds.length > 0) {
    assert.ok(createdUserIds.every((id) => /^[0-9a-f-]{36}$/.test(id)), 'Unexpected test user id')
    const ids = createdUserIds.map((id) => `'${id}'::uuid`).join(',')
    runLocalSql(`delete from auth.users where id in (${ids})`)
  }
}
