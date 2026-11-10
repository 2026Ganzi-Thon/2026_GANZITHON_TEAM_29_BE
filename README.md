# 집중농장 Backend

2026 간지톤 TEAM 29 `집중농장`의 Supabase 전용 백엔드 저장소입니다.

## 범위

- Supabase Auth 이메일/비밀번호 인증
- PostgreSQL 스키마와 마이그레이션
- RPC와 Row Level Security
- 데이터베이스 테스트
- Supabase Cron 기반 자동 수확(담당 B, 후속 단계)

Spring Boot 또는 별도 애플리케이션 서버와 프론트엔드 코드는 이 저장소의 범위가 아닙니다.

## 현재 상태

Phase 1 공용 개발 기반만 구성되어 있습니다. 업무 테이블, RPC, RLS 정책 및 Cron은 아직 구현하지 않았습니다. 원격 Supabase 프로젝트도 연결하지 않았습니다.

## 시작하기

필수 조건:

- Node.js 20 이상
- npm
- Docker 호환 런타임(OrbStack 또는 Docker Desktop 권장)

```bash
npm ci
npx supabase --version
npm run db:start
```

컨테이너 런타임이 실행 중이어야 `db:start`, `db:reset`, `db:test`, `db:lint`를 사용할 수 있습니다. 현재 업무 테스트 SQL은 아직 없어 `db:test`가 `NOTESTS`를 반환합니다.

개발 및 브랜치 규칙은 [docs/development.md](docs/development.md), RPC 계약은 [docs/api/rpc-contracts.md](docs/api/rpc-contracts.md)를 참고하세요.
