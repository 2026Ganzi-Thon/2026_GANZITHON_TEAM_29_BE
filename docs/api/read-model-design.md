# 농장·집중 기록 조회 설계

이 문서는 B 쓰기 모델 병합 전의 후속 설계입니다. SQL, 정확한 반환 타입, 자동 수확 알림 필드는 확정하지 않습니다. Figma v1.2 원본은 이 저장소에서 확인할 수 없어, 명시된 `today | week | all` 요구만 반영했습니다.

## `get_my_farm()`

### 확정 동작

- 인증 사용자의 밭만 `plot_index ASC`로 조회
- 조회 전용: 밭 생성은 `ensure_farm()` 담당
- `focusing | paused` → `growing`
- `seed_saved` → `empty`
- `ripe` → `ripe`
- `harvested` → `harvested`
- 밭이 있지만 세션이 없으면 `empty`
- 사용자 ID는 입력받지 않고 `auth.uid()`로 소유권 확인
- 밭이 0개이면 빈 배열 반환; 조회 중 `ensure_farm()` 호출 금지

### 반환 권장안—미확정

```json
[
  {
    "plot_id": "uuid",
    "plot_index": 1,
    "farm_status": "growing",
    "session_id": "uuid",
    "session_status": "paused",
    "crop_id": "uuid",
    "crop_name": "당근",
    "target_seconds": 1200,
    "focused_seconds": 430,
    "pending_auto_harvest_id": null
  }
]
```

`empty`인 밭의 세션/작물/시간 필드는 `NULL` 권장입니다. `pending_auto_harvest_id`의 실제 이름과 원본 테이블은 B 알림 스키마 후 확정합니다.

### 활성 세션 포함 위치

| 안 | 장점 | 단점 |
|---|---|---|
| `get_my_farm()`에 표시용 세션 포함 | 농장 화면 1회 호출, 밭과 세션 스냅샷 일관성 | 타이머 갱신 응답이 커짐 |
| `get_active_focus()`에만 포함 | 집중 상태 책임 분리, 타이머 갱신 단순 | 농장 화면이 2회 호출·합치 필요 |

권장은 `get_my_farm()`에 렌더링용 `session_id`, `session_status`, 확정 시간만 포함하고, 제어·실시간 타이머의 권위 응답은 `get_active_focus()`로 두는 방식입니다. 최종 결정은 A/B/프론트엔드 담당입니다.

### 테스트 계획

- 밭 0개, 초기 빈 밭, 각 세션 상태 프로젝션
- `plot_index` 순서와 확장 밭
- 다른 사용자의 밭/세션 노출 차단
- 세션·수확 JOIN으로 밭이 중복 반환되지 않음
- 보류 알림 있음/없음

## `get_focus_history(p_period)` — 구현됨, 수확 집계 PARTIAL

### 입력과 기간

| 값 | 범위 |
|---|---|
| `today` | `profiles.timezone`의 현재 날짜 1일, 빈 날짜도 한 항목 반환 |
| `week` | 사용자 시간대의 월요일~일요일 7일, 빈 날짜도 0으로 반환 |
| `all` | 확정 기록의 최초~최종 `record_date`, 기록이 있는 날짜만 반환 |

양 끝 날짜는 모두 포함합니다. `record_date`는 B가 세션 시작 시 사용자 시간대로 확정하므로 조회 시 UTC 시각으로 재변환하지 않습니다. `seed_saved | ripe | harvested`만 확정 기록으로 집계하고 `focusing | paused`는 제외합니다.

### 확정 반환 계약

```json
{
  "period": "week",
  "range": { "start_date": "2026-11-09", "end_date": "2026-11-15", "timezone": "Asia/Seoul" },
  "summary": { "focused_seconds": 7200, "seed_count": 1, "harvest_count": null },
  "items": [
    { "record_date": "2026-11-09", "focused_seconds": 1800, "seed_count": 0, "harvest_count": null }
  ],
  "capabilities": { "harvest_count": false }
}
```

- `focused_seconds`: 확정 세션의 초 합계이며 0초 기록도 유지
- `seed_count`: `seed_saved` 세션 수
- `harvest_count`: `harvests`가 아직 없으므로 정상값처럼 0을 반환하지 않고 `null`
- `capabilities.harvest_count`: 현재 `false`; B 수확 스키마 연동 후에만 `true`
- `all` 빈 결과: `range.start_date/end_date = null`, 0 요약, 빈 `items`
- 다른 사용자 행은 `auth.uid()` 필터와 `focus_sessions` RLS로 이중 격리
- 함수는 `STABLE SECURITY INVOKER`, 빈 `search_path`, 조회 전용

### 결정 대기

- Figma v1.2의 실제 필드·그룹·정렬 확인: 프론트엔드/기획
- 수확 집계의 원본 테이블·완료 시각·자동 수확 귀속일: B/기획
- `reset_farm_history()`의 물리 삭제, 논리 삭제, 복구 규칙: B/기획
- 시간대 변경 시 기존 `record_date` 보존 여부: A/기획
- 일별 합계가 아닌 원시 세션 상세가 화면에 필요한지: 프론트엔드/A
- 장기 사용 시 `focus_sessions(user_id, record_date)` 인덱스 추가: B/A 공동 마이그레이션 검토

### 테스트 계획

- pgTAP: 오늘/주간/전체, 월요일~일요일, 연도 경계 fixture, 0초, 빈 기록, 권한, 격리
- Supabase JS: 실제 Auth 사용자, RPC JSON, 비정상 입력, 익명 차단, 사용자 격리
- 수확 테이블 연동과 자동 수확은 B 스키마 병합 후 별도 테스트 추가
