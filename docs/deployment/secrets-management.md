# 환경변수와 Secret 관리

## 분류

| 값 | 브라우저 사용 | 저장 위치 | 비밀 여부 |
|---|---|---|---|
| Supabase Project URL | 가능 | 프론트 환경 설정 | 공개 구성값 |
| Publishable key | 가능 | 프론트 환경 설정 | 공개 구성값; RLS 필수 |
| Secret key | 금지 | 서버 비밀 관리자 | 비밀 |
| legacy `service_role` key | 금지 | 가급적 신규 사용 금지; 필요 시 서버 비밀 관리자 | 비밀 |
| DB 비밀번호·연결 문자열 | 금지 | 배포 Environment Secret | 비밀 |
| Supabase Access Token | 금지 | 배포 Environment Secret | 비밀 |

Publishable key가 공개 가능하다는 것은 데이터가 공개라는 뜻이 아닙니다. 노출 스키마의 RLS와 객체 권한이 실제 보안 경계입니다.

## 로컬

- `.env.example`에는 변수명만 둡니다.
- 실제 값은 Git에서 무시되는 `.env.local` 등에 저장합니다.
- 셸 기록, 터미널 캡처, 이슈, 메신저, 테스트 로그에 Secret을 붙이지 않습니다.
- `SUPABASE_YES`를 env 파일에 저장하지 않습니다.
- CLI가 출력하는 로컬 키는 로컬 테스트 전용이며 원격 환경에 재사용하지 않습니다.

## GitHub Actions

STAGING과 PRODUCTION에 별도 GitHub Environment를 만들고 다음 값을 각각 저장합니다.

- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_DB_PASSWORD`
- `SUPABASE_PROJECT_ID` 또는 환경 변수로 전달할 Project Ref

원칙:

- 환경별 Secret을 repository 공용 Secret 하나로 합치지 않음
- PRODUCTION Environment에 required reviewer와 main 브랜치 제한 적용
- token은 필요한 프로젝트와 읽기/DB 쓰기 범위로 제한
- workflow에서 Secret 전체를 출력하거나 debug trace를 활성화하지 않음
- Project Ref는 비밀이 아니어도 배포 대상 혼동을 막기 위해 Environment별로 관리
- Secret key는 DB 마이그레이션에 필요하지 않으므로 배포 workflow에 넣지 않음

## 프론트엔드 전달

프론트에는 환경별로 Project URL과 Publishable key만 전달합니다. STAGING 빌드가 PRODUCTION 키를 사용하거나 반대가 되지 않도록 배포 플랫폼의 환경 분리를 사용합니다.

검증 항목:

- 브라우저 번들에 Secret key, DB URL, Access Token이 없음
- 오류 추적·분석 이벤트에 JWT와 refresh token이 없음
- `.env*`와 인증서·키 파일이 `.gitignore`로 제외됨
- 키 교체 시 프론트/서버/CI 영향과 폐기 순서를 기록

## 사고 대응

Secret이 Git, 로그 또는 채팅에 노출되면 삭제만으로 해결하지 않습니다.

1. 해당 키·토큰·DB 비밀번호를 즉시 폐기/교체
2. 접근 로그와 사용 범위 확인
3. GitHub Actions 및 배포 플랫폼 Secret 갱신
4. 영향받은 세션·배포 재발급
5. 원인과 재발 방지 조치 기록

과거 Git 이력 제거는 팀 합의와 별도 절차로 수행하며 force push를 임의로 사용하지 않습니다.
