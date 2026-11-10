# A/B 기반 연동 계약

이 문서는 A 마이그레이션 뒤에 B의 밭·집중·수확 모델을 안전하게 연결하기 위한 확정 계약과 결정 대기 항목을 분리합니다. B 테이블이나 RPC를 구현하는 문서가 아닙니다.

## 1. A가 제공하는 데이터

### `public.profiles`

| 컬럼 | 타입 | 제약 |
|---|---|---|
| `id` | `UUID` | PK, `auth.users(id)` FK, `ON DELETE CASCADE` |
| `nickname` | `TEXT` | NOT NULL, 1~30자, 기본 `농부` |
| `timezone` | `TEXT` | NOT NULL, 1~64자, 기본 `Asia/Seoul` |
| `onboarded_at` | `TIMESTAMPTZ` | NULL 가능 |
| `created_at` | `TIMESTAMPTZ` | NOT NULL, DB 생성 시각 |

`profiles.id`는 사용자 소유권 FK의 기준입니다. B는 프로필을 직접 생성·수정·삭제하지 않습니다.

### `public.crops`

| 컬럼 | 타입 | 제약 |
|---|---|---|
| `id` | `UUID` | PK |
| `name` | `TEXT` | NOT NULL, UNIQUE |
| `target_seconds` | `INTEGER` | NOT NULL, `> 0` |
| `energy_level` | `TEXT` | `low | medium | high` |
| `sort_order` | `INTEGER` | NOT NULL, UNIQUE, `> 0` |
| `is_active` | `BOOLEAN` | NOT NULL |

| UUID | 작물 | 초 | 에너지 |
|---|---|---:|---|
| `10000000-0000-4000-8000-000000000001` | 새싹채소 | 600 | low |
| `10000000-0000-4000-8000-000000000002` | 당근 | 1200 | low |
| `10000000-0000-4000-8000-000000000003` | 딸기 | 1800 | medium |
| `10000000-0000-4000-8000-000000000004` | 옥수수 | 2700 | medium |
| `10000000-0000-4000-8000-000000000005` | 토마토 | 3600 | high |
| `10000000-0000-4000-8000-000000000006` | 호박 | 5400 | high |

B는 작물 ID, 목표 시간, 활성 여부를 직접 변경하지 않습니다. 카탈로그 변경은 A 마이그레이션으로만 진행합니다.

## 2. B 쓰기 모델의 확정 계약

- `farm_plots.id UUID`
- `farm_plots.user_id UUID` → `profiles.id`
- `farm_plots.plot_index`: 사용자별 1부터 시작하는 표시 번호
- `UNIQUE (user_id, plot_index)`
- `UNIQUE (user_id, id)`: 복합 소유권 FK 대상
- `focus_sessions.id UUID`
- `focus_sessions (user_id, plot_id)` → `farm_plots (user_id, id)`
- `focus_sessions.crop_id UUID` → `crops.id`
- `harvests.session_id` → `focus_sessions.id`, `UNIQUE (session_id)`
- 세션 상태: `focusing`, `paused`, `seed_saved`, `ripe`, `harvested`

`start_focus` 트랜잭션은 `crops.target_seconds`를 읽어 세션에 복사합니다. `target_seconds`, `focused_seconds`, `record_date`는 서버가 확정하며 클라이언트 입력을 신뢰하지 않습니다.

## 3. B가 참조할 A RPC

| RPC | 반환 필드 | 용도 |
|---|---|---|
| `get_my_profile()` | `nickname`, `timezone`, `onboarded`, `onboarded_at` | 사용자 시간대·온보딩 상태 |
| `complete_onboarding()` | `TIMESTAMPTZ` | 최초 온보딩 완료 시각; 멱등 |
| `list_crops(p_energy)` | `crop_id`, `name`, `target_seconds`, `recommended`, `sort_order` | 작물 선택·세션 목표 시간 기준 |

```js
const { data: crops, error } = await supabase.rpc('list_crops', { p_energy: 'medium' })
const cropId = crops[0].crop_id
await supabase.rpc('start_focus', { p_plot_id: plotId, p_crop_id: cropId })
```

`start_focus` 입력에 `target_seconds`를 추가하지 않습니다.

## 4. 마이그레이션 순서

1. A `20261110152140_a_foundation.sql`
2. B `farm_plots`
3. B `focus_sessions`
4. B `harvests`·휴식·알림
5. A 조회 RPC `get_my_farm()`, `get_focus_history(p_period)`
6. A/B 온보딩–`ensure_farm()` 통합 마이그레이션

B 마이그레이션은 A 커밋/마이그레이션에 의존함을 PR에 표시합니다. 이미 병합된 A 마이그레이션을 수정하지 않습니다.

## 5. A/B 통합 테스트

1. 회원가입 → 프로필 1개 생성 → `ensure_farm()` → 초기 밭 순서/소유권 검증
2. `list_crops()`의 `crop_id`로 `start_focus()` → DB 목표 초 복사 검증
3. 다른 사용자의 `plot_id`로 세션 시작 거부
4. 집중 상태 변경 → `get_my_farm()` 표시 상태 프로젝션 검증
5. 세션당 두 번 수확 경쟁 → 하나만 성공
6. 사용자 시간대 날짜 경계 전후 세션의 `record_date` 검증
7. 자동 수확과 수동 수확이 조회/집계에 중복 포함되지 않음을 검증

## 6. 결정 대기

| 항목 | 이유 | 결정 주체 |
|---|---|---|
| `ensure_farm()` 호출 시점·재시도 | 온보딩과 밭 생성의 트랜잭션 경계 미확정 | A/B/프론트엔드 |
| 세션 상태 전이·`INVALID_STATE` SQLSTATE | B 쓰기 모델 미구현 | A/B |
| 일시정지 구간 저장 방식 | `focused_seconds` 계산에 영향 | B |
| 자동 수확 알림 스키마 | `get_my_farm()` 반환 필드에 영향 | A/B/프론트엔드 |
| 기록 초기화의 물리/논리 삭제 | 후속 조회 동작에 영향 | A/B/기획 |
| 시간대 변경 정책 | 기존 `record_date` 재계산 여부 | A/기획 |

## 7. B 로컬 시작 절차

```bash
npm ci
npm run db:start
npm run db:reset
npm run db:test
npm run test:integration
```

`test:integration`이 로컬 Auth 계정을 고유 이메일로 생성하고 테스트 종료 시 삭제합니다. 공용 테스트 계정, 운영 계정, `service_role` 키를 준비할 필요가 없습니다. 상세 절차는 [A 기반 검증 런북](../runbooks/a-foundation-verification.md)을 따릅니다.

## 8. RLS·함수·Cron 권한 주의사항

- `authenticated`는 `profiles`, `crops` SELECT만 가집니다. B 테이블 쓰기는 직접 GRANT가 아닌 소유권을 검증하는 RPC로 제공합니다.
- A 테이블·RPC에는 `service_role` 명시 권한이 없습니다. 관리용 서비스 클라이언트가 정말 필요한 경우 A/B 공동 마이그레이션으로 특정 테이블 `SELECT` 또는 특정 함수 `EXECUTE`만 추가합니다.
- DB 내부 Supabase Cron은 `service_role` API 키를 사용하는 구조가 아닙니다. `pg_cron` job은 스케줄한 DB role로 실행되므로 `cron.job.username`과 대상 함수의 소유자/EXECUTE를 함께 검증합니다.
- `process_due_harvests()`에 definer가 필요하면 비공개 schema, 고정 `search_path`, 최소 EXECUTE, 멱등성과 동시성 테스트를 B 마이그레이션에 포함합니다.
- `private` schema를 `authenticated`/`service_role`에 전체 공개하지 않습니다. 필요한 내부 함수는 공개 RPC 또는 Cron 소유 함수에서만 호출합니다.
