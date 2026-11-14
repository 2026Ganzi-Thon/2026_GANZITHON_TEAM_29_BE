# Auth 운영 정책

## 최종 결정

- 이메일 주소를 로그인 ID로 사용
- Supabase Auth 이메일/비밀번호 가입·로그인
- 신규 회원가입 허용
- 회원가입 시 \`options.data.nickname\` metadata 전달
- Confirm email OFF
- 이메일 인증 링크 없이 가입
- 별도 Spring Boot Auth 서버 없음

\`nickname\`은 표시 정보이며 권한 판단에 사용하지 않습니다. 소유권은 \`auth.uid()\`, UUID FK와 RLS로 검증합니다.

## 환경 상태

| 항목 | LOCAL | STAGING | PRODUCTION 정책 |
|---|---|---|---|
| 이메일/비밀번호 | 활성 | 활성 | 활성 |
| 신규 가입 | 허용 | 허용 | 허용 |
| Confirm email | OFF | Dashboard 저장 완료 | OFF |
| nickname metadata | 사용 | 사용 예정 | 사용 |
| 원격 실측 | 해당 없음 | 미실행 | 미실행 |
| 익명 로그인 | 비활성 | 비활성 유지 | 비활성 유지 |

Staging Dashboard 저장은 사용자 확인 사항입니다. 원격 Auth 사용자를 만들지 않았으므로 가입 직후 세션 발급은 아직 실측 PASS가 아닙니다.

## 호출 계약

~~~js
await supabase.auth.signUp({
  email,
  password,
  options: { data: { nickname } },
})
await supabase.auth.signInWithPassword({ email, password })
await supabase.auth.getSession()
await supabase.auth.signOut()
~~~

회원가입 트리거는 nickname을 최대 30자로 정규화해 프로필에 복사합니다. 사용자 수정 가능한 metadata는 역할이나 권한 결정에 사용하지 않습니다.

## 남은 운영 결정

Confirm email OFF는 확정 사항이며 결정 대기가 아닙니다. 아래 항목만 별도로 확정합니다.

- 최소 비밀번호 길이와 조합
- JWT 만료와 refresh token 정책
- Site URL과 환경별 Redirect URL
- rate limit과 CAPTCHA 도입 기준
- 로그아웃 scope와 다중 기기 정책
- 비밀번호 재설정·이메일 주소 변경 UX
- Staging 원격 회원가입 스모크 테스트 승인

Redirect URL에는 불필요하게 광범위한 \`**\` 패턴을 사용하지 않습니다. 토큰과 Auth 오류 본문은 로그에 남기지 않습니다.

공식 참고: [Password Security](https://supabase.com/docs/guides/auth/password-security), [User Sessions](https://supabase.com/docs/guides/auth/sessions), [Rate Limits](https://supabase.com/docs/guides/auth/rate-limits), [Redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls), [Signing Out](https://supabase.com/docs/guides/auth/signout)
