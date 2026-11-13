# A 담당 프론트엔드 연동 가이드

이 문서는 Supabase JS를 사용하는 별도 프론트엔드 저장소의 연동 계약입니다. PR #7의 `get_my_farm()`과 PR #8의 `get_focus_history()`는 각각 `develop` 병합과 대상 환경 배포 후 호출할 수 있습니다. S 화면 원본은 백엔드 저장소에서 확인하지 못했으므로 제공된 화면 번호만 매핑하며 UI 전용 필드를 DB 계약으로 추가하지 않습니다.

## 클라이언트 설정과 키 구분

프론트엔드 빌드 도구가 공개 환경 변수를 읽어 `publicEnv`에 전달한다고 가정한 예시입니다. 실제 변수 노출 문법은 프론트엔드 프레임워크에 맞춥니다.

```js
import { createClient } from '@supabase/supabase-js'

const supabaseUrl = publicEnv.SUPABASE_URL
const supabasePublishableKey = publicEnv.SUPABASE_PUBLISHABLE_KEY

if (!supabaseUrl || !supabasePublishableKey) {
  throw new Error('Supabase public configuration is missing')
}

export const supabase = createClient(supabaseUrl, supabasePublishableKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
})
```

| 값 | 브라우저 사용 | 규칙 |
|---|---:|---|
| Project URL | 가능 | 환경별 URL 사용 |
| Publishable key | 가능 | RLS 적용을 전제로 공개 클라이언트에 사용 |
| Secret/service role key | 금지 | 서버 관리 환경에만 보관; 브라우저 번들·로그 금지 |
| DB 비밀번호·배포 토큰 | 금지 | 로컬 비밀 저장소 또는 보호된 CI 환경에만 보관 |

Staging과 Production 값을 섞지 않습니다. Secret이 노출되면 코드에서 숨기는 것으로 끝내지 않고 즉시 폐기·재발급합니다.

## Auth SDK 4개

확정 정책은 이메일/비밀번호, 신규 가입 허용, Confirm email OFF, 가입 metadata의 nickname 사용입니다.

```js
const signup = await supabase.auth.signUp({
  email,
  password,
  options: { data: { nickname } },
})

const login = await supabase.auth.signInWithPassword({ email, password })
const restored = await supabase.auth.getSession()
const logout = await supabase.auth.signOut()
```

| 화면 | 함수 | 성공 조건 | 실패·재시도 |
|---|---|---|---|
| S19 | `signUp()` | Confirm email OFF 환경에서 `user`와 `session` 확인 | 응답이 불명확하면 무조건 재가입하지 말고 `getSession()` 또는 로그인을 확인 |
| S18 | `signInWithPassword()` | `session.access_token`과 `user` 확인 | 자격 증명 오류 자동 재시도 금지 |
| 앱 시작 | `getSession()` | 저장된 세션 복원 | 초기 로딩 1회; DB 권한은 RPC/RLS가 최종 판단 |
| 로그아웃 | `signOut()` | 클라이언트 세션 제거 | 실패 표시 후 사용자 재시도; 이전 JWT를 보관·재사용하지 않음 |

nickname은 표시 정보이며 권한 판단에 사용하지 않습니다. 회원가입 트리거가 공백 nickname을 `농부`로 대체하고 최대 30자로 저장합니다. Confirm email OFF는 환경별 Dashboard 설정이므로 Production에서도 별도 확인합니다.

## 공통 오류 정규화

RPC 오류는 `message`보다 `code`를 먼저 확인합니다. B 집중 RPC의 `PT409`만 `details` 식별자를 추가로 사용합니다.

```js
export function normalizeBackendError(error, hasSession) {
  if (!error) return null
  if (error.code === 'PGRST301' || error.code === 'PT401') return 'UNAUTHENTICATED'
  if (error.code === '42501' && !hasSession) return 'UNAUTHENTICATED'
  if (error.code === 'PT404') return 'NOT_FOUND'
  if (error.code === '22023') return 'INVALID_INPUT'
  if (error.code === 'PT409') return error.details || 'INVALID_STATE'
  return 'UNKNOWN'
}
```

- 세션 없는 `42501`: 익명 역할의 함수 실행 차단이므로 `UNAUTHENTICATED`
- 세션이 있는 `42501`: 사용자 입력이 아닌 권한 배포 오류; 일반 오류 화면을 표시하고 운영 로그에 기록
- `PGRST301`: 파싱 불가·변조·만료 JWT
- 사용자 메시지에 토큰, SQL, DB 세부 오류를 표시하지 않음

## A RPC 5개

모든 A RPC는 로그인 세션이 필요합니다.

### `get_my_profile()` — S01

```js
const { data, error } = await supabase.rpc('get_my_profile')
```

```json
[
  {
    "nickname": "농부",
    "timezone": "Asia/Seoul",
    "onboarded": false,
    "onboarded_at": null
  }
]
```

내부 사용자 ID와 생성 시각은 반환하지 않습니다. 프로필이 없으면 `PT404 / NOT_FOUND`입니다.

### `complete_onboarding()` — S01

```js
const { data, error } = await supabase.rpc('complete_onboarding')
// data: "2026-11-10T15:30:00+00:00"
```

최초 완료 시각 스칼라를 반환합니다. 반복·동시 호출은 같은 최초 시각을 반환하므로 실패 복구 재시도가 가능합니다.

### `list_crops(p_energy)` — S04/S05

```js
const { data, error } = await supabase.rpc('list_crops', {
  p_energy: 'medium', // low | medium | high | null
})
```

```json
[
  {
    "crop_id": "10000000-0000-4000-8000-000000000001",
    "name": "새싹채소",
    "target_seconds": 600,
    "recommended": false,
    "sort_order": 1
  }
]
```

활성 작물 6종을 `sort_order` 오름차순 반환합니다. `null`이면 모두 `recommended = false`; 허용되지 않은 문자열은 `22023 / INVALID_INPUT`입니다.

### `get_my_farm()` — S02/S03

```js
const { data, error } = await supabase.rpc('get_my_farm')
```

```json
[
  {
    "plot_id": "uuid",
    "plot_index": 1,
    "farm_status": "empty",
    "session_id": null,
    "session_status": null,
    "crop_id": null,
    "crop_name": null,
    "target_seconds": null
  }
]
```

- `plot_index` 오름차순
- 밭이 없으면 `[]`; 조회가 밭을 생성하지 않음
- `focusing | paused → growing`, `ripe → ripe`, `harvested → harvested`
- `seed_saved`는 밭을 점유하지 않아 `empty`
- 실시간 `focused_seconds`와 `remaining_seconds`는 B의 `get_active_focus()` 사용
- 저장된 세션 상태만 투영하며 완료·만료 상태를 확정하지 않음

### `get_focus_history(p_period)` — S14/S15/S15-1

```js
const { data, error } = await supabase.rpc('get_focus_history', {
  p_period: 'week', // today | week | all
})
```

```json
{
  "period": "week",
  "range": {
    "start_date": "2026-11-09",
    "end_date": "2026-11-15",
    "timezone": "Asia/Seoul"
  },
  "summary": {
    "focused_seconds": 0,
    "seed_count": 0,
    "harvest_count": null
  },
  "items": [
    {
      "record_date": "2026-11-09",
      "focused_seconds": 0,
      "seed_count": 0,
      "harvest_count": null
    }
  ],
  "capabilities": { "harvest_count": false }
}
```

- `today`: 오늘 한 항목, 기록이 없어도 0으로 반환
- `week`: 사용자 시간대의 월요일~일요일 7개 항목, 빈 날짜는 0
- `all`: 기록이 있는 날짜만 오름차순; 빈 기록이면 날짜 범위 `null`, 요약 0, `items = []`
- `seed_saved | ripe | harvested`만 집계; 활성 집중은 제외
- `focused_seconds = 0`인 씨앗도 `seed_count`에 포함
- 수확 스키마 전에는 `harvest_count`가 숫자가 아님

화면은 `capabilities.harvest_count === true`일 때만 수확 수를 숫자로 표시합니다. `false`이면 숨김 또는 “준비 중” 상태로 처리하며 0회 수확으로 해석하지 않습니다.

## 로그인·온보딩·농장 진입

1. `signUp()`에 nickname metadata를 포함합니다.
2. 가입 응답 세션을 확인합니다. 없으면 S18 로그인으로 이동합니다.
3. `get_my_profile()`로 프로필 트리거 결과를 확인합니다.
4. S01 입력 완료 후 B의 `ensure_farm()`을 호출합니다.
5. 응답에 1~12번 밭이 모두 있는지 확인합니다.
6. `complete_onboarding()`으로 최초 완료 시각을 확정합니다.
7. `get_my_farm()`을 호출하고 S02/S03으로 이동합니다.

`ensure_farm()` 성공 후 `complete_onboarding()`이 실패하면 4~6단계를 같은 순서로 다시 실행합니다. 두 RPC 모두 멱등적이라 밭이 12개를 넘어 증가하거나 최초 완료 시각이 바뀌지 않습니다. 두 호출은 단일 트랜잭션은 아닙니다.

## 로딩·빈 데이터·재시도

| 호출 | 로딩 | 빈 데이터 | 재시도 |
|---|---|---|---|
| `get_my_profile()` | 앱 진입 시 1회 | 정상 가입에서 빈 배열은 계약 위반으로 기록 | 네트워크 오류 1회 |
| `list_crops()` | 에너지 선택 변경마다 | 빈 배열이면 선택 비활성화 및 운영 오류 기록 | 네트워크 오류 1회; 이전 요청 결과 폐기 |
| `get_my_farm()` | 농장 진입·상태 변경 성공 후 | `[]`이면 `ensure_farm()` 복구 흐름 제안 | 네트워크 오류 1회 |
| `get_focus_history()` | 기간 탭 변경마다 | 계약에 맞춰 0 또는 빈 목록 표시 | 네트워크 오류 1회; 이전 요청 결과 폐기 |
| `complete_onboarding()` | 버튼 중복 입력 잠금 | 해당 없음 | 멱등 재시도 가능 |

자동 무한 재시도는 사용하지 않습니다. 탭·에너지 변경 중 이전 요청이 늦게 끝나면 최신 선택의 결과만 화면에 반영합니다.

## A/B 책임 경계

| A 조회·프로필 | B 쓰기·상태 전이 |
|---|---|
| 프로필 조회와 온보딩 완료 | `ensure_farm()`과 밭 생성 |
| 작물 목록·추천 | 집중 시작·일시정지·재개·중단 |
| 농장 상태 투영 | 씨앗 보관·수확·휴식·초기화 |
| 집중/씨앗 일별 기록 집계 | 자동 수확·Cron·수확 알림 |

A 조회 RPC는 밭을 만들거나 세션 상태를 변경하지 않습니다. 완료·만료 세션이 B에 의해 확정되기 전에는 농장과 기록 화면이 저장된 상태만 보여줍니다.

## 미확정 UI 계약

- 자동 수확 알림 ID와 확인 처리
- 기록 화면의 원시 세션·작물 상세 목록
- 수확 건수와 수동/자동 수확 날짜 귀속
- `all` 장기 기록 pagination 또는 기간 제한
- timezone 변경 시 기존 `record_date` 표시 정책
- S02/S03, S14/S15/S15-1 원본 화면의 필드·그룹·정렬

이 항목은 프론트에서 임시 필드로 고정하거나 기존 RPC 응답에 추측해 추가하지 않습니다.
