# 집중농장 Backend

2026 간지톤 TEAM 29 `집중농장`의 Supabase 전용 백엔드 저장소입니다. Spring Boot 또는 별도 애플리케이션 서버와 프론트엔드 코드는 범위에 포함하지 않습니다.

## 현재 상태

Phase 2 A 기반을 구현했습니다.

- Supabase Auth 회원가입 프로필 트리거
- `profiles`, `crops` 및 RLS
- `get_my_profile()`, `complete_onboarding()`, `list_crops(p_energy)`
- pgTAP DB 테스트와 로컬 Auth/RPC 통합 테스트

원격 Supabase 프로젝트는 연결하지 않았습니다. B 도메인·Cron과 A의 농장/기록 조회는 후속 범위입니다.

## 로컬 실행

필요 환경은 Node.js 20 이상, npm, OrbStack 또는 Docker Desktop입니다.

```bash
npm ci
npm run db:start
npm run db:reset
```

## 검증

```bash
npm run db:test
npm run test:integration
npm run db:lint
npm audit
```

`test:integration`은 로컬 Supabase Auth에 실제 회원가입하고 액세스 토큰으로 세 RPC를 호출합니다. 운영 키나 원격 DB를 사용하지 않습니다.

## 문서

- [개발 및 브랜치 규칙](docs/development.md)
- [RPC·A/B 공통 계약](docs/api/rpc-contracts.md)
- [마이그레이션 순서](docs/database/migrations.md)
- [Phase 2 범위](docs/phase-2-scope.md)
