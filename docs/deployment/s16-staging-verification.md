# S16 Staging 배포·원격 E2E 기록

검증일: 2026-11-18 (Asia/Seoul). 대상: focus-farm-staging / klanbfvywwudprunaqdf / 서울 / PostgreSQL 17.11. **S16 배포 및 실제 SDK 검증 VERIFIED_REMOTE**.

## 코드와 배포

- 구현 PR #28, 커밋 `674347f1629cdd1894d301ed77aedd531d842a9b`, develop 병합 `e4876e791c3454ae8d8aa75a64c52511c29670c3`.
- main 승격 PR #29, 배포 main `5cc72ca035d41c359dae9ffd04f441e64df29030`.
- 기존 main과 develop 차이는 앞서 검수한 인계·Cron·원격 E2E 문서/운영 SQL과 이번 S16 코드·시험뿐이었습니다. 기존 B RPC 및 마이그레이션 내용 변경 없음.
- CLI 3.1.0의 link, migration list, db push help 확인 후 정확한 프로젝트 연결.
- 배포 전 원격 이력 14개. dry-run 대상은 `20261118052002_b_reset_farm_history.sql` 하나이며 seed/role/Vault 변경 없음.
- `npx supabase db push --skip-vault --remote --yes` 성공. 원격 이력 15개, local/remote 버전 전부 일치. 배포 후 dry-run 적용 예정 0개.
- 갱신된 Staging 운영 SQL을 실제 재실행해 정확한 15개 이력 가드 통과 확인. Cron Job ID 1·이름·주기·postgres·ACTIVE 유지. Job 삭제·중복 등록 없음.

## 로컬 회귀와 동시성

기존 303개를 유지하고 reset pgTAP 40개 추가, **343/343 PASS**. npm ci, 로컬 db:reset, 기존 Auth/RPC·History 통합, 신규 `test:reset`, DB lint, npm audit(취약점 0), 로컬 DB advisor(이슈 없음) 통과. CI에 test:reset 단계만 추가하고 기존 검증은 모두 유지했습니다.

pgTAP은 focusing/paused/ripe/harvested/seed_saved, 수확의 메모·알림·휴식, stop token, overwork 삭제와 프로필·Auth·밭 ID·작물·타인 데이터 보존을 검증합니다. 강제 DELETE 실패 trigger를 테스트 트랜잭션에만 넣어 앞서 삭제한 과로 기록도 롤백되는 것을 확인했습니다. 익명·service_role 실제 실행 거부, PUBLIC 권한 없음, 인증 컨텍스트/프로필 부재 오류, 기존 DELETE 직접 권한 없음도 검증했습니다.

SDK Promise.all 경쟁: reset/reset, start, pause, resume, finalize, confirm stop, harvest, note, rest, claim. 별도 DB 연결 worker/reset 경쟁도 통과했습니다. 실행 순서에 따른 정상 성공·NOT_FOUND만 허용하고 deadlock·기타 오류는 실패로 처리합니다. 모든 가능한 잠금 스케줄을 증명하는 전수 시험은 아닙니다.

## 실제 원격 SDK 검증

실제 supabase-js 2.109.0으로 고유 임시 계정 A/B를 회원가입·로그인했습니다. 비밀번호·JWT·refresh/stop token은 로그에 출력하지 않았습니다. 관리자 fixture는 정확한 user_id/session_id와 이번 실행 metadata가 일치하는 테스트 행만 갱신했습니다.

각 계정은 12칸·온보딩·수확·메모·휴식을 만들었습니다. B에는 별도 paused 활동을 남겨 전체 프로필/밭/세션/수확 응답 스냅샷을 저장했습니다. A에는 씨앗·수확 대기·진행 중/일시정지·유효 stop preview·과로 보조 기록을 만들었습니다.

| 검증 | 실제 결과 |
|---|---|
| reset POST 성공 | 정확히 `{success:true}` |
| 계정·로그인 유지 | 같은 access token, getUser 동일 사용자 |
| 프로필·온보딩 유지 | nickname/timezone/onboarded/onboarded_at 응답 동일 |
| 농장 유지 | 동일한 plot ID/index 12개 |
| 활동 초기화 | 세션·수확·메모·휴식·알림·preview·overwork 없음 |
| 조회 | 농장 empty/session_id=null, 활성 session=null |
| 통계 | today/week/all 3종 합계 0, capability=true; 1/7/0 항목 규칙 유지 |
| 이전 token | confirm → STOP_TOKEN_NOT_FOUND |
| 타 사용자 | B 전체 스냅샷이 초기화 전후 동일 |
| 이후 사용 | A 같은 밭 start_focus 성공, 다시 reset 성공, 빈 재호출 성공 |
| 익명 | 원격 HTTP 401 / SQLSTATE 42501 |

## 실제 Cron 후 복원되지 않음

A의 ripe 세션 수확 기한만 테스트용 과거로 조정하고 A reset을 호출했습니다. 관리자 worker를 직접 호출하지 않고 reset 이후의 **실제 예약 실행**을 기다렸습니다.

- Cron Job ID 1, `focus-farm-auto-harvest-staging`
- UTC 시작 `2026-11-18 05:32:00.057532+00`
- UTC 종료 `2026-11-18 05:32:00.064452+00`
- 한국 시각 14:32, `succeeded`
- 이후 A 모든 조회가 계속 빈 상태, B 스냅샷 보존.

기존 Cron 1분·postgres·100명 배치·수확 로직은 변경하지 않았습니다.

## 정리와 보안

finally에서 테스트 클라이언트 signOut 후 **이번 실행의 정확한 이메일 2개 및 metadata가 일치하는 계정만 삭제**했습니다. 해당 ID의 profile/plots/sessions/previews/notices가 0임을 확인했습니다. FK CASCADE로 수확·메모·휴식도 함께 제거됩니다. 이번 배포 직전 기존 사용자 수는 실제 조회상 0이었지만 이를 삭제 조건으로 사용하지 않았습니다.

별도 원격 조회에서도 auth.users/auth.sessions/profiles/farm_plots/focus_sessions/harvests/private previews/overwork 모두 0건을 확인했습니다. 기존 사용자 전역 삭제·TRUNCATE·원격 reset은 실행하지 않았습니다.

새 RPC는 SECURITY DEFINER, 빈 search_path, 인자 없음/JSONB이며 authenticated=true, anon/service_role=false입니다. RLS·기존 권한은 유지되고 원격 DB lint 오류 없음. Security Advisor는 기존 private 정책 없음 INFO 2개·기존 플랫폼 익명 definer WARN 1개를 유지하며, authenticated definer WARN은 reset 추가로 16→17입니다. 의도된 소유권 검사 쓰기 RPC 경고이며 경고 0으로 보고하지 않습니다.

## 프론트 전달

[S16 API 명세](../api/s16-reset-contract.md)와 [전체 인계](frontend-handoff.md)를 사용하세요. S16에서만 삭제를 확정하고 버튼·요청·타이머를 잠급니다. 성공 후 캐시 무효화 → 농장/활성 세션/기록/자동 알림 재조회 → S02 이동. 로그인·온보딩은 유지합니다. 이전 요청의 늦은 응답을 폐기하고, 네트워크 오류에 reset을 자동 재시도하지 않습니다. 성공 후 재조회 실패는 조회만 재시도합니다.

### Discord 공유문

S16 기록 모두 지우기가 Staging에 배포됐습니다. 로그인 상태에서 `supabase.rpc('reset_farm_history')`를 호출하면 `{success:true}`를 반환합니다. 계정·닉네임·timezone·온보딩·기존 12칸 ID는 유지하고 진행 중 집중을 포함한 모든 활동·수확·메모·휴식·알림·stop token·과로 안내 기록을 삭제합니다. 취소는 API 호출 없이 S14, 성공은 캐시 무효화와 재조회 후 S02입니다. 파괴적 API이므로 자동 재시도하지 마세요. 실제 SDK·계정 격리·Cron 후 잔존 없음과 343개 DB 회귀/통합 테스트를 확인했고 임시 계정은 정리했습니다. 상세 요청·오류·재조회 계약은 `docs/api/s16-reset-contract.md`를 참고해주세요.

미검증: 실제 프론트 UI·브라우저 CORS·요청 취소/캐시 세대 처리, 자연 자정·대량 사용자 부하·모든 동시성 순서. Notion은 접근되지 않아 문서를 직접 수정하지 않았으며 S16 명세를 추가용으로 제공했습니다.
