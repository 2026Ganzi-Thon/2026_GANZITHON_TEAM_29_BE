# Supabase 프로젝트 준비 체크리스트

이 체크리스트는 프로젝트 생성 승인 이후에 사용합니다. 현재 집중농장 원격 프로젝트는 미확정이며 어떤 기존 프로젝트에도 연결하지 않습니다.

## 생성 전 승인

- [ ] 과금 가능성과 예상 사용 기간을 프로젝트 소유자가 승인
- [ ] Supabase 조직 소유자가 TEAM 29 공용 조직인지 확인
- [ ] STAGING / PRODUCTION 프로젝트 수 결정
- [ ] 프로젝트 이름 규칙 결정: 예시 `focus-farm-staging`, `focus-farm-production`
- [ ] GoldenLook 및 다른 서비스 프로젝트가 아님을 두 명이 확인
- [ ] 리전 결정: 한국 사용자 중심 권장 후보 `Northeast Asia (Seoul) / ap-northeast-2`
- [ ] 요금제·compute·백업 보존 정책 승인

## 생성 후 기록

비밀값은 문서나 이슈에 기록하지 않습니다.

- [ ] 조직명과 프로젝트 표시명
- [ ] 환경(STAGING 또는 PRODUCTION)
- [ ] Dashboard의 Project Ref(Project ID)
- [ ] API URL
- [ ] 리전
- [ ] `show server_version;` 결과와 로컬 `db.major_version` 호환성
- [ ] 프로젝트 소유자와 관리자 목록
- [ ] 개발자별 최소 역할과 퇴사/이탈 시 회수 담당자
- [ ] DB 직접 연결 허용 대상과 SSL 요구사항
- [ ] Publishable key 발급 및 프론트 환경별 등록
- [ ] Secret key가 브라우저와 프론트 빌드 환경에 없음을 확인
- [ ] DB 비밀번호를 비밀 관리자에 저장하고 공유 채널에 게시하지 않음
- [ ] 개인 Access Token 대신 가능하면 프로젝트 범위가 제한된 토큰 사용

## 플랫폼 보안

- [ ] 조직 관리자 MFA 활성화 및 가능하면 조직 MFA 강제
- [ ] Data API 노출 스키마가 `public`, `graphql_public`에 한정되는지 확인
- [ ] 새 public 객체 자동 노출 정책과 마이그레이션의 명시적 GRANT가 일치하는지 확인
- [ ] 모든 노출 테이블의 RLS 활성화 확인
- [ ] `anon`, `authenticated`, `service_role`의 기본·명시 권한 검토
- [ ] `SECURITY DEFINER` 함수의 고정 `search_path`, 소유권 검사, EXECUTE 권한 검토
- [ ] Network Restrictions와 SSL Enforcement 적용 가능성 검토
- [ ] Pooler/direct connection 용도를 구분하고 애플리케이션에 DB 관리자 자격 증명을 제공하지 않음

## 백업·로그·모니터링

- [ ] 선택한 요금제의 자동 백업 보존 기간 확인
- [ ] 복구 목표(RPO/RTO)와 PITR 필요 여부 결정
- [ ] Free tier라면 정기 논리 백업과 외부 보관 책임자 지정
- [ ] 복구 연습은 production이 아닌 별도 프로젝트에서 수행
- [ ] Database/Auth/API 로그 보존 기간 확인
- [ ] Auth 실패, 429, 5xx, migration 실패, Cron 실패의 확인 담당자 지정
- [ ] 배포 직후 로그 관찰 시간과 롤백 판단 기준 기록

## 연결 승인 게이트

다음 값이 승인되기 전에는 `supabase link`를 실행하지 않습니다.

1. 환경명
2. Project Ref
3. 조직·프로젝트 표시명
4. 리전과 PostgreSQL 버전
5. 해당 환경을 변경할 승인자

연결 후 `npx supabase status`의 `linked_project`를 확인하고 [마이그레이션 런북](migration-runbook.md)의 읽기·dry-run 단계부터 진행합니다.

공식 참고: [Database Backups](https://supabase.com/docs/guides/platform/backups), [Production Checklist](https://supabase.com/docs/guides/deployment/going-into-prod)
