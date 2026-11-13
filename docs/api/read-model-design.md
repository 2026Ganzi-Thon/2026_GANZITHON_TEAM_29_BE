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

## `get_focus_history(p_period)`

### 입력과 기간

| 값 | 범위 |
|---|---|
| `today` | `profiles.timezone`의 현재 날짜 00:00 이상, 다음 날 00:00 미만 |
| `week` | 사용자 시간대의 월요일 00:00 이상, 다음 월요일 00:00 미만 |
| `all` | 전체 `record_date`, 월별 오름차순 집계 권장 |

경계는 사용자 시간대에서 계산한 `[start, end)`를 UTC 시각으로 변환합니다. `record_date`는 세션 시작 시점에 서버가 확정하고 후속 수확 시각으로 바꾸지 않습니다.

### 반환 권장안—미확정

기존 RPC 하나를 유지하므로 안정적 외피를 권장합니다.

```json
{
  "period": "week",
  "range": { "start_date": "2026-11-09", "end_date": "2026-11-15", "timezone": "Asia/Seoul" },
  "summary": { "focused_seconds": 7200, "seed_count": 1, "harvest_count": 2 },
  "items": [
    { "record_date": "2026-11-09", "focused_seconds": 1800, "seed_count": 0, "harvest_count": 1 }
  ]
}
```

- `today`: 세션/작물 기록 목록을 시작 시각 내림차순으로 보여줄지 `TBD`
- `week`: 7일 집계, 기록 없는 날짜 0 포함 권장
- `all`: 월별 집계; 오래된 원시 기록은 cursor pagination 권장
- 씨앗 보관과 수확은 각각 계수하되 `focused_seconds`는 세션당 한 번만 합산
- `harvests.session_id UNIQUE`를 사용하고, JOIN 전 세션/수확을 각각 집계해 중복 합산 방지
- 자동 수확은 수확 처리일이 아닌 원래 세션 `record_date`에 속하는 권장
- 빈 결과는 0 요약과 빈 `items`

### 결정 대기

- Figma v1.2의 실제 필드·그룹·정렬 확인: 프론트엔드/기획
- `seed_saved`를 집중 시간 합계에 포함할지: 기획/A/B
- `reset_farm_history()`의 물리 삭제, 논리 삭제, 복구 규칙: B/기획
- 시간대 변경 시 기존 `record_date` 보존 여부: A/기획
- `today` 원시 목록 pagination 임계값: 프론트엔드/A

### 테스트 계획

- UTC 오프셋 양/음수, 일요일→월요일, 월/연도 경계
- 세션 시작일과 수확일이 다른 경우
- 씨앗/수확/자동 수확, 하나의 세션에 수확 1개
- 빈 기록, 다른 사용자 격리, 초기화 후 조회
- 동일 세션과 수확 JOIN 시 `focused_seconds` 중복 없음
