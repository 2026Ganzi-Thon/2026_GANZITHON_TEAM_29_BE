# 환경변수와 Secret 관리

## 값 분류

| 값 | 브라우저 | 저장 위치 | 비밀 |
|---|---|---|---|
| Supabase Project URL | 허용 | 프론트 환경 설정 | 아니요 |
| Publishable key | 허용 | 프론트 환경 설정 | 아니요; RLS 필수 |
| Secret/service_role key | 금지 | 서버 비밀 관리자 | 예 |
| DB 비밀번호·Connection URL | 금지 | 로컬 키체인 또는 배포 Secret | 예 |
| Supabase Access Token | 금지 | 로컬 키체인 또는 배포 Secret | 예 |
| Project Ref | 금지 아님 | 환경별 배포 설정 | 아니요; 대상 식별값 |

Staging Ref는 \`klanbfvywwudprunaqdf\`입니다. 공개 가능한 식별자라도 다른 프로젝트와 혼동하지 않도록 환경별로 고정합니다. Connection URL, token, DB 비밀번호와 Secret key는 Git, 채팅, 이슈와 CI 로그에 남기지 않습니다.

## 로컬

- \`.env.example\`에는 변수명만 둡니다.
- 실제 값은 Git에서 무시되는 파일이나 OS 키체인에 저장합니다.
- \`SUPABASE_YES\`를 env 파일에 저장하지 않습니다.
- CLI 인증과 Session Pooler 정보를 커밋하지 않습니다.
- 로컬 키를 원격 환경에 재사용하지 않습니다.

## GitHub Actions

STAGING과 PRODUCTION에 별도 GitHub Environment를 사용합니다.

- 프로젝트 범위가 제한된 \`SUPABASE_ACCESS_TOKEN\`
- 필요한 경우 \`SUPABASE_DB_PASSWORD\`
- 대상 식별용 \`SUPABASE_PROJECT_ID\`

실제 DB 변경 job에는 required reviewer와 브랜치 제한을 적용합니다. Secret 전체 출력과 shell debug trace를 금지합니다. Secret key는 DB 마이그레이션에 필요하지 않으므로 workflow에 넣지 않습니다.

## 프론트와 사고 대응

프론트에는 환경별 Project URL과 Publishable key만 전달합니다. 브라우저 번들·요청·오류 로그에 Secret, DB URL, Access Token, JWT와 refresh token이 없어야 합니다.

노출 시 파일 삭제로 끝내지 않고 즉시 폐기·교체하고 접근 로그, GitHub/배포 Secret, 영향받은 세션과 재발 방지 조치를 확인합니다. Git 이력 정리는 팀 합의 없이 force push하지 않습니다.
