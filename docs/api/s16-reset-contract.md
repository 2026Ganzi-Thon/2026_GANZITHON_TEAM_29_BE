# S16 기록 모두 지우기

상태: **Staging 배포·실제 SDK VERIFIED_REMOTE** (2026-11-18). [배포 및 검증 기록](../deployment/s16-staging-verification.md)을 참고하세요.

## API 명세 (Notion 추가용)

- 화면: S14 → S16 확인 → 성공 시 S02
- `reset_farm_history()`, POST `/rest/v1/rpc/reset_farm_history`, body `{}`
- 인증: 사용자 JWT, 입력 매개변수 없음, auth.uid() 소유권 확인
- HTTP 200: `{"success":true}`
- PT401 / UNAUTHENTICATED: 함수 본문 인증 컨텍스트 부재
- PT404 / NOT_FOUND: 본인 프로필 부재
- 익명·service_role: EXECUTE 차단, 42501 (익명 HTTP 401)
- 빈 상태 재호출은 성공하지만 **지연된 재요청은 새 기록도 삭제하므로 자동 재시도 금지**.

```js
const { data, error } = await supabase.rpc('reset_farm_history')
if (error) throw error
if (data?.success !== true) throw new Error('기록 초기화 실패')
```

보존: Auth·로그인 세션·회원 정보·닉네임·timezone·온보딩 완료 시각·plot ID/index·작물·Cron.

삭제: 본인 focus_sessions 모든 상태, 종속 harvests(메모·자동 알림·휴식 포함), 종속 stop previews/tokens, 본인 overwork_notices. 복구 불가입니다. profiles/farm_plots/crops는 삭제하지 않습니다. 농장 미초기화 사용자는 기존 ensure_farm으로 12칸을 생성하고 기존·확장 밭은 보존합니다.

## 잠금·원자성

프로필 FOR NO KEY UPDATE → ensure_farm → 세션 ID 순 FOR UPDATE → 과로 안내 삭제 → 세션 삭제와 FK CASCADE 순서입니다. start/finalize/harvest/rest/claim/worker와 프로필 선점 규칙을 공유합니다. worker는 잠긴 사용자를 SKIP LOCKED로 넘깁니다.

pause/resume은 세션부터 잠그고 프로필을 다시 잠그지 않으며 note는 수확 행을 갱신합니다. reset은 세션 다음 종속 행을 삭제하므로 이전 쓰기가 완료되거나 삭제 후 NOT_FOUND가 됩니다. 기존 B 함수 변경은 없습니다. 같은 사용자 start/reset 경쟁에서 새 세션이 먼저 생성돼 삭제되거나 reset 후 생성돼 남는 것은 모두 정상입니다.

오류면 과로 안내·종속 삭제도 모두 롤백합니다. 다른 사용자 삭제·TRUNCATE·계정 삭제·DELETE 권한 추가·RLS 완화는 없습니다.

## 프론트 흐름

1. S14에서 S16 확인 모달 표시. 취소·바깥 클릭은 API 없이 S14 복귀.
2. 확정 시 버튼 비활성화, 관련 요청·타이머 정리. 요청 세대 번호를 갱신해 삭제 전에 발행된 늦은 응답을 폐기합니다.
3. RPC 성공 후 농장·활성 세션·기록·알림 캐시 무효화.
4. get_my_farm → get_active_focus → get_focus_history(today/week/all) → 미확인 자동 알림 재조회 후 S02 이동.
5. 삭제 성공 후 조회만 실패하면 **조회만 재시도**. 응답 유실로 성공 여부가 불명확하면 자동 reset 재호출 없이 재조회·사용자 재확인을 거칩니다.
6. 로그아웃·온보딩 재진입·계정 재생성은 하지 않습니다.

초기화 후: 12개 empty/session_id=null, 활성 session=null, summary 3종 모두 0, capability.harvest_count=true. today 1일/week 7일 0 채우기, all 빈 items/null 날짜 범위, 알림 빈 배열입니다.

## 기획·검증

Figma metadata로 v1.0 `15:479`와 v1.2 `63:2192`를 직접 조회했습니다. v1.0의 onboarded 보존·S02 이동·취소 S14와 v1.2의 서버 삭제 문구를 확인했습니다. 회원·로그인·plot ID 보존은 이번 사용자 확정 정책을 따릅니다. UI 구현·시각 QA는 이번 범위가 아닙니다. Notion은 접근되지 않아 변경하지 않았으며 위 명세를 추가용으로 제공합니다.

신규 버전: `20261118052002_b_reset_farm_history.sql`. 기존 14개 수정 없음. Cron 가드만 정확한 15개 목록으로 갱신하고 나머지 가드는 유지합니다.

전용 pgTAP은 상태별 삭제·cascade·격리·보존·빈 집계·토큰·권한·실패 원자성을 검증합니다. `npm run test:reset`은 SDK 로그인·plot ID 보존과 reset/start/pause/resume/finalize/stop/harvest/note/rest/claim/worker 경쟁을 검증합니다. 예상 가능한 NOT_FOUND만 허용하고 deadlock 등 다른 오류는 실패합니다. 모든 스케줄링을 전수 증명하는 시험은 아닙니다.
