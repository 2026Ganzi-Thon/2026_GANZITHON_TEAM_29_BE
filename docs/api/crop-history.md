# 작물별 집중 및 수확 기록 — get_crop_history

Issue: [#31](https://github.com/2026Ganzi-Thon/2026_GANZITHON_TEAM_29_BE/issues/31).
현재 검증 상태: **VERIFIED_LOCAL_ONLY / 원격 배포 PENDING**.
마이그레이션: `20261118132003_a_crop_history.sql` (Supabase CLI 3.1.0 생성).

## 요청과 화면 연결

POST `/rest/v1/rpc/get_crop_history`, Supabase Auth JWT, Content-Type application/json.
필수 입력은 `{"p_period":"today"}`이며 `today`, `week`, `all`만 허용한다.
사용자 ID는 받지 않는다. 이메일 확인 OFF 환경에서 로그인한 세션을 사용한다.

```js
const today = await supabase.rpc('get_crop_history', { p_period: 'today' })
const week = await supabase.rpc('get_crop_history', { p_period: 'week' })
const all = await supabase.rpc('get_crop_history', { p_period: 'all' })
// 각 호출의 error를 기존 normalizeBackendError로 처리한다.
```

| 화면 | 응답 필드 |
| --- | --- |
| S14 오늘 작물별 기록 | `crop_totals` |
| S15 이번 주 요일별 작물 기록 | `items[].crops` |
| S15-1 전체 월별 작물 기록 | `monthly[].crops` |
| S15-1 누적 작물 기록 | `crop_totals` |

최상위 필드는 정확히 `period`, `summary`, `items`, `monthly`, `crop_totals` 5개다.
기존 `get_focus_history()`의 range/capabilities/items.seed_count는 새 API에 추가하지 않는다.
새 API의 summary만으로 집중 시간·수확·씨앗 총합을 표시할 수 있으므로, 같은 화면에서
총합만 얻기 위해 두 API를 중복 호출할 필요는 없다. 기존 API는 그대로 지원한다.

## 성공 응답 구조

```json
{
  "period": "today",
  "summary": {"focused_seconds": 150, "harvest_count": 3, "seed_count": 2},
  "items": [{
    "record_date": "2026-11-18", "focused_seconds": 150, "harvest_count": 3,
    "crops": [
      {"crop_id":"10000000-0000-4000-8000-000000000001","crop_name":"새싹채소","focused_seconds":0,"harvest_count":0},
      {"crop_id":"10000000-0000-4000-8000-000000000002","crop_name":"당근","focused_seconds":150,"harvest_count":3}
    ]
  }],
  "monthly": [],
  "crop_totals": [
    {"crop_id":"10000000-0000-4000-8000-000000000001","crop_name":"새싹채소","focused_seconds":0,"harvest_count":0},
    {"crop_id":"10000000-0000-4000-8000-000000000002","crop_name":"당근","focused_seconds":150,"harvest_count":3}
  ]
}
```

위 값은 로컬 SDK fixture의 실제 응답이다. week도 같은 5개 필드를 반환하며 날짜 7개,
monthly는 빈 배열이다. all은 기록 날짜만 items에, 기록 월만 monthly에 포함한다.
월별 항목은 `{month:"YYYY-MM",focused_seconds,harvest_count,crops:[...]}`다.
기간별 전체 실제 응답은 [실측 예제 JSON](crop-history-examples.json)을 따른다.

문자열: period, record_date(YYYY-MM-DD), month(YYYY-MM), crop_id(UUID), crop_name.
집계는 JSON number 정수이며 내부 합계는 bigint다. 숫자 null/문자열과 배열 null을 반환하지 않는다.
JS Number의 안전 정수 상한(2^53-1)을 넘는 데이터는 별도 클라이언트 계약이 필요하다.

## 날짜·집계·정렬·빈 데이터

- 오늘/이번 주는 `profiles.timezone` 기준, 이번 주는 월~일이다.
- 귀속일은 `focus_sessions.record_date`: 수확 완료일이 아닌 집중 시작일.
- 시간대 변경은 조회 기간의 경계만 바꾸며 저장된 record_date를 재작성하지 않는다.
- 확정 상태 seed_saved/ripe/harvested의 focused_seconds 합산. focusing/paused 제외.
- 실제 harvests 행(수동/자동 모두)만 수확으로 집계. session_id UNIQUE로 중복 합산 방지.
- 씨앗은 seed_saved 세션 수이며 0초도 포함. 0초 기록이 있는 작물도 표시.
- 비활성 작물의 과거 기록도 이름·정렬 순서와 함께 유지.
- items 날짜 오름차순, monthly 연도-월 내림차순, 각 crops/crop_totals는 sort_order 후 UUID.
- 빈 today: 날짜 1개, 빈 week: 날짜 7개, 합계 0/crops=[].
- 빈 all: summary 세 값 0, items/monthly/crop_totals 모두 [].
- today/week의 monthly는 항상 []. 기록 없는 작물을 전체 6종으로 채우지 않는다.
- 날짜·작물·월별 합계와 summary는 일치한다. 기존 API와 같은 스냅샷이면 summary도 같다.
  서로 다른 HTTP 요청 사이에 수확/초기화가 일어나면 스냅샷 차이는 가능하다.

## 오류

| 상황 | HTTP | code | message |
| --- | --- | --- | --- |
| anon(함수 권한 없음) | 401 | 42501 | permission denied for function get_crop_history |
| authenticated 역할이지만 auth.uid 없음 | 401 | PT401 | UNAUTHENTICATED |
| null/빈 문자열/잘못된 값/대소문자 | 400 | 22023 | INVALID_INPUT |
| 프로필 없음 | 404 | PT404 | NOT_FOUND |

PostgREST 오류 객체는 code/message/details/hint를 포함한다.
`p_period` 키를 아예 생략하면 함수 시그니처 매칭 실패가 될 수 있으므로 반드시 전달한다.
기타 오류를 성공 응답으로 감싸지 않는다. 프론트는 기존 오류 정규화·로딩·재시도 정책을 따른다.
조회는 재시도 가능하지만 성공 빈 배열을 오류로 간주하지 않는다.

## 승인된 보안 설계와 기존 RPC 영향

SECURITY INVOKER/STABLE/search_path=''/timezone=UTC. 입력 인증은 auth.uid()만 사용한다.
EXECUTE는 authenticated만 허용하고 PUBLIC/anon/service_role을 명시적으로 제거한다.
기존 crops_select_active는 유지하고, Issue #31 사용자 승인으로 **본인 확정 세션이 참조하는
비활성 작물**의 SELECT만 추가한다. 쓰기 권한·다른 테이블 GRANT는 바꾸지 않는다.

직접 테이블 SELECT에도 같은 추가 가시성이 적용되며 기존 허용 열 모두를 읽을 수 있다.
다른 사용자·미참조·진행/일시정지만 있는 비활성 작물은 보이지 않는다.
reset_farm_history로 마지막 확정 참조가 사라지면 즉시 가시성도 사라진다.
정책 의존성은 crops → focus_sessions → auth.uid이며, focus_sessions 정책은 crops를
참조하지 않으므로 순환 참조하지 않는다.

- list_crops: 명시적 `c.is_active` 필터로 계속 활성 작물만 반환.
- start_focus: 명시적 활성 검사로 비활성 작물 심기 계속 거부.
- get_my_farm: 기존 LEFT JOIN 유지. 본인 ripe 비활성 작물의 메타데이터를 읽을 수 있게 된다.
  focusing/paused만으로는 권한을 얻지 않는다. 기존 null 가능성이 있어 프론트는 null 안전 처리 유지.
- get_focus_history: 함수 본문/권한/응답과 테스트 모두 변경 없음. crops 조인이 없어 합계 유지.
- B 수확/종료/휴식/Cron은 변경하지 않는다. 작물 FK 및 UNIQUE도 그대로다.

## QA 및 성능

기존 pgTAP 343개를 유지했다. 신규 76개 테스트는 인증/입력/기간/집계/정렬/타입/0초/비활성/RLS/
초기화/읽기 불변/시간대/32-bit 초과 합계 및 기존 summary 일치를 검사한다.
SDK 테스트는 실제 signUp/signInWithPassword/getSession/signOut과 RPC/직접 SELECT를 사용한다.
로컬 pgTAP 결과는 기존 343 + 신규 76 = **419/419 PASS**다.
기존 Auth/RPC·History·Farm reset SDK, 신규 Crop history SDK, DB lint 및 npm audit(취약점 0)도 통과했다.
신규 SDK의 비활성 RLS 검증은 별도 비활성 테스트 작물 5개만 만들고 기존 6종은 변경하지 않는다.
테스트 계정을 로그아웃·삭제한 뒤 이 작물도 정확한 UUID/이름 조건으로 제거하고 잔여 0건을 확인한다.

로컬 재현 명령:

```sh
npm ci
npm run db:reset
npm run db:test
npm run test:integration
npm run test:history
npm run test:reset
npm run test:crop-history
npm run db:lint
npm audit
node scripts/benchmark-crop-history.mjs
```

`db:reset`은 로컬 검증 DB에만 사용한다. benchmark는 전체 트랜잭션을 ROLLBACK한다.
새 필터를 한 번 materialize하고 날짜×작물 집계를 재사용한다. 신규 인덱스는 추가하지 않았다.
기존 `focus_sessions_streak_history`의 본인 확정 기록 인덱스와 PK를 사용하는 JOIN 계획을 확인했다.

| 로컬 all 조회 조건 | 함수 실행 ms | JSON bytes |
| --- | ---: | ---: |
| 빈 사용자 | 1.150 | 136 |
| 12 세션 | 0.534 | 2,982 |
| 10,000 세션/28일 | 4.449 | 6,734 |
| 10,000 세션/1,825일/61개월 | 12.958 | 399,673 |
| 본인 12 세션 + 타 사용자 100,000 세션 | 1.215 | 2,982 |

단일 로컬 측정이며 네트워크·동시 부하·호스팅 성능 보장은 아니다. 모든 측정은 타 사용자
100,000 세션 fixture와 비활성 작물 정책이 있는 상태에서 수행했다. 전체 함수 EXPLAIN ANALYZE와
공통 JOIN의 별도 실행 계획을 기록했다. 장기 all은 무제한이며 기록을 자르지 않는다.
응답 크기/지연이 커지면 기간 필터·페이지네이션을 별도 계약으로 확정해야 한다.

## 화면/외부 문서 확인 및 한계

Figma node 63:1848의 메타데이터에서 S14/S15/S15-1 기록 화면과 씨앗 표시를 확인했다.
픽셀 단위 화면 검수나 프론트 구현은 수행하지 않았다.
Notion 링크는 접근 불가였으므로 이 문서를 붙여넣기용 API 명세로 사용할 수 있다.

현재 crop별 focused_seconds는 씨앗 보관·수확 대기·수확 완료 시간을 합친다.
summary.seed_count만으로 작물별 씨앗 시간/횟수를 분리할 수 없다.
S14에서 이를 별도 표시하려면 팀 합의 후 seed_focused_seconds 등의 계약을 추가해야 한다.
이번 작업에서는 응답 필드를 늘리지 않았다.
