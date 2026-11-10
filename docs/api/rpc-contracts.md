# RPC 계약

이 문서는 확정된 함수명과 입력 규칙만 고정합니다. 반환 타입, 상세 필드, 미제공 입력 타입과 공통 오류 코드 목록은 합의 전까지 `TBD`입니다.

## 공통 규칙

- RPC 함수명은 `snake_case`를 사용합니다.
- 입력 매개변수는 `p_` 접두사를 사용합니다.
- 사용자 ID는 입력받지 않고 Supabase 인증 컨텍스트에서 확인합니다.
- 집중 시간은 초 단위입니다.
- 시각은 UTC로 저장합니다.
- 기록 날짜와 자동 수확 판정은 사용자 시간대를 기준으로 합니다.
- 세션당 수확은 한 번만 허용합니다.
- 공통 오류 코드 목록과 응답 형태는 `TBD`이며, 확정 후 모든 RPC가 동일하게 유지합니다.
- 아래 함수명과 입력 매개변수는 별도 계약 변경 없이 수정하지 않습니다.

## 인증

인증은 RPC가 아니라 Supabase Auth SDK를 사용합니다.

| 작업 | SDK 메서드 |
|---|---|
| 회원가입 | `signUp` |
| 로그인 | `signInWithPassword` |
| 세션 조회 | `getSession` |
| 로그아웃 | `signOut` |

이메일 확인 여부, 프로필 자동 생성 시점, redirect URL 및 상세 오류 매핑은 `TBD`입니다.

## A 담당 RPC

| 함수 | 입력 | 반환 | 설명 |
|---|---|---|---|
| `get_my_profile()` | 없음 | `TBD` | 인증 사용자의 프로필 조회 |
| `complete_onboarding()` | 없음 | `TBD` | 온보딩 완료 처리. 상세 필드 규칙은 `TBD` |
| `list_crops(p_energy)` | `p_energy`: 타입/허용 범위 `TBD` | `TBD` | 에너지 조건에 맞는 작물 목록 조회 |
| `get_my_farm()` | 없음 | `TBD` | 인증 사용자의 농장 상태 조회 |
| `get_focus_history(p_period)` | `p_period`: 타입/허용 값 `TBD` | `TBD` | 사용자 시간대 기준 집중 기록 조회 |

## B 담당 RPC

| 함수 | 입력 | 반환 | 설명 |
|---|---|---|---|
| `ensure_farm()` | 없음 | `TBD` | 사용자 농장 보장 |
| `start_focus(p_plot_id, p_crop_id)` | 두 ID의 타입 `TBD` | `TBD` | 집중 세션 시작 |
| `get_active_focus()` | 없음 | `TBD` | 활성 집중 세션 조회 |
| `pause_focus(p_session_id)` | ID 타입 `TBD` | `TBD` | 집중 일시정지 |
| `resume_focus(p_session_id)` | ID 타입 `TBD` | `TBD` | 집중 재개 |
| `preview_stop_focus(p_session_id)` | ID 타입 `TBD` | `TBD` | 집중 중단 결과 미리보기 |
| `confirm_stop_focus(p_stop_token)` | 토큰 타입/만료 규칙 `TBD` | `TBD` | 미리보기 토큰으로 집중 중단 확정 |
| `harvest_crop(p_session_id)` | ID 타입 `TBD` | `TBD` | 세션당 한 번만 수확 |
| `process_due_harvests()` | 없음 | `TBD` | 자동 수확 대상 처리 |
| `ack_auto_harvest_notice(p_harvest_ids)` | ID 배열 타입 `TBD` | `TBD` | 자동 수확 알림 확인 |
| `save_harvest_note(p_harvest_id, p_note)` | ID/메모 제약 `TBD` | `TBD` | 수확 메모 저장 |
| `start_rest(p_harvest_id)` | ID 타입 `TBD` | `TBD` | 수확 후 휴식 시작 |
| `reset_farm_history()` | 없음 | `TBD` | 기록 초기화. 삭제/보존 범위 `TBD` |

## 상태

확정 상태 값은 다음과 같습니다.

- `focusing`
- `paused`
- `seed_saved`
- `ripe`
- `harvested`

각 상태가 적용되는 엔터티, 허용 전이, 종료 상태 및 실패 시 롤백 규칙은 `TBD`입니다.

## 계약 변경 절차

함수명, 입력명 또는 공통 규칙 변경은 프론트엔드와 A/B 백엔드 담당자 합의가 필요합니다. 변경 PR에는 호환성 영향과 마이그레이션 방법을 기록합니다.
