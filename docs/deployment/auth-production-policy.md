# Auth 운영 정책

Supabase Auth 이메일/비밀번호 인증을 사용합니다. 아래 권장안은 운영 프로젝트에 아직 적용되지 않았으며 프로젝트 생성 후 A/프론트엔드/기획 승인이 필요합니다.

## 로컬과 운영 권장안

| 항목 | 현재 LOCAL | 운영 권장안 | 상태 |
|---|---|---|---|
| 이메일/비밀번호 | 활성 | 활성 | 확정 |
| 이메일 확인 | 비활성 | 활성 + Custom SMTP | 결정 필요 |
| 회원가입 | 허용 | 공개 출시 시 허용; 비공개 테스트는 초대/기간 제한 | 결정 필요 |
| 최소 비밀번호 길이 | 6 | 최소 8 | 권장 |
| 비밀번호 조합 | 제한 없음 | 영문 대·소문자와 숫자, UX 확인 후 기호 포함 여부 결정 | 결정 필요 |
| JWT 만료 | 3600초 | 3600초 유지 | 권장 |
| refresh token rotation | 활성 | 활성 유지 | 권장 |
| refresh reuse interval | 10초 | 기본 10초에서 시작 | 권장 |
| 익명 로그인 | 비활성 | 비활성 유지 | 권장 |
| Site URL | `http://127.0.0.1:3000` | 실제 HTTPS production URL 1개 | 미확정 |
| Redirect URL | 로컬 주소 | 환경별 정확한 HTTPS callback만 허용 | 미확정 |
| 비밀번호 변경 재인증 | 비활성 | `secure_password_change` 활성 검토 | 권장 |
| 로그인 rate limit | IP당 5분 30회 | 기본값에서 시작 후 429·공격 로그로 조정 | 권장 |

운영 Redirect URL에는 광범위한 `**` 패턴을 사용하지 않습니다. Preview URL이 필요하면 STAGING에만 제한된 패턴을 추가하고 PRODUCTION은 정확한 URL을 사용합니다.

## 이메일 확인과 SMTP

호스팅 프로젝트는 이메일 확인이 기본 활성일 수 있지만 Dashboard의 실제 값을 반드시 확인합니다. 이메일 확인을 활성화하려면 다음이 선행되어야 합니다.

- Custom SMTP 설정과 발신 도메인 검증
- 회원가입·재전송·비밀번호 재설정 템플릿 검수
- Site URL/Redirect URL 확정
- 만료 링크, 중복 클릭, 이미 확인된 계정 테스트
- 테스트 계정이 production 사용자와 분리됨을 확인

Supabase 기본 이메일 발송은 운영용 가용성을 보장하는 SMTP로 간주하지 않습니다.

## 세션과 로그아웃

- JWT 만료는 1시간을 권장합니다. 5분 미만은 refresh 부하와 시계 오차 문제 때문에 사용하지 않습니다.
- refresh token rotation을 유지하고 토큰을 로그·분석 도구·오류 메시지에 기록하지 않습니다.
- 현재 `signOut()` 계약은 유지합니다. JS 기본 scope는 `global`이므로 다중 기기 정책을 프론트와 확정한 뒤 `global` 또는 `local`을 명시합니다.
- 로그아웃 후에도 기존 access JWT는 만료까지 유효할 수 있습니다. 즉시 차단이 필요한 민감 작업만 `session_id`와 `auth.sessions` 검증을 별도 설계합니다.
- 브라우저 저장소 선택과 XSS 방어는 프론트엔드 보안 검토 대상입니다.

## Rate limit 운영

- 로그인/회원가입: 기본 IP당 5분 30회에서 시작
- token refresh: 기본 IP당 5분 150회에서 시작
- 이메일 발송: Custom SMTP 용량과 가입 예상량에 맞춰 별도 결정
- 429 응답을 정상 실패로 처리하고 무한 재시도하지 않음
- 프록시를 사용하는 경우 실제 사용자 IP 전달 정책을 검토하되 임의 헤더를 신뢰하지 않음

## 운영 전 결정 대기

- 이메일 확인 활성화 시점과 미확인 사용자의 UX
- SMTP 공급자·발신 도메인·비용 책임자
- 최소 비밀번호 조합과 비밀번호 재설정 UX
- 정상 로그아웃 scope 및 다중 기기 허용 정책
- production Site URL, callback URL, preview URL 범위
- 공개 회원가입 시작 시점과 CAPTCHA 도입 기준

공식 참고: [Password Security](https://supabase.com/docs/guides/auth/password-security), [User Sessions](https://supabase.com/docs/guides/auth/sessions), [Rate Limits](https://supabase.com/docs/guides/auth/rate-limits), [Redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls), [Signing Out](https://supabase.com/docs/guides/auth/signout)
