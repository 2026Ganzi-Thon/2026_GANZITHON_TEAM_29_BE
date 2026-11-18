# get_crop_history: 구현 전 권한 결정

상태: **승인됨** — 사용자 후속 지시로 아래 제한적인 RLS 예외가 확정되었다.
신규 구현·검증·배포의 최신 상태는 [최종 명세](crop-history.md)를 따른다.

추적: [Issue #31](https://github.com/2026Ganzi-Thon/2026_GANZITHON_TEAM_29_BE/issues/31).
작업 브랜치: `feat/a-crop-history` (별도 worktree, 기존 작업 폴더 보존).

## 목적과 확정 계약

S14/S15/S15-1의 작물별 기록을 위한 `public.get_crop_history(p_period text)`를 추가한다.
기존 `get_focus_history()`와 기존 마이그레이션은 변경하지 않는다.

- 입력: 필수 `today | week | all`; 사용자 ID는 `auth.uid()`로만 확인.
- 반환: JSONB 최상위 `period`, `summary`, `items`, `monthly`, `crop_totals` 5개.
- 확정 상태 `seed_saved`, `ripe`, `harvested`만 집중 시간에 포함.
- 실제 `harvests.session_id`로 수확 횟수 집계. 0초 씨앗도 보존.
- 날짜는 `record_date`, 오늘/이번 주는 `profiles.timezone`, 주간은 월~일 7일.
- 비활성 작물의 기존 기록, 실제 작물명, `sort_order` 정렬도 보존.
- 기존 기록 API와 동일 스냅샷의 summary가 일치해야 한다.
- authenticated만 EXECUTE 허용; anon/PUBLIC/service_role 차단; STABLE 및 빈 search_path.

## 확인한 충돌

2026-11-18 기준 develop `094d4d5025e345fa39384d0abb7a2bfdc1d435f5`.
로컬과 Staging `klanbfvywwudprunaqdf`의 `crops` SELECT 정책은
`crops_select_active`, authenticated, `USING (is_active)` 하나다.

기존 기록 API는 crops를 조인하지 않으므로 비활성 작물의 세션도 합산한다.
새 API를 SECURITY INVOKER로 구현하여 crops를 조인하면:

| 방식 | 실제 로컬 결과 | 계약 위반 |
| --- | --- | --- |
| 기존 get_focus_history('all') | focused_seconds=30, seed_count=1, harvest_count=0 | 없음 |
| sessions INNER JOIN crops | 0건, focused_seconds=0 | 과거 기록 유실, 기존 summary와 불일치 |
| sessions LEFT JOIN crops | 세션 유지, name/sort_order=NULL | 실제 작물명 및 정렬 계약 불충족 |

재현은 로컬 트랜잭션에서 임시 Auth 사용자/밭/30초 seed_saved 세션을 생성하고
해당 작물을 비활성화한 뒤 authenticated 역할로 조회했다. 전체 ROLLBACK 후 임시 사용자 0건.
Staging에서는 정책 및 마이그레이션 목록만 읽었고 쓰기 작업은 하지 않았다.

## 승인할 선택지

**권장: 본인 확정 기록에 등장하는 비활성 작물만 추가 조회 허용.**
신규 마이그레이션의 별도 SELECT 정책으로 기존 활성 카탈로그 조회를 유지하고,
본인 확정 세션이 참조하는 작물에 한해 비활성 행도 볼 수 있도록 한다.
새 RPC는 SECURITY INVOKER를 유지한다. 기존 정책/함수/병합 마이그레이션을 수정하지 않는다.

이는 기존 SELECT 가시성의 의도적인 확대다. 최초 지시의 ‘RLS 완화 금지’에 대해
사용자가 **본인 확정 기록이 참조하는 비활성 작물만** 예외로 승인했다.
신규 마이그레이션 `20261118132003_a_crop_history.sql`로 적용한다.
직접 crops 조회 및 기존 카탈로그 RPC에 미치는 영향도 회귀 검증한다.
특히 해당 사용자는 비활성 작물의 name/sort_order뿐 아니라 기존 SELECT 허용 열도 볼 수 있다.

대안은 신규 RPC의 제한적인 SECURITY DEFINER 설계다. 기존 테이블 정책은 유지되지만
함수 소유자 권한으로 읽으므로 별도 보안 승인이 필요하고, 기본 구현으로 채택하지 않았다.
작물명을 고정 UUID에 하드코딩하거나 기록을 누락시키는 우회는 하지 않는다.

## 승인 후 작업 순서

1. 공식 CLI로 새 마이그레이션 생성, 확정 권한 설계 및 CTE 기반 집계 구현.
2. 전용 pgTAP T01~T27, SDK 통합 테스트와 CI 단계 추가.
3. npm ci, 로컬 reset/test, integration/history/reset, lint, audit 실행.
4. 빈/소량/다량/다년/다른 사용자 다량 fixture의 실행 계획과 응답 크기 측정.
5. API 계약·프론트 인계·Notion 붙여넣기 명세 및 Cron 버전 가드 갱신.
6. PR/CI/병합 조건 검수 후 Staging dry-run에서 승인된 신규 버전만 확인하여 배포.
7. 임시 A/B 계정으로 원격 E2E 및 정확한 정리 검증 후 실제 상태로 문서 갱신.

S14의 씨앗/수확대기/수확완료별 집중 시간 분리는 현재 응답으로 불가능하다.
추가 필드나 페이지네이션은 이번 계약에 임의로 추가하지 않는다.

## 참고

정책 승인 전 2026-11-18 최초 기존 기능 회귀 검증: npm ci 성공, pgTAP 343/343 PASS,
Auth/RPC·History·Farm reset SDK 통합 PASS, DB lint 오류 없음, npm audit 취약점 0건.
이 최초 검증에서는 기존 로컬 DB를 reset하지 않고 당시 실행 중인 로컬 스택에서 검증했다.
정책 승인 후 신규 API·성능·원격 E2E까지 완료했다. 최신 결과는
[Staging 검증 보고서](../deployment/crop-history-staging-verification.md)를 따른다.

- [Supabase RLS 공식 문서](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase changelog](https://supabase.com/changelog.md)
- 기존 정책: `supabase/migrations/20261110152140_a_foundation.sql`
- 기존 집계: `supabase/migrations/20261115011444_a_focus_history_harvest_count.sql`
