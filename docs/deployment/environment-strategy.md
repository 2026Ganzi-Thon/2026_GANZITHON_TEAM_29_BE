# 환경 분리 전략

## 현재 상태

- LOCAL만 구축되어 있습니다. 원격 Supabase 프로젝트는 확정되지 않았고 CLI도 연결되지 않았습니다.
- `supabase/config.toml`의 `project_id = "focus-farm-local"`은 로컬 컨테이너 이름이며 원격 Project Ref가 아닙니다.
- 기존 프로젝트, 특히 GoldenLook은 집중농장 환경으로 간주하거나 재사용하지 않습니다.
- PR #1의 A 마이그레이션과 Backend CI는 아직 `develop`에 병합되지 않았습니다.

## 목표 환경

| 환경 | 목적 | 데이터 | Git 기준 | 배포 |
|---|---|---|---|---|
| LOCAL | 개인 개발·DB reset·pgTAP·통합 테스트 | 합성 테스트 데이터만 | 이슈 브랜치 | 개발자가 로컬 실행 |
| STAGING | 프론트/백엔드 통합·릴리스 후보 검증 | 테스트 계정만 | `develop` | 승인된 후보만 수동 승인 배포 |
| PRODUCTION | 실제 사용자 서비스 | 실제 사용자 데이터 | `main` | 보호된 GitHub Environment 승인 후 배포 |

PRODUCTION에서는 `db reset`, 테스트 사용자 생성, seed 적용, `migration repair`를 실행하지 않습니다.

## 권장안: 프로젝트 2개

STAGING과 PRODUCTION을 서로 다른 Supabase 프로젝트로 운영합니다.

장점:

- 테스트와 실제 사용자 데이터가 물리적으로 분리됨
- Auth 사용자·키·로그·rate limit·백업 정책을 독립 관리
- staging의 reset이나 잘못된 마이그레이션이 production에 영향을 주지 않음
- `develop`과 `main`의 배포 대상을 명확히 고정 가능

비용:

- 프로젝트별 compute/plan 사용량과 부가 기능 비용이 발생할 수 있음
- 백업, SMTP, 모니터링, Secret과 접근 권한을 두 환경에서 관리해야 함
- 정확한 금액은 프로젝트 생성 시점의 Supabase 요금제와 선택한 compute를 확인해야 하며 이 문서에서 고정하지 않음

## 간소화안: 원격 프로젝트 1개

비용 승인이 늦어지면 원격 프로젝트 하나를 **staging 전용**으로 먼저 만들 수 있습니다. 실제 사용자 유입 전 별도 production 프로젝트를 만들고 동일 마이그레이션을 처음부터 적용합니다.

하나의 프로젝트에 staging과 production 사용자를 섞는 방식은 허용하지 않습니다. 스키마 접두사만으로 Auth 사용자, 프로젝트 키, 로그, 백업, rate limit을 안전하게 분리할 수 없기 때문입니다.

## 결정 기준

1. 실제 사용자 서비스 전에는 production 프로젝트가 별도로 존재해야 함
2. 한국 사용자 중심이면 구체 리전 `ap-northeast-2`(Seoul)를 우선 검토
3. 데이터 위치 요구사항, 예산, 백업 보존 기간을 함께 승인
4. 프로젝트 생성 후 Project Ref와 PostgreSQL major version을 기록

## CI/CD 단계

- PR → PR #1 병합 후 Backend CI가 로컬 Supabase에서 reset, pgTAP, Auth/RPC 통합, lint, audit 수행
- `develop` → STAGING 배포 후보 생성; 자동 배포하지 않고 보호된 GitHub Environment의 승인 후 수동 실행
- `main` → PRODUCTION 배포 후보 생성; STAGING 검증 증거와 별도 운영 승인 필요
- 실제 배포 → 테스트 성공 커밋과 배포 커밋이 같은지 확인한 뒤 `db push --dry-run --remote`, 승인, `db push --remote` 순서

원격 프로젝트와 Secret 이름이 확정되기 전에는 배포 workflow를 추가하지 않습니다. 확정 후에도 push 이벤트만으로 DB를 변경하지 않고 `workflow_dispatch`, environment required reviewer, branch 제한을 함께 사용합니다. 배포 job은 기존 Backend CI의 성공을 선행 조건으로 삼고 Production에서 reset·seed·repair 명령을 포함하지 않습니다.

관련 절차는 [Supabase 프로젝트 준비](supabase-setup.md), [마이그레이션 런북](migration-runbook.md)을 따릅니다.

공식 참고: [Managing Environments](https://supabase.com/docs/guides/deployment/managing-environments), [Available Regions](https://supabase.com/docs/guides/platform/regions)
