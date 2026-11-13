# Supabase 프로젝트 준비 체크리스트

## 확인된 Staging

| 항목 | 값 |
|---|---|
| 환경 | STAGING |
| 이름 | \`focus-farm-staging\` |
| Project Ref | \`klanbfvywwudprunaqdf\` |
| 리전 | \`ap-northeast-2\` (Seoul) |
| PostgreSQL | 17.11 |
| CLI | 3.1.0 |
| 연결 | CLI 인증 및 IPv4 Session Pooler 확인 |
| 원격 migration | 0개 |
| 실제 배포 | 미실행 |

Connection URL, Access Token, DB 비밀번호와 Secret key는 문서나 로그에 기록하지 않습니다. GoldenLook과 다른 프로젝트는 접근하거나 재사용하지 않습니다.

## 완료와 잔여 항목

- [x] Staging 생성, 서울 리전, PostgreSQL 17.11 확인
- [x] CLI 인증, 정확한 Project Ref link, IPv4 Session Pooler 연결
- [x] 원격 migration list와 업무 객체 0개 확인
- [x] Confirm email OFF 저장
- [x] dry-run 후보 확인
- [ ] 원격 회원가입으로 Auth 정책 실측
- [ ] 집중 세션 상태 확정 문제 해결
- [ ] A/B 검토와 최초 배포 승인·적용

## Auth 설정

확정 정책은 이메일/비밀번호, 신규 가입 허용, Confirm email OFF, 회원가입 metadata의 \`nickname\`입니다. 이번 준비 작업에서는 Dashboard 설정을 변경하지 않습니다. Site URL, Redirect URL, 비밀번호 강도와 rate limit은 별도로 확정합니다.

## 보안·운영 준비

- [ ] 프로젝트 관리자·개발자 최소 역할과 접근 회수 담당자 지정
- [ ] 조직 관리자 MFA 확인
- [ ] Staging 프론트에는 Project URL과 Publishable key만 등록
- [ ] Secret key와 DB 자격 증명이 브라우저·Git·CI 로그에 없음을 확인
- [ ] Data API 노출, RLS와 명시적 GRANT 일치 확인
- [ ] 백업 보존 기간, RPO/RTO와 복구 책임자 확인
- [ ] Production은 별도 프로젝트로 생성

## 연결 검증

~~~bash
npx supabase link klanbfvywwudprunaqdf
npx supabase migration list --remote
npx supabase db push --dry-run --skip-vault --remote
~~~

CLI 출력이 \`focus-farm-staging (klanbfvywwudprunaqdf)\`와 다르면 중단합니다. CLI의 \`production\` 표시는 독립 프로젝트 primary database 분류이며 환경 용도를 대체하지 않습니다. 실제 적용은 별도 승인 없이는 실행하지 않습니다.

공식 참고: [Database Backups](https://supabase.com/docs/guides/platform/backups), [Production Checklist](https://supabase.com/docs/guides/deployment/going-into-prod)
