# 로컬 개발 실행 가이드

## 준비

1. Node.js 20 이상을 설치합니다.
2. OrbStack 또는 Docker Desktop처럼 Docker API와 호환되는 런타임을 설치하고 실행합니다.
3. 의존성을 설치합니다.

```bash
npm ci
```

macOS에서는 OrbStack을 사용할 수 있습니다.

```bash
brew install --cask orbstack
orb start
docker version
```

로컬 서비스 포트가 외부 LAN에 노출되지 않도록 OrbStack 설정을 확인합니다.

```bash
orb config set docker.expose_ports_to_lan false
orb config set machines.expose_ports_to_lan false
```

## 로컬 Supabase

```bash
npm run db:start
npx supabase status
```

작업 후에는 다음 명령으로 중지합니다.

```bash
npm run db:stop
```

## 검증 명령

```bash
npm run db:reset
npm run db:test
npm run test:integration
npm run db:lint
npm audit
```

`test:integration`은 로컬 DB 컨테이너가 실행 중이어야 하며 원격 프로젝트를 사용하지 않습니다.

## 2026-11-10 검증 상태

- OrbStack 2.2.5 및 Docker Engine 29.8.2 실행 확인
- PostgreSQL 17.11 실행 확인
- Auth health endpoint 응답 확인
- Studio와 Mailpit 접속 확인
- 로컬 DB reset 및 seed 실행 확인
- DB lint 오류 0건
- Phase 2 A pgTAP과 Auth/RPC 통합 테스트는 [별도 검증 런북](a-foundation-verification.md)에 기록

## 현재 BLOCKED 항목

원격 Supabase 프로젝트가 확정되지 않았으므로 link, 원격 schema pull/push 및 원격 테스트도 수행하지 않습니다.

`supabase/config.toml`의 `project_id = "focus-farm-local"`은 로컬 컨테이너 식별자이며 원격 프로젝트 ID가 아닙니다. 생성된 PostgreSQL 17 설정도 CLI 기본값이므로, 원격 프로젝트가 확정되면 실제 major version과 일치하는지 확인해야 합니다.
