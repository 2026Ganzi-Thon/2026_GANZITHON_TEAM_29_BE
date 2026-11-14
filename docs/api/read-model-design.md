# 농장·집중 기록 조회 설계

현재 \`develop\`의 \`farm_plots\`, \`focus_sessions\`, \`crops\`를 기준으로 A 조회 모델을 정의합니다. S02/S03 원본 화면 명세와 자동 수확 알림 스키마는 저장소에서 확인할 수 없어 의존 필드를 반환하지 않습니다.

## \`get_my_farm()\`

### 확정 동작과 보안

- 인증 사용자의 밭만 \`plot_index ASC\`로 조회
- 조회 전용이며 밭 생성은 B의 \`ensure_farm()\` 담당
- \`focusing | paused → growing\`
- \`seed_saved → empty\`
- \`ripe → ripe\`
- \`harvested → empty\`
- 점유 세션이 없으면 \`empty\`
- 밭이 0개이면 빈 배열을 반환하고 밭을 생성하지 않음
- 사용자 ID 입력 없이 \`auth.uid()\`로 소유권 확인
- \`STABLE SECURITY INVOKER\`와 기존 RLS 사용
- 테이블 쓰기와 세션 상태 확정 없음
- \`anon\`, \`service_role\` 실행 권한 없음

### 반환 계약

Supabase RPC는 다음 행 배열을 JSON으로 반환합니다.

~~~json
[
  {
    "plot_id": "uuid",
    "plot_index": 1,
    "farm_status": "growing",
    "session_id": "uuid",
    "session_status": "paused",
    "crop_id": "uuid",
    "crop_name": "당근",
    "target_seconds": 1200
  }
]
~~~

\`empty\` 밭의 세션·작물·목표 시간 필드는 \`NULL\`입니다. \`target_seconds\`는 세션 시작 당시 복사된 값입니다.

### JOIN과 책임 경계

- \`farm_plots\`를 기준으로 현재 밭을 점유하는 \`focusing\`, \`paused\`, \`ripe\` 세션만 LEFT JOIN
- 복합 소유권 \`(user_id, plot_id)\`를 함께 검사
- \`crops\`에서는 표시용 이름만 조회
- \`seed_saved\`, \`harvested\`는 기록으로 남지만 밭을 점유하지 않으므로 JOIN에서 제외
- 실시간 \`focused_seconds\`, \`remaining_seconds\`는 \`get_active_focus()\`를 권위 응답으로 사용
- B가 아직 자동 \`ripe\`/\`seed_saved\` 상태 확정을 구현하지 않았으므로 DB에 저장된 상태만 투영
- 자동 수확 알림 ID는 원본 테이블과 ack 규칙 확정 후 별도 후속 마이그레이션으로 추가

### 테스트

- 밭 0개 조회가 빈 배열이며 생성 부작용 없음
- 초기 12칸, 정렬과 빈 밭
- focusing/paused/ripe/harvested/seed_saved 상태 투영과 비점유 행의 NULL 필드
- 여러 과거 harvested 세션이 있어도 밭당 한 행
- 작물 ID·이름과 세션 목표 시간
- 다른 사용자 격리와 익명 차단
- JOIN으로 밭 중복 없음
- 함수가 B 세션 상태를 변경하지 않음

`20261114054245_b_finalize_focus.sql`부터 `focus_sessions_one_occupant`와 `start_focus()`는 `harvested`를 점유에서 제외합니다. 수확 기록은 보존하면서 같은 밭에 새 세션을 시작할 수 있습니다.

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
