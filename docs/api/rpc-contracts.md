# RPC 계약

이 문서는 프론트엔드와 A/B 백엔드가 공유하는 계약입니다. 명시된 RPC 계약을 적용하며, 미확정 반환 형식과 제약은 `TBD`입니다.

## 공통 규칙

- RPC 함수명은 `snake_case`, 입력 매개변수는 `p_` 접두사를 사용합니다.
- `user_id`는 `auth.users.id` UUID이며 `profiles.id`와 같습니다. 사용자 ID는 입력받지 않고 `auth.uid()`로 확인합니다.
- `plot_id`, `crop_id`, `session_id`는 모두 UUID입니다.
- `target_seconds`는 심기 시점의 `crops.target_seconds`를 세션에 복사합니다. 클라이언트 값을 신뢰하지 않습니다.
- `target_seconds`는 `> 0`, `focused_seconds`는 서버가 확정하는 `>= 0` 정수 초입니다.
- 집중 시작 직후 중단하면 `focused_seconds = 0`인 `seed_saved` 기록을 허용합니다. 서버는 이를 1초로 보정하지 않으며 음수는 거부합니다.
- 시각은 UTC `TIMESTAMPTZ`로 저장하고, `record_date`는 사용자 시간대의 세션 시작일입니다.
- 세션당 수확은 한 번만 허용합니다.

## A/B 공통 데이터 계약

| 항목 | 계약 |
|---|---|
| `farm_plots.id` | UUID (`plot_id`) |
| `farm_plots.plot_index` | 사용자별 1부터 시작; 초기 1~12, 추후 4칸 단위 확장 |
| `farm_plots` 유일성 | `UNIQUE (user_id, plot_index)`, `UNIQUE (user_id, id)` |
| `focus_sessions.id` | UUID (`session_id`) |
| `focus_sessions.plot_id` | `(user_id, plot_id)` → `farm_plots(user_id, id)` |
| `focus_sessions.crop_id` | UUID → `crops.id` |
| `harvests.session_id` | `UNIQUE` |

상세한 소유권·마이그레이션 계약은 [A/B 연동 문서](../integration/a-to-b-contract.md)를 따릅니다. B의 농장 기반 마이그레이션은 `farm_plots`를 생성합니다.

## 인증

```js
await supabase.auth.signUp({ email, password, options: { data: { nickname } } })
await supabase.auth.signInWithPassword({ email, password })
await supabase.auth.getSession()
await supabase.auth.signOut()
```

`nickname`은 표시 정보로만 사용하고 소유권 판단에 사용하지 않습니다. 신규 가입을 허용하고 Confirm email은 OFF이며 이메일 인증 링크를 사용하지 않습니다. Staging Dashboard 저장은 완료됐지만 원격 회원가입 동작은 아직 실측하지 않았습니다. Redirect URL과 Auth 상세 오류 매핑은 A/프론트엔드가 별도로 확정합니다.

## 오류 계약

`supabase-js` DB 호출의 `error`는 `code`, `message`, `details`, `hint` 네 필드를 제공하며 HTTP status를 노출하지 않습니다. HTTP status는 네트워크 응답이나 커스텀 `fetch`로 확인합니다.

| 비즈니스 오류 | `error.code` | `error.message` | HTTP | 적용 |
|---|---|---|---:|---|
| `UNAUTHENTICATED` | `PT401` | `UNAUTHENTICATED` | 401 | 함수 본문에 도달했지만 `auth.uid()`가 없음 |
| `NOT_FOUND` | `PT404` | `NOT_FOUND` | 404 | 인증 사용자의 프로필 없음 |
| `INVALID_INPUT` | `22023` | `INVALID_INPUT` | 400 | 허용되지 않은 입력 |
| `INVALID_STATE` | `PT409` | 표시 문구 | 409 | 집중 세션 RPC의 `details`에 식별자 포함 |

익명 호출은 함수 `EXECUTE`가 없어 본문에 도달하지 않습니다. 실제 응답은 HTTP 401, `code = 42501`, `message = permission denied for function ...`입니다. 프론트엔드는 세션이 없는 `42501` 응답을 `UNAUTHENTICATED`로 정규화합니다. `AUTH_REQUIRED`, `PROFILE_NOT_FOUND`는 더 이상 사용하지 않습니다.

### 프론트엔드 정규화 규칙

`message`보다 `code`를 먼저 판단합니다.

```js
function normalizeBackendError(error, hasSession) {
  if (error.code === 'PGRST301' || error.code === 'PT401') return 'UNAUTHENTICATED'
  if (error.code === '42501' && !hasSession) return 'UNAUTHENTICATED'
  if (error.code === '22023') return 'INVALID_INPUT'
  if (error.code === 'PT404') return 'NOT_FOUND'
  return 'UNKNOWN'
}
```

- 로그아웃/JWT 누락: 클라이언트가 토큰을 보내지 않아 `42501`; `UNAUTHENTICATED`로 정규화
- 변조·파싱 불가 JWT: `PGRST301`; `UNAUTHENTICATED`로 정규화
- 세션이 있는 `42501`: 권한 설정 오류이므로 사용자 문구로 숨기고 운영 오류로 기록
- 집중 세션 상태 전이 오류는 `PT409`와 `details`로 분기합니다.

`signOut()`은 클라이언트 세션을 제거하지만 이미 발급된 access JWT는 만료 전까지 유효할 수 있습니다. 로그아웃 후 토큰을 보관·재사용하지 않습니다.

## Phase 2 A RPC

### `get_my_profile()`

- 입력: 없음
- 반환: `[{ nickname, timezone, onboarded, onboarded_at }]`
- 내부 컬럼 `id`, `created_at`은 반환하지 않음

```js
const { data, error } = await supabase.rpc('get_my_profile')
// data: [{ nickname: '농부', timezone: 'Asia/Seoul', onboarded: false, onboarded_at: null }]
```

### `complete_onboarding()`

- 입력: 없음
- 반환: 최초 완료 시각 `TIMESTAMPTZ` 스칼라
- 반복·동시 호출: 모두 같은 최초 시각 반환

```js
const { data, error } = await supabase.rpc('complete_onboarding')
// data: '2026-11-10T15:30:00+00:00'
```

`ensure_farm()`은 구현되어 있으며 온보딩 완료와의 호출 순서·재시도 소유자는 A/B/프론트엔드가 확정합니다.

### `list_crops(p_energy)`

- `p_energy`: `TEXT`, `low | medium | high | NULL`
- 반환: `[{ crop_id, name, target_seconds, recommended, sort_order }]`
- `sort_order ASC`; `NULL`은 6종 모두 `recommended = false`

```js
const { data, error } = await supabase.rpc('list_crops', { p_energy: 'low' })
```

## 후속 A RPC

| 함수 | 입력 | 상태 |
|---|---|---|
| `get_my_farm()` | 없음 | B 쓰기 모델 후 구현; 세부 응답 `TBD` |
| `get_focus_history(p_period)` | `today | week | all` | B 쓰기 모델 후 구현; 세부 응답 `TBD` |

권장안·예시·결정 대기 항목은 [조회 모델 설계](read-model-design.md)에 기록합니다.

## B 담당 RPC

### `ensure_farm()`

- 입력: 없음
- 반환: `[{ plot_id, plot_index }]` (UUID, INTEGER), `plot_index` 오름차순
- 인증된 본인의 초기 밭 1~12번을 보장합니다. 반복·동시 호출에서도 기존 밭 ID를 유지합니다.
- 프로필이 없으면 `PT404`, 익명 호출은 실행 권한이 없어 `42501`입니다.
- 농장 상태 조회는 후속 `get_my_farm()`이 담당합니다.

`preview_stop_focus(p_session_id)`, `confirm_stop_focus(p_stop_token)`, `harvest_crop(p_session_id)`, `process_due_harvests()`, `ack_auto_harvest_notice(p_harvest_ids)`, `save_harvest_note(p_harvest_id, p_note)`, `start_rest(p_harvest_id)`, `reset_farm_history()`의 함수명과 입력명은 유지합니다. 반환 형식·상태 전이·메모/토큰 제약은 B가 제안하고 A/프론트엔드와 확정하기 전까지 `TBD`입니다.

## 상태

- 세션: `focusing`, `paused`, `seed_saved`, `ripe`, `harvested`
- 농장 표시: `empty`, `growing`, `ripe`, `harvested`

세션 상태 전이, 실패 롤백, 자동 수확 경계는 B/A 공동 결정 전까지 `TBD`입니다.

## 집중 세션 (Issue #4)

- `start_focus(p_plot_id, p_crop_id)` (POST) → `{ session_id, plot_id, crop_id, status, started_at, target_seconds, server_now }`. 본인 빈 밭과 활성 작물만 허용하며, 사용자별 `focusing` 또는 `paused` 세션을 한 개로 제한합니다.
- `get_active_focus()` (GET) → `{ session, server_now, show_overwork_notice }`. `session`은 `null` 또는 `{ session_id, plot_id, crop_id, status, started_at, paused_at, target_seconds, focused_seconds, remaining_seconds }`입니다.
- `pause_focus(p_session_id)` (POST) → `{ session_id, status, paused_at, remaining_seconds, server_now }`. 이미 일시정지 상태면 기존 일시정지 시각을 반환합니다.
- `resume_focus(p_session_id)` (POST) → `{ session_id, status, remaining_seconds, server_now }`. 이미 집중 중이고 목표 도달 전이면 누적 휴식 시간을 수정하지 않습니다.

서버는 경과 시간에서 누적 휴식 시간을 뺀 뒤 초 단위로 내림합니다. 일시정지 중에는 `paused_at`을 계산 기준으로 사용합니다. `record_date`는 사용자 시간대 기준 시작일입니다.

### 집중 세션 오류

기존 A RPC는 `message`로 비즈니스 오류를 식별합니다. 집중 세션 RPC는 Notion 계약에 따라 `details`에 식별자를, `message`에 표시 문구를 둡니다. 프론트엔드는 집중 세션 응답의 `code`와 `details`를 사용합니다.

| SQLSTATE / HTTP | details |
| --- | --- |
| PT400 / 400 | INVALID_INPUT |
| PT401 / 401 | UNAUTHENTICATED |
| PT404 / 404 | PLOT_NOT_FOUND, CROP_NOT_FOUND, SESSION_NOT_FOUND |
| PT409 / 409 | PLOT_OCCUPIED, ACTIVE_SESSION_EXISTS, INVALID_STATE, PAUSE_EXPIRED |

비활성 작물은 `CROP_NOT_FOUND`로 처리합니다. 익명 실행은 권한 계층에서 차단되며 기존과 동일하게 `42501`이 반환될 수 있습니다.

### 완료·만료 및 과로 안내

- 조회는 목표 도달과 24시간 일시정지 만료 세션을 숨기며 DB 상태를 변경하지 않습니다.
- 후속 서버 처리에서 목표 도달은 `ripe`, 일시정지 만료는 `seed_saved`로 확정할 예정입니다. 확정 전에는 기존 활성 세션이 UNIQUE 제약에 남으므로 새 시작이 409로 거부될 수 있습니다. 새 시작 전 자동 확정 여부는 팀 정책 결정 대기입니다.
- `show_overwork_notice`는 세션이 없으면 `false`입니다. 활성 세션에도 현재는 임시로 `false`를 반환하며, 표시 조건과 표시 이력 정책은 결정 대기입니다.
