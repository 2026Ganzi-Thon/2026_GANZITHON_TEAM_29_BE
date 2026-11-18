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
   - 밭 생성·세션 상태 변경 없음; `seed_saved`, `harvested`는 비점유 기록
5. `20261113145323_a_focus_history.sql`
   - `get_focus_history(p_period)`
   - 집중 시간·씨앗 일별 집계; 수확 집계는 B `harvests` 병합 후 후속 마이그레이션
6. `20261114054245_b_finalize_focus.sql`
   - 목표 달성·24시간 일시정지 만료 자동 확정과 `finalize_my_focus()`
   - `harvested`를 점유에서 제외한 인덱스·`start_focus()` 계약
7. `20261114070324_b_stop_focus.sql`
   - 중도 종료 미리보기·확정·취소 RPC와 해시 토큰 저장소
   - 5분 TTL, 멱등 확인, 상태 전이 시 미리보기 무효화

8. `20261114072516_b_harvest.sql` — 수확·자동 수확·알림·timezone 검증
9. `20261115011444_a_focus_history_harvest_count.sql` — 실제 수확 집계
10. `20261115013511_b_save_harvest_note.sql` — 메모 기반
11. `20261115015534_b_start_rest.sql` — 수확 후 휴식
12. `20261115020000_b_harvest_note_guidance.sql` — 메모 안내
13. `20261115020500_b_focus_streak.sql` — 연속 집중·과로 안내
14. `20261115021000_b_overwork_precision.sql` — 안내 시간 정밀도
15. `20261118052002_b_reset_farm_history.sql` — S16 본인 활동 초기화, 계정·프로필·밭 보존
16. `20261118132003_a_crop_history.sql` — 작물별 집중·실제 수확 기록과 승인된 비활성 작물 SELECT 정책
17. `20261118135436_a_history_crop_counts.sql` — 두 기록 API의 작물별 성장·씨앗 횟수 확장(배포 상태는 보강 명세 참조)

Staging에는 16개가 적용됐습니다. get_crop_history 배포는 앞선 15개를 보존하고 신규 1개만 추가했습니다. Staging 전용 Cron Job은 일반 마이그레이션이 아닌 ops/staging에서 관리하며 가드는 정확한 16개 목록을 검사합니다. Cron Job 자체는 이번 배포에서 변경하지 않았습니다.

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
npm run test:history
npm run test:reset
npm run test:crop-history
npm run db:lint
npm audit
```

`db:reset`은 로컬 DB를 재생성하므로 필요한 로컬 데이터를 미리 보존합니다. CLI v3에서 위 명령은 기본으로 로컬을 대상으로 하며 `--remote`를 사용하지 않습니다. 통합 테스트는 publishable key만 사용하고 테스트 사용자를 정리합니다.

## B 의존성

작물별 기록 추가: `20261118132003_a_crop_history.sql`은 앞선 S16 마이그레이션 다음에 적용합니다.
신규 get_crop_history(text)와 승인된 crops_select_own_history SELECT 정책만 추가합니다.
기존 마이그레이션 및 get_focus_history는 수정하지 않습니다. `npm run test:crop-history`도 실행합니다.

- `farm_plots.user_id` → `profiles.id`
- `focus_sessions.crop_id` → `crops.id`
- `start_focus` 시 `crops.target_seconds`를 세션에 복사
- 복합 소유권 FK와 수확 멱등성은 [RPC 계약](../api/rpc-contracts.md)을 따름
- `ensure_farm()` 성공 후 `complete_onboarding()`을 호출하며, 실패 시 같은 순서로 멱등 재시도
- B/Cron에 필요한 `service_role` 권한은 새 객체에 명시적으로만 `GRANT`; A 테이블/RPC에는 기본 권한 없음
