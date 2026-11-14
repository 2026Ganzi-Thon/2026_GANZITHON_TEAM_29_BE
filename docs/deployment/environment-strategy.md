# 환경 분리 전략

## 현재 상태

- LOCAL: OrbStack, Supabase CLI 3.1.0, PostgreSQL 17 로컬 환경
- STAGING: \`focus-farm-staging\`(\`klanbfvywwudprunaqdf\`), \`ap-northeast-2\`(Seoul), PostgreSQL 17.11
- 2026-11-13 기준 CLI 인증, 정확한 Project Ref, IPv4 Session Pooler, 원격 읽기와 dry-run 확인
- 원격 마이그레이션과 업무 스키마는 0개이며 실제 배포는 미실행
- \`supabase/config.toml\`의 \`focus-farm-local\`은 로컬 컨테이너 이름
- GoldenLook과 다른 프로젝트는 접근하거나 재사용하지 않음

최신 \`develop\`에는 A 기반, B 농장 기반, B 집중 세션의 마이그레이션 3개가 있습니다. 집중 세션에는 목표 도달 또는 24시간 일시정지 만료 뒤 DB 상태가 확정되지 않아 새 집중 시작이 막힐 수 있는 알려진 제한이 있습니다. 후속 수정과 팀 승인 전에는 Staging 배포를 보류합니다.

## 환경별 경계

| 환경 | 목적 | 데이터 | Git 기준 | 배포 |
|---|---|---|---|---|
| LOCAL | 개발·reset·테스트 | 합성 데이터 | 작업 브랜치 | 개발자 실행 |
| STAGING | 통합·릴리스 후보 검증 | 테스트 계정만 | 승인된 \`develop\` | 별도 승인 후 수동 |
| PRODUCTION | 실제 서비스 | 실제 사용자 데이터 | 승인된 \`main\` | 보호된 승인 후 |

STAGING과 PRODUCTION은 별도 프로젝트를 사용합니다. PRODUCTION에서는 reset, seed, 테스트 사용자 생성과 migration repair를 실행하지 않습니다.

## Auth 결정

이메일/비밀번호 가입과 신규 가입을 허용하고 \`nickname\` metadata를 전달합니다. Confirm email은 OFF이며 이메일 인증 링크를 사용하지 않습니다. Staging Dashboard 저장은 완료됐지만 원격 회원가입은 아직 실측하지 않았습니다.

## CI/CD

- PR: 로컬 reset, pgTAP, Auth/RPC 통합, lint, advisors, audit
- \`develop\`: STAGING 배포 후보, 자동 배포 금지
- \`main\`: PRODUCTION 배포 후보, STAGING 증거와 별도 승인 필요
- 실제 배포: 동일 SHA 테스트 → 원격 이력 → dry-run → A/B 검토 → 승인 → 한 명이 적용

관련 절차는 [Supabase 프로젝트 준비](supabase-setup.md), [Auth 정책](auth-production-policy.md), [마이그레이션 런북](migration-runbook.md)을 따릅니다.

공식 참고: [Managing Environments](https://supabase.com/docs/guides/deployment/managing-environments), [Available Regions](https://supabase.com/docs/guides/platform/regions)
