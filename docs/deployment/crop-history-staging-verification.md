# get_crop_history Staging 배포 및 최종 인계

검증일: 2026-11-18 (Asia/Seoul). 최종 API 상태: **VERIFIED_REMOTE**.
대상은 focus-farm-staging / `klanbfvywwudprunaqdf` / ap-northeast-2 / PostgreSQL 17.11.0.018.
Production 및 타 프로젝트에 접근하지 않았다.

## 코드 및 CI 이력

- [Issue #31](https://github.com/2026Ganzi-Thon/2026_GANZITHON_TEAM_29_BE/issues/31): 제한적인 RLS 예외를 사용자 승인으로 확정.
- [기능 PR #32](https://github.com/2026Ganzi-Thon/2026_GANZITHON_TEAM_29_BE/pull/32): MERGED.
  - 기능 HEAD `95b0391ea46390b0908a5f6a707e0dc4bd7346c4`.
  - develop 코드 통합 SHA `a20f53cb42603e6428fe180f73d000e08cd21b6d`.
  - [기능 CI 성공](https://github.com/2026Ganzi-Thon/2026_GANZITHON_TEAM_29_BE/actions/runs/44314831822).
- [병합된 develop CI 성공](https://github.com/2026Ganzi-Thon/2026_GANZITHON_TEAM_29_BE/actions/runs/44315282640).
- [release PR #33](https://github.com/2026Ganzi-Thon/2026_GANZITHON_TEAM_29_BE/pull/33): MERGED.
  - [release CI 성공](https://github.com/2026Ganzi-Thon/2026_GANZITHON_TEAM_29_BE/actions/runs/44315252397).
  - main 및 실제 배포 SHA `5e06f34bf3e5ba3e7d6d08c5b3f46437da343ebf`.
- 원격 검증 후 인계 문서는 별도 문서 PR로 develop에 반영한다.
  문서 병합 이후 develop HEAD는 위 코드 통합 SHA와 달라질 수 있다.

main/develop 직접 push 및 force push는 사용하지 않았다. 기능 브랜치와 기존 로컬 작업은 보존했다.

## 마이그레이션과 권한

Supabase CLI 3.1.0의 --help를 확인하고 공식 migration new로
`20261118132003_a_crop_history.sql`을 생성했다. 기존 15개 SQL과 get_focus_history 코드는 변경하지 않았다.
main 배포 커밋에서 실행한 실제 dry-run:

```text
npx supabase db push --remote=klanbfvywwudprunaqdf --dry-run --skip-vault
DRY RUN: migrations will *not* be pushed to the database.
Would push these migrations:
 • 20261118132003_a_crop_history.sql
```

사용자가 승인한 배포 범위에 따라 다음 명령으로 위 1개만 적용했다.

```text
npx supabase db push --remote=klanbfvywwudprunaqdf --skip-vault --yes
Applying migration 20261118132003_a_crop_history.sql...
```

적용 후 원격 이력은 **16개**, 최신 버전은 `20261118132003`이다.
CLI의 `production` 표기는 해당 Supabase 프로젝트의 기본 브랜치 구분이다.
이 작업의 팀 환경은 명시적으로 STAGING이며 이름·Ref·리전·버전을 별도로 재확인했다.

신규 함수: STABLE, SECURITY INVOKER, search_path='', UTC.
ACL은 postgres와 authenticated EXECUTE만 존재한다. anon/PUBLIC/service_role 실행은 불허한다.
기존 crops_select_active 유지 + 본인 seed_saved/ripe/harvested 기록의 비활성 작물 SELECT만 추가했다.
테이블 GRANT/열은 유지하고 쓰기 권한은 늘리지 않았다.

기존 public/private 함수 정의 및 실행 ACL 집계, crops 테이블 ACL, 신규 정책을 제외한 기존 RLS,
Cron Job 전체 설정의 배포 전후 해시/JSON을 비교해 모두 동일함을 확인했다.
Cron Job ID 1은 `* * * * *`, ACTIVE, 기존 process_due_harvests 명령 그대로다.
Cron 버전 가드 파일은 16개 목록만 반영했고 원격에서 재등록·변경·직접 수확 실행은 하지 않았다.

## 실제 QA 결과

| 범위 | 결과 | 검증 상태 |
| --- | --- | --- |
| 기존 pgTAP 343 + 신규 76 | **419/419 PASS**, 기존 테스트 삭제/변경 없음 | VERIFIED_LOCAL_ONLY |
| npm ci, 로컬 DB reset | PASS | VERIFIED_LOCAL_ONLY |
| 기존 Auth/RPC·History·Farm reset SDK | PASS | VERIFIED_LOCAL_ONLY |
| 신규 Crop history SDK | 로컬 및 Staging PASS | VERIFIED_REMOTE |
| DB lint | 로컬·원격 모두 오류 없음 | VERIFIED_REMOTE |
| npm audit | 취약점 0 | VERIFIED_LOCAL_ONLY |
| JSON 타입/정렬/0 채움/일·월·작물 합계/동일 스냅샷 parity | PASS | 로컬 pgTAP + 원격 SDK |
| 누락 프로필, JWT 없는 authenticated, service_role 실제 SQL 실행 거부 | PASS | VERIFIED_LOCAL_ONLY |
| service_role EXECUTE 없음 | 원격 카탈로그 확인 | VERIFIED_REMOTE |
| 성능/EXPLAIN/응답 크기 | [상세 측정](../api/crop-history.md#qa-및-성능) | VERIFIED_LOCAL_ONLY |

원격 SDK는 실제 signUp → signInWithPassword → getSession → RPC → signOut을 수행했다.
Confirm email OFF로 가입 즉시 세션이 발급됐다. Auth 운영 정책은 변경하지 않았다.
today/week/all 실제 응답은 [전체 JSON](../api/crop-history-examples.json)에서 확인할 수 있다.

| 기간 | 집중 초 | 수확 | 씨앗 | 날짜 수 | 월 수 |
| --- | ---: | ---: | ---: | ---: | ---: |
| today | 150 | 3 | 2 | 1 | 0 |
| week | 210 | 3 | 2 | 7 | 0 |
| all | 360 | 4 | 3 | 4 | 2 |

세 기간 모두 기존 get_focus_history의 summary와 일치했다. 같은 작물의 수확 3회,
자동 수확으로 표시된 실제 harvest 행, 수확 행 없는 harvested 세션, 0초 씨앗,
수확일과 다른 record_date, 다른 연도의 같은 월을 포함한 fixture를 사용했다.
사용자 B의 빈 응답과 직접 타 사용자 세션 SELECT의 빈 결과를 확인했다.
잘못된 기간은 HTTP 400/22023/INVALID_INPUT, 익명 RPC는 HTTP 401/42501이었다.
읽기 전후 본인 세션·수확 데이터 스냅샷도 동일했다.

### 승인된 RLS 예외 13항목

| 항목 | 실제 확인 |
| --- | --- |
| 본인 확정 참조 비활성 작물 | 직접 SELECT 및 RPC 성공 |
| 타인 확정 참조 작물 | A/B 상호 차단 |
| 미참조 비활성 작물 | 차단 |
| focusing/paused만 참조 | 각각 차단 |
| 익명 | 테이블·RPC 권한 차단 |
| list_crops | 테스트 비활성 작물 제외, 활성 목록 유지 |
| start_focus | 본인 과거 기록에 있어도 비활성 심기 PT404/CROP_NOT_FOUND |
| 마지막 참조 초기화 | 직접 SELECT 권한 즉시 소멸 |
| 비활성 집중·실제 수확 보존 | 50초/수확 1/씨앗 1, 실제 작물명 반환 |
| 기존 기록 API 합계 | 비활성 fixture도 동일 |
| 순환·성능 | 원격 실제 조회 성공, 정책 의존 그래프 비순환, 로컬 대량 EXPLAIN 완료 |
| 직접 SELECT 열 | 기존 6개 열 그대로, 추가 쓰기 권한 없음 |
| 기존 crops 참조 RPC 영향 | list/start 원격 확인, farm 로컬 회귀 및 영향 분석 완료 |

RLS 시험을 위해 별도 비활성 작물 5개와 임시 A/B 계정 소유 데이터만 생성했다.
기존 6개 작물이나 실제 사용자 데이터는 수정하지 않았다. 테스트 UUID·email·run metadata로
계정을 특정하여 로그아웃·삭제했고, 시험 작물도 UUID+이름+비활성 조건으로만 삭제했다.
각 계정의 users/profiles/plots/sessions 잔여 0건과 테스트 작물 잔여 0건을 확인했다.
수확은 세션 FK CASCADE로 제거되며 A의 reset 후 합계/배열 0도 실제 SDK로 검증했다.
최종 원격 재조회에서도 crop_history_test_run 계정 0, 시험 작물 0, 기존 활성 작물 6종을 확인했다.
원격 전체 사용자/업무 데이터가 0이라고 가정하거나 그 상태를 요구하지 않았다.

## Advisor 결과와 남은 위험

Security Advisor는 배포 전후 동일하다: private 정책 없는 테이블 INFO 2,
기존 platform rls_auto_enable의 anon definer WARN 1, 기존 authenticated definer WARN 17,
[유출 비밀번호 방어 설정 WARN 1](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
기존 기능/운영 Auth 설정을 이번 API 범위 밖에서 임의로 변경하지 않았다.

Performance Advisor는 기존 FK 인덱스 INFO 2를 유지하며,
[multiple_permissive_policies WARN 1](https://supabase.com/docs/guides/database/database-linter?lint=0006_multiple_permissive_policies)이 crops에 추가됐다.
이는 기존 active 정책 유지와 승인된 별도 own_history 정책을 함께 평가하기 때문이다.
정책을 합치거나 원래 정책을 바꾸지 않았다. 제한된 공개 범위를 유지하며 실제 로컬 대량 성능을 측정했다.
운영 동시 부하/장기간 누적 응답은 별도 관찰 대상이다.

- S14의 작물별 씨앗/ripe/수확완료 집중 시간 분리는 현재 계약으로 불가능: **PENDING 팀 합의**.
- all 페이지네이션은 이번 MVP에 없으며 데이터를 임의로 자르지 않는다.
- Figma 메타데이터만 대조했으며 실제 프론트 UI E2E는 **PENDING**.
- Notion 접근 불가. [최종 명세](../api/crop-history.md)를 붙여넣기용 문서로 제공한다.
- 기존 Cron 예약 수확 E2E는 이전 검증 기록을 유지한다. 이번 작업에서는 ACTIVE/설정 보존만 확인했다.

## 프론트 전달용 메시지

> get_crop_history(p_period)가 Staging 배포 및 실제 Auth/RPC·RLS 검증을 완료했습니다.
> today/week/all을 지원하며 S14=crop_totals, S15=items[].crops,
> S15-1=monthly[].crops 및 crop_totals로 연결하면 됩니다.
> summary로 기존 총합도 표시할 수 있어 중복 호출은 필요하지 않습니다.
> 기존 get_focus_history는 그대로입니다. S14의 상태별 작물 시간 분리는 별도 합의가 필요합니다.
> 최종 명세: docs/api/crop-history.md, 실제 응답: docs/api/crop-history-examples.json.

Discord/카카오톡으로 메시지를 실제 발송하지는 않았다.
