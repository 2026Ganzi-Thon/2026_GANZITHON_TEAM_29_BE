# Staging 실제 Auth 및 예약 수확 E2E 기록

검증일: 2026-11-15 (한국 시각). 대상: `focus-farm-staging`, `klanbfvywwudprunaqdf`, 서울, PostgreSQL 17.11. 상태 ACTIVE_HEALTHY.

기준 develop `76302083ceae695ecb36cec916e5e3615a7dc61b`, 배포 main `7471dddc028df1c87f2e33e93dbbae33b34b31f5`. 원격 이력은 14개, Job ID 1 / `focus-farm-auto-harvest-staging` / `* * * * *` / postgres / ACTIVE로 사전·사후 동일합니다.

## 방법과 보안

설치된 supabase-js 2.109.0과 실제 Staging URL·Publishable key를 사용했습니다. 고유 임시 이메일 2개와 무작위 비밀번호를 메모리에서 생성하고 가입 metadata에 실행 식별자를 넣었습니다. 비밀번호·access/refresh token·stop token은 로그나 문서에 출력하지 않았습니다. 원격 데이터 fixture와 삭제는 승인된 프로젝트의 CLI DB 연결로 실행했습니다.

기존 사용자는 0명이었습니다. 시간 조정은 정확한 session_id + user_id + 가입 metadata의 실행 식별자 세 조건으로 대상 행 한 개를 확인한 후 수행했습니다. 기존 사용자 데이터·마이그레이션·Cron 설정·B 함수는 변경하지 않았습니다.

## 실제 HTTP API 결과

| 호출 / 시나리오 | 결과 | 확인한 범위 |
|---|---|---|
| signUp | VERIFIED_REMOTE | 고유 계정 2개, nickname 프로필 트리거, Confirm email OFF 즉시 session |
| signInWithPassword | VERIFIED_REMOTE | 두 계정 모두 실제 로그인 |
| setSession/getSession/getUser | VERIFIED_REMOTE | 새 클라이언트에 세션 복원, 사용자 ID 일치, Auth HTTP로 사용자 확인 |
| signOut | VERIFIED_REMOTE | 모든 테스트 클라이언트 로그아웃 및 session=null |
| get_my_profile | VERIFIED_REMOTE | 각 계정 프로필 1개 반환 |
| ensure_farm | VERIFIED_REMOTE | 각 계정 밭 12개 |
| complete_onboarding | VERIFIED_REMOTE | 반복 호출 최초 시각 동일 |
| list_crops | VERIFIED_REMOTE | low 및 null 조회, 작물 6종 |
| get_my_farm | VERIFIED_REMOTE | 12개 반환, 자동 수확 후 해당 밭 empty/session_id=null |
| start_focus | VERIFIED_REMOTE | 본인 밭에서 새 집중 시작 및 수확 후 재사용 |
| get_active_focus | VERIFIED_REMOTE | 시작한 세션 ID 복원 |
| pause_focus/resume_focus | VERIFIED_REMOTE | paused/focusing 응답 |
| preview_stop_focus | VERIFIED_REMOTE | 미리보기 발급 및 새 미리보기 흐름 |
| cancel_stop_focus | VERIFIED_REMOTE | 취소 성공 |
| confirm_stop_focus | VERIFIED_REMOTE | seed_saved, 같은 토큰 재요청 동일 성공 |
| finalize_my_focus | VERIFIED_REMOTE | 테스트 소유 세션 시간 조정 후 ripe 확정 |
| get_focus_history | VERIFIED_REMOTE | today/week/all 씨앗 1개 및 capability=true, 수확 후 all 수확 수 2개 |
| harvest_crop | VERIFIED_REMOTE | 기한 전 수동 수확, auto_harvested=false, 재시도 동일 결과 |
| save_harvest_note | VERIFIED_REMOTE | 일반 메모 saved=true/guidance_required=false |
| start_rest | VERIFIED_REMOTE | 종료 시각 반환 및 재요청 시각 불변 |
| claim_overwork_notice | VERIFIED_REMOTE (false 분기) | 새 세션 자격 미달 정상 false. true/일별 경합은 VERIFIED_LOCAL_ONLY |
| 자동 알림 SELECT/ack | VERIFIED_REMOTE | 본인 미확인 목록, ack 1→재시도 0, 목록 제거 |

일반 메모 저장만 원격 호출했으며 guidance_required=true는 로컬 검증입니다. 모든 입력 오류·TTL·24시간·timezone·동시성 조합을 원격에서 전수검증한 의미는 아닙니다. 실제 브라우저 UI·스토리지 복원·CORS는 별도 프론트 환경에서 검증해야 합니다. 이번 세션 복원은 새 SDK 클라이언트의 setSession/getSession과 getUser로 확인했습니다.

## 두 계정 격리

- B 계정의 REST SELECT에서 A 계정 profiles/focus_sessions/harvests 행은 각각 빈 배열.
- B가 A 세션 pause 요청 → SESSION_NOT_FOUND.
- B가 A stop token confirm 요청 → STOP_TOKEN_NOT_FOUND.
- B가 A 수확 note 요청 → HARVEST_NOT_FOUND.
- B가 A 자동 알림 ack 요청 → AUTO_HARVEST_NOT_FOUND.
- 각 계정의 농장 조회는 12개. UUID를 입력한 타인 데이터 접근과 쓰기 RPC 거부를 실제 API로 검증했습니다.

## 실제 Cron 처리

관리자 `process_due_harvests()` 직접 호출은 이번 E2E에서 **0회**입니다. 테스트 계정의 새 집중 세션 started_at만 과거로 조정해 실제 finalize RPC로 ripe를 만들고, 해당 세션 auto_harvest_at만 과거로 설정했습니다. 그 뒤 SDK로 harvests를 조회하며 다음 예약 실행을 기다렸습니다.

| 예약 실행 | 실제 DB 이력 |
|---|---|
| Job | 1 / focus-farm-auto-harvest-staging |
| UTC 시작 | 2026-11-15 14:52:00.057285+00 |
| UTC 종료 | 2026-11-15 14:52:00.069431+00 |
| 한국 시각 | 2026-11-15 23:52 |
| 상태 | succeeded |
| return_message | 1 row (SQL 반환 행 수, 수확 건수 의미 아님) |

예약 직후 SDK 검증: session.status=harvested, harvests 정확히 1건, auto_harvested=true, 농장 해당 밭 empty, 미확인 알림 존재, ack 1건, 재ack 0건, 미확인 목록 빈 배열. 해당 세션 수확 행이 계속 1개임을 확인했습니다. 다른 수동 수확과 합쳐 기록 조회의 harvest_count=2를 확인했습니다.

이는 실제 예약 worker의 수확 성공 경로 검증이며 자연스럽게 실제 자정까지 기다린 시험은 아닙니다. 장기 반복 주기·Cron/수동 수확 동시 경합은 이번 원격 E2E에서 강제 재현하지 않았습니다.

## 정리 및 회귀

성공·실패 모두 finally 경로에서 테스트 클라이언트를 signOut하고 **정확한 임시 이메일 2개 및 실행 metadata가 일치하는 auth.users만 삭제**하도록 했습니다. FK cascade 이후 별도 관리자 조회로 다음을 확인했습니다.

| 항목 | 사후 잔여 |
|---|---:|
| auth.users / auth.sessions | 0 / 0 |
| profiles / farm_plots | 0 / 0 |
| focus_sessions / harvests | 0 / 0 |
| focus_stop_previews / overwork_notices | 0 / 0 |
| 마이그레이션 | 기존 14개 |
| Cron | 기존 Job 1개, ACTIVE, 1분, postgres |

로컬 npm ci, db:reset, db:test **303/303 PASS**, Auth/RPC 통합 PASS, History 통합 PASS, db:lint 오류 없음, npm audit 취약점 0. 업무·보안 코드와 기존 테스트는 수정하지 않았습니다. 이번 PR은 검증 결과 문서만 포함합니다.

프론트 연동은 [인계 문서](frontend-handoff.md)를 기준으로 시작할 수 있습니다. Notion 대조·브라우저 통합·과로 안내 true의 원격 경로·자연 자정 경계·운영 부하 시험은 남아 있습니다.
