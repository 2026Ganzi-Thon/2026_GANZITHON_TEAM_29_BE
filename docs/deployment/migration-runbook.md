# 원격 마이그레이션 런북

Supabase CLI `3.1.0` 기준입니다. CLI v3는 로컬이 기본 대상이며 원격 명령에는 `--remote`가 필요합니다. 이 문서의 원격 명령은 프로젝트 승인 후에만 실행합니다.

## 금지 사항

- PRODUCTION에서 `db reset`, `--include-seed`, 테스트 계정 생성 금지
- Dashboard SQL/Table Editor로 업무 스키마를 직접 변경하지 않음
- 병합된 마이그레이션 수정·삭제 금지
- `migration repair`를 일반 배포나 자동 복구로 사용하지 않음
- GoldenLook 또는 Project Ref가 검증되지 않은 프로젝트에 연결 금지
- 여러 사람이 동시에 `db push` 실행 금지

## 1. 배포 대상 확인

승인 티켓에 환경, 조직, 프로젝트명, Project Ref, 리전, 배포 커밋 SHA와 승인자를 기록합니다. CLI 출력의 대상이 승인 티켓과 다르면 중단합니다.

```bash
npx supabase --version
npx supabase status
```

프로젝트가 승인된 최초 1회에만 다음 연결을 수행합니다.

```bash
npx supabase link <approved-project-ref>
```

## 2. 버전과 원격 상태 확인

- Dashboard 또는 승인된 읽기 전용 연결에서 `show server_version;` 확인
- `supabase/config.toml`의 `db.major_version`과 major version 일치 확인
- 저장소와 원격의 마이그레이션 이력 비교

```bash
npx supabase migration list --remote
```

차이가 예상과 다르거나 원격에만 존재하는 버전이 있으면 배포를 중단합니다. `db pull`이나 `migration repair`는 원인 조사와 별도 승인 없이 실행하지 않습니다.

## 3. 적용 SQL 검토

```bash
git diff <last-deployed-sha>..HEAD -- supabase/migrations
```

두 명이 다음을 검토합니다.

- 파괴적 DDL, 테이블 재작성, 장시간 lock 가능성
- 새 public 테이블의 RLS와 정책
- `PUBLIC`, `anon`, `authenticated`, `service_role` GRANT/REVOKE
- `SECURITY DEFINER`, 고정 `search_path`, 소유권 검증
- FK·UNIQUE·CHECK·인덱스와 데이터 backfill 순서
- 재시도·동시 실행 안전성과 Cron 함수 권한

## 4. 로컬 회귀 검증

PR #1 병합 후 현재 CI와 동일한 명령을 실행합니다.

```bash
npm ci
npm run db:start
npm run db:reset
npm run db:test
npm run test:integration
npm run db:lint
npm audit
```

테스트가 없거나 실행되지 않은 단계를 PASS로 기록하지 않습니다.

## 5. 원격 dry-run

```bash
npx supabase db push --dry-run --remote
```

출력된 마이그레이션 파일이 승인 목록과 정확히 같아야 합니다. `--include-all`, `--include-seed`, `--include-roles`는 별도 승인 없이는 사용하지 않습니다.

## 6. 백업과 승인

- STAGING: 테스트 데이터만 존재하는지 확인
- PRODUCTION: 최신 백업 시각, 복구 가능 범위, 배포 후 관찰 담당자 확인
- GitHub Environment 또는 배포 승인 기록 확보
- 한 명의 배포 실행자만 지정

## 7. 적용

CLI v3의 원격 변경 확인 프롬프트에서 대상과 목록을 다시 확인합니다. CI를 사용할 때만 보호된 Environment 승인 뒤 `--yes`를 사용합니다.

```bash
npx supabase db push --remote
```

## 8. 적용 후 검증

```bash
npx supabase migration list --remote
npx supabase db lint --remote --level warning --fail-on error
```

[릴리스 체크리스트](release-checklist.md)에 따라 Auth, 프로필 트리거, RPC, RLS, 고정 작물, 로그를 검증합니다. Production에서 파괴적인 테스트를 실행하지 않습니다.

## 9. 실패와 복구

1. 추가 배포와 앱 릴리스를 중단
2. CLI 출력·DB/Auth/API 로그·적용된 migration version 보존
3. 트랜잭션 실패면 실제 적용 여부를 `migration list --remote`와 스키마로 확인
4. 전진 수정이 안전하면 새 마이그레이션을 작성하고 전체 검증 후 배포
5. 데이터 손상 또는 서비스 중단이면 프로젝트 소유자가 백업/PITR 복구를 승인
6. `migration repair`는 SQL을 되돌리지 않고 이력만 수정하므로 실제 스키마가 맞다는 증거와 A/B 공동 승인이 있을 때만 별도 실행

복구 후 원인, 영향 시간, 데이터 영향, 재발 방지 테스트를 기록합니다.

공식 참고: [Supabase CLI v3 변경사항](https://supabase.com/changelog/supabase-cli-v3), [Deploy Database Migrations](https://supabase.com/docs/guides/deployment/database-migrations)
