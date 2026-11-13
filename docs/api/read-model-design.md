# 농장·집중 기록 조회 설계

현재 \`develop\`의 \`farm_plots\`, \`focus_sessions\`, \`crops\`를 기준으로 A 조회 모델을 정의합니다. S02/S03 원본 화면 명세와 자동 수확 알림 스키마는 저장소에서 확인할 수 없어 의존 필드를 반환하지 않습니다.

## \`get_my_farm()\`

### 확정 동작과 보안

- 인증 사용자의 밭만 \`plot_index ASC\`로 조회
- 조회 전용이며 밭 생성은 B의 \`ensure_farm()\` 담당
- \`focusing | paused → growing\`
- \`seed_saved → empty\`
- \`ripe → ripe\`
- \`harvested → harvested\`
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

- \`farm_plots\`를 기준으로 현재 밭을 점유하는 \`focusing\`, \`paused\`, \`ripe\`, \`harvested\` 세션만 LEFT JOIN
- 복합 소유권 \`(user_id, plot_id)\`를 함께 검사
- \`crops\`에서는 표시용 이름만 조회
- \`seed_saved\`는 기록으로 남지만 밭을 점유하지 않으므로 JOIN에서 제외
- 실시간 \`focused_seconds\`, \`remaining_seconds\`는 \`get_active_focus()\`를 권위 응답으로 사용
- B가 아직 자동 \`ripe\`/\`seed_saved\` 상태 확정을 구현하지 않았으므로 DB에 저장된 상태만 투영
- 자동 수확 알림 ID는 원본 테이블과 ack 규칙 확정 후 별도 후속 마이그레이션으로 추가

### 테스트

- 밭 0개 조회가 빈 배열이며 생성 부작용 없음
- 초기 12칸, 정렬과 빈 밭
- focusing/paused/ripe/harvested/seed_saved 상태 투영
- 작물 ID·이름과 세션 목표 시간
- 다른 사용자 격리와 익명 차단
- JOIN으로 밭 중복 없음
- 함수가 B 세션 상태를 변경하지 않음

## \`get_focus_history(p_period)\`

### 입력과 기간

| 값 | 범위 |
|---|---|
| \`today\` | 사용자 시간대의 현재 날짜 |
| \`week\` | 사용자 시간대의 월요일부터 일요일 |
| \`all\` | 전체 기록, 월별 집계 권장 |

경계는 사용자 시간대에서 계산한 \`[start, end)\`를 UTC로 변환합니다. \`record_date\`는 세션 시작 시 서버가 확정하며 수확 시각으로 바꾸지 않습니다.

### 반환 권장안—미확정

~~~json
{
  "period": "week",
  "range": {
    "start_date": "2026-11-09",
    "end_date": "2026-11-15",
    "timezone": "Asia/Seoul"
  },
  "summary": {
    "focused_seconds": 7200,
    "seed_count": 1,
    "harvest_count": 2
  },
  "items": []
}
~~~

- \`today\`: 원시 기록 목록과 정렬은 TBD
- \`week\`: 기록 없는 날짜를 포함한 7일 집계 권장
- \`all\`: 월별 집계와 pagination 권장
- 씨앗과 수확은 각각 계수하고 집중 시간은 세션당 한 번만 합산
- 빈 결과는 0 요약과 빈 items

### 결정 대기

- S02/S03 및 기록 화면의 실제 필드·그룹·정렬
- \`seed_saved\`의 집중 시간 합산 여부
- \`reset_farm_history()\` 삭제·복구 규칙
- 시간대 변경 시 기존 \`record_date\` 보존 여부
- 원시 기록 pagination 기준
