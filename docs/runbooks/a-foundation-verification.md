# A 기반 검증 런북

이 절차는 로컬 Supabase에만 적용합니다. `--remote`, `supabase link`, 운영 키를 사용하지 않습니다.

## 전체 검증

```bash
npm ci
npx supabase --version
npm run db:start
npm run db:reset
npm run db:test
npm run test:integration
npm run db:lint
npx supabase db advisors --type all --level info --fail-on error
npm audit
```

`test:integration`은 `@supabase/supabase-js`와 publishable key로 실제 로컬 Auth/Data API를 호출합니다. 프로필 없음 재현과 정리에만 로컬 DB 컨테이너의 `postgres` 연결을 사용하며 `service_role` 키는 사용하지 않습니다. 테스트 사용자는 `finally`에서 삭제됩니다. 실패 후 정리 여부가 불확실하면 `npm run db:reset`을 실행합니다.

## 권한 검증 요점

- `profiles`, `crops`: RLS 활성
- `authenticated`: 두 테이블 SELECT만, 쓰기/삭제 없음
- `anon`, `service_role`: 두 테이블 명시 권한 없음
- `authenticated`: 세 public RPC EXECUTE
- `anon`, `service_role`: 세 public RPC EXECUTE 없음
- `private.handle_new_user()`: 외부 역할 EXECUTE 없음
- `get_my_profile`, `list_crops`: invoker
- `complete_onboarding`, `handle_new_user`: 필요한 definer, `search_path = ''`, `auth.uid()`/스키마 명시

## GitHub Actions

`.github/workflows/backend-ci.yml`은 `develop`/`main` 대상 PR과 수동 실행에서 동작합니다. 권한은 `contents: read`만 사용하고, 운영 Secret과 원격 Supabase를 참조하지 않습니다. 로컬 키가 로그에 표시되지 않도록 `supabase start` stdout을 숨기고, `if: always()` 정리 단계에서 임시 볼륨을 삭제합니다.

## PR 설명 초안

### 범위

- Auth 회원가입 프로필 자동 생성
- `profiles`, `crops`, 고정 작물 6종
- `get_my_profile()`, `complete_onboarding()`, `list_crops(p_energy)`
- RLS, 명시적 GRANT/REVOKE, 표준 오류 계약
- pgTAP과 실제 Auth/RPC 통합 테스트
- A/B FK·마이그레이션 연동 계약

### 리뷰 요청

- B: `profiles.id`, `crops.id`, `crops.target_seconds`, 복합 소유권 FK
- 프론트엔드: RPC 반환 형식과 오류 `message` 정규화
- A/B: `ensure_farm()` 연결 경계, `INVALID_STATE`, 조회 모델 TBD

### 제외

B 테이블/RPC, Cron, `get_my_farm()`, `get_focus_history()`, 원격 Supabase 배포는 포함하지 않습니다.
