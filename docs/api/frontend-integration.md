# A 담당 프론트엔드 연동 가이드

프론트엔드는 브라우저용 Supabase Project URL과 publishable key만 사용합니다. Secret key, DB 비밀번호, 배포 토큰은 브라우저 번들에 넣지 않습니다. S 화면 원본은 저장소에서 확인하지 못했으므로 화면 매핑은 팀이 제공한 번호만 사용하며 UI 전용 필드를 DB 계약으로 만들지 않습니다.

## 공통 오류 처리

RPC 오류는 `message`보다 `code`를 먼저 확인합니다. 세션 없는 `42501`, `PT401`, `PGRST301`은 `UNAUTHENTICATED`, `PT404`는 `NOT_FOUND`, `22023`은 `INVALID_INPUT`으로 정규화합니다. 세션이 있는데 발생한 `42501`은 사용자 입력 오류가 아니라 권한 배포 오류로 기록합니다. B 집중 RPC의 `PT409`는 `details` 식별자를 사용합니다.

네트워크 오류의 조회 요청은 한 번 재시도할 수 있습니다. 인증·변경 요청은 결과를 확인하지 않은 채 반복하지 않습니다. `ensure_farm()`과 `complete_onboarding()`은 서버 멱등성이 보장되므로 실패 복구 시 같은 순서를 다시 실행할 수 있습니다.

## Auth SDK 4개

| 화면 | 함수 | 입력 | 성공 시 사용 | 재시도 |
|---|---|---|---|---|
| S19 | `signUp()` | `email`, `password`, `options.data.nickname` | Confirm email OFF 환경에서는 `user`와 `session` 확인 | 불명확한 네트워크 실패 후 먼저 `getSession()` 또는 로그인 확인 |
| S18 | `signInWithPassword()` | `email`, `password` | `session.access_token`, `user` | 자격 증명 오류 자동 재시도 금지 |
| 앱 시작 | `getSession()` | 없음 | 로컬 세션 복원; 서버 권한은 RPC/RLS가 최종 확인 | 1회 로딩 후 로그인 화면 분기 |
| 로그아웃 | `signOut()` | 없음 | 로컬 세션 제거 | 실패 표시 후 사용자가 재시도 |

```js
await supabase.auth.signUp({ email, password, options: { data: { nickname } } })
await supabase.auth.signInWithPassword({ email, password })
await supabase.auth.getSession()
await supabase.auth.signOut()
```

Confirm email OFF는 Staging Dashboard 정책입니다. 로컬/Production에서도 환경별 설정을 별도로 확인해야 합니다.

## A RPC 5개

| 화면 | RPC | 입력 | 성공 응답 | 로딩 정책 |
|---|---|---|---|---|
| S01 | `get_my_profile()` | 없음 | `[{ nickname, timezone, onboarded, onboarded_at }]` | 세션 복원 후 1회 |
| S01 | `complete_onboarding()` | 없음 | 최초 완료 시각 문자열 | `ensure_farm()` 성공 후 호출 |
| S04/S05 | `list_crops(p_energy)` | `low | medium | high | null` | `[{ crop_id, name, target_seconds, recommended, sort_order }]` | 에너지 선택 때 호출; 변경 시 이전 요청 결과 폐기 |
| S02/S03 | `get_my_farm()` | 없음 | 밭 행 배열 | 화면 진입·상태 변경 성공 후 재조회 |
| S14/S15/S15-1 | `get_focus_history(p_period)` | `today | week | all` | 기간·요약·일별 항목 JSON | 탭 변경 때 호출; 이전 요청 결과 폐기 |

```js
const profile = await supabase.rpc('get_my_profile')
const crops = await supabase.rpc('list_crops', { p_energy: 'medium' })
const farm = await supabase.rpc('get_my_farm')
const history = await supabase.rpc('get_focus_history', { p_period: 'week' })
```

`get_my_farm()`은 PR #7 기준으로 다음 행을 `plot_index` 오름차순 반환합니다.

```json
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
```

밭이 없으면 `[]`이며 조회가 밭을 생성하지 않습니다. 생성은 B의 `ensure_farm()`만 담당합니다.

`get_focus_history()`의 수확 필드는 스키마가 생기기 전까지 `null`입니다. 화면은 `capabilities.harvest_count === true`일 때만 수확 수를 숫자로 표시합니다.

## 회원가입부터 농장 진입

1. `signUp()`에 nickname metadata를 포함합니다.
2. 세션을 확인합니다. Confirm email OFF 환경에서는 가입 응답 세션을 사용하고, 없으면 로그인 화면으로 이동합니다.
3. `get_my_profile()`로 트리거가 만든 프로필을 확인합니다.
4. S01 입력이 완료되면 B의 `ensure_farm()`을 호출해 1~12번 밭을 확인합니다.
5. 성공하면 `complete_onboarding()`을 호출해 온보딩 완료 시각을 확정합니다.
6. `get_my_farm()`을 호출하고 S02/S03으로 이동합니다.

`ensure_farm()` 성공 후 `complete_onboarding()`이 실패하면 같은 4~5단계를 재시도합니다. 반대로 완료 응답을 받았지만 화면 전환이 실패해도 전체 순서를 다시 실행할 수 있습니다. 두 RPC 모두 기존 ID/최초 시각을 유지합니다. 다만 두 호출은 하나의 DB 트랜잭션이 아니며, 원자성이 필요하다는 제품 결정이 생기면 A/B 공동 RPC를 별도 설계합니다.

## 기록 조회 계약

```json
{
  "period": "week",
  "range": { "start_date": "2026-11-09", "end_date": "2026-11-15", "timezone": "Asia/Seoul" },
  "summary": { "focused_seconds": 0, "seed_count": 0, "harvest_count": null },
  "items": [
    { "record_date": "2026-11-09", "focused_seconds": 0, "seed_count": 0, "harvest_count": null }
  ],
  "capabilities": { "harvest_count": false }
}
```

`today`와 `week`는 빈 날짜도 0으로 표시하며, `all`은 기록이 있는 날짜만 반환합니다. 현재 응답은 일별 합계이므로 원시 세션·작물 상세 UI가 필요하면 기존 계약에 필드를 임의 추가하지 말고 별도 계약을 확정합니다.
