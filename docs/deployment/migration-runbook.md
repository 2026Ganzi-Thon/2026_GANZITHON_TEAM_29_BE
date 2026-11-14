# 원격 마이그레이션 런북

Supabase CLI 3.1.0 기준입니다. CLI v3는 로컬이 기본 대상이므로 원격 명령에는 \`--remote\`를 명시합니다. hosted 변경은 별도 승인 전에는 실행하지 않습니다.

## 현재 Staging 사전 검증

대상은 \`focus-farm-staging (klanbfvywwudprunaqdf)\`, Seoul, PostgreSQL 17.11입니다. 2026-11-13 기준 원격 이력과 업무 객체는 0개입니다.

현재 `origin/develop`의 dry-run 후보 스냅샷은 다음 세 개입니다.

1. \`20261110152140_a_foundation.sql\`
2. \`20261113012151_b_farm_foundation.sql\`
3. \`20261113020509_b_focus_sessions.sql\`

세 번째 마이그레이션은 목표 도달/일시정지 만료 후 상태가 확정되지 않아 새 집중이 막힐 수 있습니다. 후속 수정과 팀 승인 전까지 **배포 보류**입니다. 현재 HEAD에서 표준 \`db push\`로 앞의 두 파일만 선택 적용하지 않습니다.

이 목록은 최종 배포 목록이 아닙니다. PR #7과 PR #8에는 각각 다음 A 마이그레이션이 있으며, 실제 후보에는 `develop` 병합 후에만 포함합니다.

- `20261113143508_a_farm_read_model.sql` — `get_my_farm()`
- `20261113145323_a_focus_history.sql` — `get_focus_history(p_period)`

두 PR의 임시 통합 검증은 pgTAP 167개, Auth/RPC 통합, History 통합, DB lint를 통과했지만 병합·원격 배포 증거는 아닙니다. 각 기능 PR 병합과 B 후속 마이그레이션 완료 후 `origin/develop`의 실제 파일 목록, CI SHA와 원격 dry-run을 다시 기록합니다. 마이그레이션 개수를 운영 문서에 고정값으로 가정하지 않습니다.

## 금지 사항

- 승인 없는 \`db push --remote\`
- 원격 reset, seed, 테스트 사용자 생성과 직접 DDL/DML
- 병합된 마이그레이션 수정·삭제
- 원인 조사 없는 \`migration repair\`
- 여러 사람의 동시 배포
- GoldenLook 또는 검증되지 않은 Project Ref 연결
- Connection URL, Access Token과 DB 비밀번호 출력

## 1. 대상과 원격 상태

~~~bash
git status --short --branch
git rev-parse HEAD
npx supabase --version
npx supabase link klanbfvywwudprunaqdf
npx supabase migration list --remote
npx supabase db query --remote --read-only "select current_setting('server_version');"
~~~

CLI 대상이 승인 기록과 다르거나 원격에 예상 밖 이력·객체가 있으면 중단합니다. repair로 맞추지 않습니다.

## 2. 로컬 회귀

~~~bash
npm ci
npm run db:start
npm run db:reset
npm run db:test
npm run test:integration
npm run test:history
npm run db:lint
npx supabase db advisors --type all --level info --fail-on error
npm audit
~~~

결과를 배포 SHA와 함께 보존합니다.

## 3. SQL·보안 검토

A/B 두 명이 PK/FK/UNIQUE/CHECK, CASCADE, 인덱스, RLS, 직접 쓰기 차단, 역할별 GRANT/REVOKE, \`SECURITY DEFINER\`, 고정 \`search_path\`, \`auth.uid()\`, Auth 트리거 실패, 동시성·멱등성과 Cron 실행 역할을 검토합니다.

## 4. 원격 dry-run

~~~bash
npx supabase db push --dry-run --skip-vault --remote
~~~

출력 목록이 승인 목록과 순서까지 같아야 합니다. \`--include-all\`, \`--include-seed\`, \`--include-roles\`는 별도 승인 없이는 사용하지 않습니다.

## 5. 승인된 적용과 사후 검증

Staging 데이터와 복구 담당자를 확인하고 보류 사유가 해소된 동일 SHA에서 CI가 성공한 뒤 한 명만 실행합니다.

~~~bash
npx supabase db push --skip-vault --remote
~~~

적용 후 migration list, Auth 프로필 트리거, 작물 6종, A RPC 5개, \`ensure_farm()\`, 집중 RPC, RLS 격리, DB lint/advisors와 로그를 확인합니다. `get_focus_history()`의 수확 집계는 B 수확 스키마 전까지 `null` 계약임을 함께 확인합니다. 원격 Auth 사용자 생성은 별도 승인 대상입니다.

## 6. 실패와 복구

1. 추가 배포와 앱 릴리스를 중단합니다.
2. CLI 출력, 로그, migration version과 실제 객체 상태를 보존합니다.
3. 트랜잭션 롤백 여부와 외부 설정 반영 여부를 읽기 전용으로 확인합니다.
4. 데이터 보존이 가능하면 새 전진 수정 마이그레이션을 만듭니다.
5. 데이터 손상이나 중단이면 프로젝트 소유자가 백업/PITR 복구를 승인합니다.
6. 역 SQL은 데이터 손실과 의존 객체를 검토한 복구 마이그레이션으로만 수행합니다.
7. \`migration repair\`는 SQL을 되돌리지 않으므로 스키마 일치 증거와 A/B 공동 승인 없이는 사용하지 않습니다.

공식 참고: [Supabase CLI v3 변경사항](https://supabase.com/changelog/supabase-cli-v3), [Deploy Database Migrations](https://supabase.com/docs/guides/deployment/database-migrations)
