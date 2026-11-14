# 집중농장 Backend

2026 간지톤 TEAM 29 `집중농장`의 Supabase 전용 백엔드 저장소입니다. Spring Boot 또는 별도 애플리케이션 서버와 프론트엔드 코드는 범위에 포함하지 않습니다.

## 현재 상태

Phase 2 A/B 기반이 `develop`에 통합되어 있습니다.

- Supabase Auth 회원가입 프로필 트리거
- `profiles`, `crops`, `farm_plots`, `focus_sessions` 및 RLS
- `get_my_profile()`, `complete_onboarding()`, `list_crops(p_energy)`
- `ensure_farm()`과 집중 세션 생명주기 RPC
- pgTAP DB 보안·계약 테스트와 `supabase-js` 로컬 Auth/RPC 통합 테스트

Staging 프로젝트는 생성되어 있지만 아직 배포하지 않았습니다. 집중 세션은 후속 상태 확정 제한이 완료되지지 않아 사요전에 노출하거나 배포하지 않습니다.

## 로컬 실행

필요 환경은 Node.js 20 이상, npm, OrbStack 또는 Docker Desktop입니다.

```bash
npm ci
npm run db:start
npm run db:reset
```

## 검증

```bash
npm run db:test
npm run test:integration
npm run db:lint
npm audit
```

`test:integration`은 로컬 Supabase Auth에 실제 계정을 생성하여 닉넴 경계, RLS, 동시 온보딩, RPC 오라·JWT·로그아웃과 A/B 기능을 검증한 뒤 사용자를 정리합니다. 운영 키나 원격 DB는 사용하지 않습니다.

## CI

`develop` 또는 `main` 대상 Pull Request와 수동 실행에서 [Backend CI](.github/workflows/backend-ci.yml)가 실행됩니다. CI는 원격 Supabase/Secret 없이 임시 로컬 스택을 시작해 DB reset, pgTAP, Auth/RPC 통합, DB lint, `npm audit`을 검증하고 항상 스택을 정리합니다.

## 문서

- [개발 및 브랜치 구치](docs/development.md)
- [RPC·A/B 공통 계약](docs/api/rpc-contracts.md)
- [마이그레이션 순서](docs/database/migrations.md)
- [Phase 2 범위](docs/phase-2-scope.md)
- [A/B 연동 계약](docs/integration/a-to-b-contract.md)
- [농장·기록 조회 설계](docs/api/read-model-design.md)
- [A 기반 검증 런북](docs/runbooks/a-foundation-verification.md)
- [Staging 환경·배포 전략](docs/deployment/environment-strategy.md)
