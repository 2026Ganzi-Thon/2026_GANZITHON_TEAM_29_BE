# 데이터베이스 마이그레이션

## 순서

1. `20261110152140_a_foundation.sql`
   - `profiles`, `crops`
   - 회원가입 프로필 트리거
   - `get_my_profile()`, `complete_onboarding()`, `list_crops(p_energy)`
   - RLS, 명시적 `GRANT`/`REVOKE`
   - 기본 작물 6종과 안정 UUID
   - `PT401`/`PT404`/`22023` PostgREST 오류 매핑

2. `20261113012151_b_farm_foundation.sql`
   - `farm_plots`, 복합 소유권 제약, `ensure_farm()`
3. `20261113020509_b_focus_sessions.sql`
   - `focus_sessions`, 집중 시작·조회·일시정지·재개 RPC
4. `20261113143508_a_farm_read_model.sql`
   - 조회 전용 `get_my_farm()`
   - 기존 RLS를 적용하는 `SECURITY INVOKER`
   - 밭 생성·세션 상태 변경 없음

마이그레이션은 이 순서로 적용하며 `profiles.id`, `crops.id`, `crops.target_seconds`를 계약대로 사용합니다. `get_my_farm()`은 DB에 저장된 세션 상태만 투영하고 B의 상태를 변경하지 않습니다.

## 생성 규칙

```bash
npx supabase migration new <descriptive_name>
```

- 타임스탬프 파일명을 직접 만들지 않습니다.
- 병합된 마이그레이션은 수정하지 않고 새 파일로 변경합니다.
- 다른 마이그레이션에 의존하는 PR은 선행 PR을 기록합니다.
- 공통 타입, RLS, 권한, 마이그레이션 순서는 A/B 모두 리뷰합니다.

## 로컬 적용과 검증

```bash
npm run db:reset
npm run db:test
npm run test:integration
npm run db:lint
npm audit
```

`db:reset`은 로컬 DB를 재생성하므로 필요한 로컬 데이터를 미리 보존합니다. CLI v3에서 위 명령은 기본으로 로컬을 대상으로 하며 `--remote`를 사용하지 않습니다. `test:integration`은 publishable key만 사용하고 테스트 사용자를 정리합니다.

## B 의존성

- `farm_plots.user_id` → `profiles.id`
- `focus_sessions.crop_id` → `crops.id`
- `start_focus` 시 `crops.target_seconds`를 세션에 복사
- 복합 소유권 FK와 수확 멱등성은 [RPC 계약](../api/rpc-contracts.md)을 따름
- `ensure_farm()`과 `complete_onboarding()` 연결은 B 마이그레이션 병합 후 공동 마이그레이션으로 처리
- B/Cron에 필요한 `service_role` 권한은 새 객체에 명시적으로만 `GRANT`; A 테이블/RPC에는 기본 권한 없음
