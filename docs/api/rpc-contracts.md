# RPC 계약

이 문서는 프론트엔드와 A/B 백엔드가 공유하는 계약입니다. Phase 2에서 구현된 A RPC 외의 반환 형식과 상세 제약은 합의 전까지 `TBD`입니다.

## 공통 규칙

- RPC 함수명은 `snake_case`, 입력 매개변수는 `p_` 접두사를 사용합니다.
- `user_id`는 `auth.users.id` UUID이며 `profiles.id`와 같습니다. RPC는 사용자 ID를 입력받지 않고 `auth.uid()`로 확인합니다.
- `plot_id`, `crop_id`, `session_id`는 모두 UUID입니다.
- `target_seconds`는 작물을 심을 때 세션에 복사하는 양의 정수 초입니다. 클라이언트 값을 신뢰하지 않고 `crops.target_seconds`를 사용합니다.
- `focused_seconds`는 서버가 확정하는 초 단위 정수입니다.
- 시각은 UTC `TIMESTAMPTZ`로 저장하고, `record_date`는 사용자 시간대 기준 세션 시작일입니다.
- 세션당 수확은 한 번만 허용합니다.

## A/B 공통 데이터 계약

| 항목 | 계약 |
|---|---|
| `farm_plots.id` | UUID (`plot_id`) |
| `farm_plots.plot_index` | 사용자별 초기 1~12, 추후 4칸 단위 확장 |
| `farm_plots` 유일성 | `UNIQUE (user_id, plot_index)`, 복합 FK를 위한 `UNIQUE (user_id, id)` |
| `focus_sessions.id` | UUID (`session_id`) |
| `focus_sessions.plot_id` | `(user_id, plot_id)` → `farm_plots(user_id, id)` |
| `focus_sessions.crop_id` | UUID → `crops.id` |
| `harvests` 유일성 | `UNIQUE (session_id)` |

B 담당 테이블은 이 마이그레이션에서 생성하지 않습니다.

## 인증

인증은 RPC가 아닌 Supabase Auth SDK를 사용합니다.

```js
await supabase.auth.signUp({ email, password, options: { data: { nickname } } })
await supabase.auth.signInWithPassword({ email, password })
await supabase.auth.getSession()
await supabase.auth.signOut()
```

`nickname`은 표시 정보로만 사용하며 인증·소유권 판단에 사용하지 않습니다. 이메일 확인 여부, redirect URL, 상세 Auth 오류 매핑은 `TBD`입니다.

## Phase 2 A RPC

### `get_my_profile()`

- 입력: 없음
- 반환: 한 행 `{ nickname, timezone, onboarded, onboarded_at }`
- 오류: `AUTH_REQUIRED`, `PROFILE_NOT_FOUND`

```js
const { data, error } = await supabase.rpc('get_my_profile')
// data: [{ nickname: '농부', timezone: 'Asia/Seoul', onboarded: false, onboarded_at: null }]
```

### `complete_onboarding()`

- 입력: 없음
- 반환: 최초 완료 시각 `TIMESTAMPTZ`(스칼라)
- 멱등성: 반복 호출은 기존 시각을 유지
- 오류: `AUTH_REQUIRED`, `PROFILE_NOT_FOUND`

```js
const { data, error } = await supabase.rpc('complete_onboarding')
// data: '2026-11-10T15:30:00+00:00'
```

`ensure_farm()`을 호출하지 않습니다. B 구현 병합 후 기존 RPC 이름과 입력을 바꾸지 않는 연결 방식을 공동 검토합니다.

### `list_crops(p_energy)`

- `p_energy`: `TEXT`, `low | medium | high | NULL`
- 반환 행: `{ crop_id, name, target_seconds, recommended, sort_order }`
- 정렬: `sort_order ASC`
- `NULL`: 6종을 모두 반환하고 `recommended = false`
- 오류: 허용 범위 외 입력은 `INVALID_INPUT` (SQLSTATE `22023`)

```js
const { data, error } = await supabase.rpc('list_crops', { p_energy: 'low' })
// data[0]: { crop_id: '...', name: '새싹채소', target_seconds: 600, recommended: true, sort_order: 1 }
```

## 후속 A RPC

| 함수 | 입력 | 반환 | 상태 |
|---|---|---|---|
| `get_my_farm()` | 없음 | 밭별 `empty | growing | ripe | harvested`; 상세 필드 `TBD` | B 쓰기 모델 후 구현 |
| `get_focus_history(p_period)` | `p_period` 허용 값 `TBD` | `record_date` 포함; 상세 필드 `TBD` | B 쓰기 모델 후 구현 |

## B 담당 RPC

| 함수 | 입력 | 반환 |
|---|---|---|
| `ensure_farm()` | 없음 | `TBD` |
| `start_focus(p_plot_id, p_crop_id)` | UUID, UUID | `TBD` |
| `get_active_focus()` | 없음 | `TBD` |
| `pause_focus(p_session_id)` | UUID | `TBD` |
| `resume_focus(p_session_id)` | UUID | `TBD` |
| `preview_stop_focus(p_session_id)` | UUID | `TBD` |
| `confirm_stop_focus(p_stop_token)` | 타입·만료 규칙 `TBD` | `TBD` |
| `harvest_crop(p_session_id)` | UUID | `TBD` |
| `process_due_harvests()` | 없음 | `TBD` |
| `ack_auto_harvest_notice(p_harvest_ids)` | UUID 배열 | `TBD` |
| `save_harvest_note(p_harvest_id, p_note)` | UUID, 메모 제약 `TBD` | `TBD` |
| `start_rest(p_harvest_id)` | UUID | `TBD` |
| `reset_farm_history()` | 없음; 삭제·보존 범위 `TBD` | `TBD` |

## 상태

- 세션: `focusing`, `paused`, `seed_saved`, `ripe`, `harvested`
- 농장 조회 응답: `empty`, `growing`, `ripe`, `harvested`

세션 상태 전이, 실패 시 롤백, 자동 수확 경계는 `TBD`입니다.

## 계약 변경

함수명, 입력명, 공통 ID 또는 상태 변경은 프론트엔드와 A/B 백엔드 합의가 필요합니다. 변경 PR에 호환성 영향과 마이그레이션 방법을 기록합니다.
