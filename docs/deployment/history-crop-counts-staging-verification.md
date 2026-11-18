# 기록 API 성장·씨앗 집계 보강 — 배포 및 인계

검증일: 2026-11-18 Asia/Seoul. 상태: **VERIFIED_REMOTE**.
프로젝트: focus-farm-staging / `klanbfvywwudprunaqdf` / ap-northeast-2 / PostgreSQL 17.11.0.018.

## PR·코드·배포 이력

- [Issue #35](https://github.com/2026Ganzi-Thon/2026_GANZITHON_TEAM_29_BE/issues/35).
- [기능 PR #36](https://github.com/2026Ganzi-Thon/2026_GANZITHON_TEAM_29_BE/pull/36) MERGED.
  기능 HEAD `0e675ac13e9bad60b9ec8bc5d62b9993138edfb0`.
  [기능 CI SUCCESS](https://github.com/2026Ganzi-Thon/2026_GANZITHON_TEAM_29_BE/actions/runs/44319929048).
- develop 코드 통합 SHA `18f3045bb47cfa9d431d20628e78fe762a08f9df`에서 전체 로컬 회귀 재검증 PASS.
- [release PR #37](https://github.com/2026Ganzi-Thon/2026_GANZITHON_TEAM_29_BE/pull/37) MERGED.
  [release CI SUCCESS](https://github.com/2026Ganzi-Thon/2026_GANZITHON_TEAM_29_BE/actions/runs/44320343216).
- main / 실제 배포 SHA `743c88a50fc2d31201a573b6d5ea592ff8e9ddbb`.
- 원격 검증 완료 후 별도 문서 PR로 develop에 인계한다. 최종 문서 병합 후 develop SHA는 위 코드 통합 SHA와 다를 수 있다.

기존 작업 폴더·브랜치는 보존하고 별도 worktree/`codex/history-crop-counts`에서 개발했다.
main/develop 직접 push, force push, 원격 reset, Production 접근은 하지 않았다.

## 신규 마이그레이션 1개

CLI 3.1.0 --help 확인 후 migration new로 `20261118135436_a_history_crop_counts.sql` 생성.
기존 16개 마이그레이션은 수정하지 않았다. 신규 SQL은 두 함수의 CREATE OR REPLACE와 COMMENT뿐이다.
RLS/GRANT/B 도메인/Cron 객체 변경은 없다. Cron 운영 SQL의 정확 버전 가드에 17번째 버전만 추가했다.

main 배포 커밋에서 실제 실행:

```text
npx supabase db push --remote=klanbfvywwudprunaqdf --dry-run --skip-vault
Would push these migrations:
 • 20261118135436_a_history_crop_counts.sql

npx supabase db push --remote=klanbfvywwudprunaqdf --skip-vault --yes
Applying migration 20261118135436_a_history_crop_counts.sql...
```

기존 16 → **17개**, 최신 `20261118135436`. role/seed/Vault 적용 없음.
CLI의 production은 이 Supabase 프로젝트 기본 브랜치 표기이며, 실제 대상 이름·Ref는 승인된 STAGING이다.
기존 get_focus_history/get_crop_history의 owner/ACL/입력/반환 타입·설정과
전체 기존 RLS/테이블 ACL·RLS 활성화 상태/다른 public·private 함수/Cron Job을 배포 전후 비교해 동일함을 확인했다.
두 함수는 STABLE/SECURITY INVOKER/search_path=''/UTC, authenticated만 허용, anon/service_role 불허다.
CREATE OR REPLACE의 기존 owner/권한 유지 동작은 [PostgreSQL 공식 문서](https://www.postgresql.org/docs/17/sql-createfunction.html) 및 실제 카탈로그로 검증했다.

## 실제 테스트 결과

| 범위 | 결과 | 검증 상태 |
| --- | --- | --- |
| pgTAP | **454/454 PASS** = 기존 419 + 신규 35 | VERIFIED_LOCAL_ONLY |
| npm ci / 로컬 DB reset | PASS | VERIFIED_LOCAL_ONLY |
| 기존 Auth/RPC·History·reset SDK | PASS | VERIFIED_LOCAL_ONLY |
| Crop SDK, 두 API 기간별 호출/일별 crop 일치 | 로컬·원격 PASS | VERIFIED_REMOTE |
| 이전 두 함수의 전체 JSON 보존 비교 | today/week/all 모두 PASS | VERIFIED_LOCAL_ONLY |
| 사용자 격리·0초·비활성 RLS·초기화·읽기 불변 | 로컬·원격 PASS | VERIFIED_REMOTE |
| 익명 차단 | 두 API 각각 실제 HTTP 401/42501 | VERIFIED_REMOTE |
| 잘못된 기간 | 실제 SDK HTTP400/22023, 기존 오류 유지 | VERIFIED_REMOTE |
| DB lint | 로컬·원격 오류 없음 | VERIFIED_REMOTE |
| npm audit | 취약점 0 | VERIFIED_LOCAL_ONLY |

기존 pgTAP은 전체 객체 기대값 한 곳에 승인된 grown_count/seed_count만 반영했다.
이전 SDK History 전체 객체 기대값에는 crops만 추가했고 기존 필드 값 검증을 유지했다.
새 SDK 로컬 호환성 시험은 변경하지 않은 이전 SQL 정의 두 개를 pg_temp에서 실행하고,
새 응답에서 승인된 추가 필드만 제거한 뒤 구버전 전체 응답과 deepEqual로 비교한다.
임시 함수/권한은 같은 트랜잭션에서 ROLLBACK하며 이 시험 DDL은 원격에서 실행하지 않았다.

신규 35개 pgTAP과 SDK가 today/week/all, ripe/harvested grown, seed_saved seed,
ripe의 실제 수확 제외, 수동·자동 실제 수확, 같은 작물 합산, focusing/paused 제외,
비활성 기록·정렬·빈 날짜·주간 7일·월별·격리·기존 필드 보존·두 API 일별 일치·초기화·STABLE/권한을 검증한다.
기존 before/after 세션·수확 스냅샷도 동일해 읽기 API의 데이터 변경 부작용이 없었다.

## 실제 응답과 프론트 계약

[전체 6개 실제 응답 JSON](../api/history-crop-counts-examples.json): 두 API × today/week/all.
[최종 호출·필드·오류 명세](../api/history-crop-counts.md).

실제 get_focus_history('today')의 items 항목:

```json
{
  "record_date": "2026-11-18",
  "focused_seconds": 150,
  "seed_count": 2,
  "harvest_count": 3,
  "crops": [
    {"crop_id":"10000000-0000-4000-8000-000000000001","crop_name":"새싹채소","focused_seconds":0,"grown_count":0,"seed_count":1},
    {"crop_id":"10000000-0000-4000-8000-000000000002","crop_name":"당근","focused_seconds":150,"grown_count":4,"seed_count":1}
  ]
}
```

get_crop_history('today')의 당근 객체는 위 값에 기존 `harvest_count:3`도 포함한다.
즉 grown_count=4(ripe 1 + harvested 3), seed_count=1, 실제 harvest_count=3이다.
harvested지만 harvest 행이 없는 별도 fixture도 grown에는 1, 실제 harvest에는 0으로 집계했다.
all의 월별·누적 객체에도 grown/seed가 동일한 규칙으로 합산된다.
focused_seconds는 씨앗/성장 완료 시간을 합친 값이며, 상태별 시간 필드는 추가하지 않았다.

## 원격 Auth·정리·운영 확인

실제 Supabase Auth HTTP로 고유 임시 계정 2개를 가입·로그인하고 getSession을 확인했다.
Confirm email OFF로 가입 즉시 세션이 발급됐고 기존 Auth 정책은 변경하지 않았다.
해당 계정의 fixture만 만들었으며 실제 사용자 데이터/기존 6개 작물은 수정하지 않았다.
추가 비활성 RLS 시험에는 시험 전용 비활성 작물 5개만 사용했다.
signOut 후 UUID/email/run metadata로 계정을 특정해 삭제하고,
시험 작물은 UUID+이름+비활성 조건으로만 제거했다. 계정별 users/profiles/plots/sessions 잔여 0,
시험 작물 잔여 0을 확인했다. 수확 행은 세션 FK CASCADE로 정리된다.
최종 재조회에서도 시험 run 계정 0, 시험 작물 0, 기존 활성 작물 6종을 확인했다.
원격 전체 사용자/업무 데이터가 0이어야 한다고 가정하지 않았다.

Cron Job ID 1, ACTIVE, `* * * * *`, 기존 command/owner/database 모두 그대로다.
Job 삭제·재등록·변경 또는 관리 함수 직접 실행을 하지 않았다. 이번 작업에서 예약 수확 E2E를 재실행했다고 주장하지 않는다.

Security Advisor는 기존 INFO 2, anon definer WARN 1, authenticated definer WARN 17,
[유출 비밀번호 방어 WARN 1](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)을 유지했다.
Performance Advisor도 기존 FK 인덱스 INFO 2와 [permissive 정책 WARN 1](https://supabase.com/docs/guides/database/database-linter?lint=0006_multiple_permissive_policies) 그대로이며 새 경고는 없다.
이번 범위 밖의 권한/Auth 설정을 임의로 바꾸지 않았다.

## 변경 범위 및 남은 한계

신규 migration/전용 pgTAP, 승인된 기존 JSON 기대값, 두 SDK, Cron 운영 버전 가드,
API 명세·실제 응답 JSON·프론트 인계·이 보고서만 변경했다. 의존성/새 기술 스택 추가는 없다.
로컬 benchmark는 1만 세션/1,825일/61개월 + 타 사용자 10만 세션에서 16.145ms,
JSON 465,843 bytes였다. 단일 로컬 수치이며 운영 부하/네트워크 지연 검증은 아니다.

- seed_focused_seconds/grown_focused_seconds: **PENDING 별도 합의**, 이번 응답에 없음.
- all 페이지네이션/프론트 UI E2E: **PENDING**, 임의 필드 추가나 데이터 절단 없음.
- Discord/카카오톡 실제 메시지 발송은 하지 않음. 명세 하단에 복사 가능한 공유 메시지를 제공한다.
