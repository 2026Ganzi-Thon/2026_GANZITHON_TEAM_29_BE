# RPC 계약

이 문서는 프론트엔드와 A/B 백엔드가 공유하는 계약입니다. Phase 2에서 구현된 A RPC 외의 반환 형식과 상세 제약은 결정 전까지 `TBD`입니다.

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

상세한 소유권·마이그레이션 계약은 [A/B 연동 문서](../integration/a-to-b-contract.md)를 따릅니다. B 테이블은 현재 마이그레이션에 없습니다.

## 인증

```js
await supabase.auth.signUp({ email, password, options: { data: { nickname } } })
await supabase.auth.signInWithPassword({ email, password })
await supabase.auth.getSession()
await supabase.auth.signOut()
```

`nickname`은 표시 정보로만 사용하고 소유권 판단에 사용하지 않습니다. 이메일 확인, redirect URL, Auth 상세 오류 매핑은 운영 프로젝트 확정 후 A/프론트엔드가 결정합니다.

## 오류 계약

`supabase-js` DB 호출의 `error`는 `code`, `message`, `details`, `hint` 네 필드를 제공하며 HTTP status를 노출하지 않습니다. HTTP status는 네트워크 응답이나 커스텀 `fetch`로 확인합니다.

| 비즈니스 오류 | `error.code` | `error.message` | HTTP | 적용 |
|---|---|---|---:|---|
| `UNAUTHENTICATED` | `PT401` | `UNAUTHENTICATED` | 401 | 함수 본문에 도달했지만 `auth.uid()`가 없음 |
| `NOT_FOUND` | `PT404` | `NOT_FOUND` | 404 | 인증 사용자의 프로필 없음 |
| `INVALID_INPUT` | `22023` | `INVALID_INPUT` | 400 | 허용되지 않은 입력 |
| `INVALID_STATE` | `TBD` | `INVALID_STATE` | `TBD` | B 상태 전이 계약 후 A/B 결정 |

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
- `INVALID_STATE`: B 상태 전이 구현 후 SQLSTATE가 확정될 때 분기 추가

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

`ensure_farm()`은 아직 호출하지 않습니다. B 구현 후 트랜잭션 경계와 재시도 소유자를 A/B가 결정합니다.

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

`ensure_farm()`, `start_focus(p_plot_id, p_crop_id)`, `get_active_focus()`, `pause_focus(p_session_id)`, `resume_focus(p_session_id)`, `preview_stop_focus(p_session_id)`, `confirm_stop_focus(p_stop_token)`, `harvest_crop(p_session_id)`, `process_due_harvests()`, `ack_auto_harvest_notice(p_harvest_ids)`, `save_harvest_note(p_harvest_id, p_note)`, `start_rest(p_harvest_id)`, `reset_farm_history()`의 함수명과 입력명은 유지합니다. 반환 형식·상태 전이·메모/토큰 제약은 B가 제안하고 A/프론트엔드와 확정하기 전까지 `TBD`입니다.

## 상태

- 세션: `focusing`, `paused`, `seed_saved`, `ripe`, `harvested`
- 농장 표시: `empty`, `growing`, `ripe`, `harvested`

세션 상태 전이, 실패 롤백, 자동 수확 경계는 B/A 공동 결정 전까지 `TBD`입니다.
