import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { randomUUID } from 'node:crypto'

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

async function request(path, { token, body, method = 'POST' } = {}) {
  const response = await fetch(`${apiUrl}${path}`, {
    method,
    headers: {
      apikey: publishableKey,
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  })
  const text = await response.text()
  const payload = text ? JSON.parse(text) : null
  return { response, payload }
}

const suffix = `${Date.now()}-${randomUUID()}`
const email = `phase2-${suffix}@test.local`
const password = `LocalOnly-${randomUUID()}-Aa1!`

const signup = await request('/auth/v1/signup', {
  body: { email, password, data: { nickname: '통합농부' } },
})
assert.equal(signup.response.status, 200, JSON.stringify(signup.payload))
assert.ok(signup.payload?.access_token, 'Local signup did not return an access token')

const token = signup.payload.access_token

const profile = await request('/rest/v1/rpc/get_my_profile', { token, body: {} })
assert.equal(profile.response.status, 200, JSON.stringify(profile.payload))
assert.deepEqual(profile.payload, [
  {
    nickname: '통합농부',
    timezone: 'Asia/Seoul',
    onboarded: false,
    onboarded_at: null,
  },
])

const firstOnboarding = await request('/rest/v1/rpc/complete_onboarding', { token, body: {} })
assert.equal(firstOnboarding.response.status, 200, JSON.stringify(firstOnboarding.payload))
assert.ok(firstOnboarding.payload, 'Onboarding timestamp is missing')

const repeatedOnboarding = await request('/rest/v1/rpc/complete_onboarding', { token, body: {} })
assert.equal(repeatedOnboarding.response.status, 200, JSON.stringify(repeatedOnboarding.payload))
assert.equal(repeatedOnboarding.payload, firstOnboarding.payload, 'Onboarding must be idempotent')

const crops = await request('/rest/v1/rpc/list_crops', {
  token,
  body: { p_energy: 'low' },
})
assert.equal(crops.response.status, 200, JSON.stringify(crops.payload))
assert.equal(crops.payload.length, 6)
assert.deepEqual(
  crops.payload.filter((crop) => crop.recommended).map((crop) => crop.name),
  ['새싹채소', '당근'],
)

const invalidEnergy = await request('/rest/v1/rpc/list_crops', {
  token,
  body: { p_energy: 'invalid' },
})
assert.equal(invalidEnergy.response.status, 400)
assert.equal(invalidEnergy.payload?.message, 'INVALID_INPUT')

const anonymousProfile = await request('/rest/v1/rpc/get_my_profile', { body: {} })
assert.ok(anonymousProfile.response.status >= 400, 'Anonymous RPC request must be rejected')

const signout = await request('/auth/v1/logout', { token, body: {} })
assert.ok([200, 204].includes(signout.response.status), JSON.stringify(signout.payload))

console.log('Auth/RPC integration: PASS (signup, profile, onboarding, crops, errors, signout)')
