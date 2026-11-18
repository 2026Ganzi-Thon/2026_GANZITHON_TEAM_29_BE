# 기록 API 작물별 성장·씨앗 집계 보강

상태: **VERIFIED_LOCAL_ONLY / Staging 신규 배포 PENDING**.
Issue [#35](https://github.com/2026Ganzi-Thon/2026_GANZITHON_TEAM_29_BE/issues/35).
신규 migration: `20261118135436_a_history_crop_counts.sql` (CLI 3.1.0 생성).

## 확정 계약

두 API 모두 POST `/rest/v1/rpc/<함수명>`, Auth JWT, 필수 `{ "p_period": "today" }`를 사용한다.
입력은 `today | week | all`, 사용자 ID는 받지 않는다.

| 필드 | 집계 의미 |
| --- | --- |
| focused_seconds | seed_saved + ripe + harvested의 확정 집중 초 |
| grown_count | ripe + harvested 세션 수. 실제 수확 전 ripe도 포함 |
| seed_count | seed_saved 세션 수. 0초 씨앗도 포함 |
| harvest_count | 실제 harvests 행 수. 수동/자동 포함, ripe 자체는 수확 아님 |

focusing/paused는 모두 제외한다. record_date, profiles.timezone, 주간 월~일 7일,
일자 오름차순/월 내림차순, 작물 sort_order 후 crop_id 정렬, 비활성 과거 기록 정책은 그대로다.
세션당 harvests UNIQUE를 유지해 JOIN 중복 합산을 방지한다.

### get_focus_history(p_period)

최상위 `period/range/summary/items/capabilities`, 기존 일별
`record_date/focused_seconds/seed_count/harvest_count`는 값·타입·의미를 유지한다.
각 items 항목에 **crops만** 추가한다. 각 작물 객체는 아래 5개 필드다.

```json
{
  "crop_id": "10000000-0000-4000-8000-000000000002",
  "crop_name": "당근",
  "focused_seconds": 150,
  "grown_count": 4,
  "seed_count": 1
}
```

기록 없는 날짜는 crops=[]다. all의 빈 items=[] 및 range 날짜 null도 그대로다.
기존 summary에 grown_count를 추가하지 않는다. 날짜별 harvest_count도 계속 실제 수확 횟수다.

### get_crop_history(p_period)

최상위 5개 `period/summary/items/monthly/crop_totals`를 유지한다.
`items[].crops`, `monthly[].crops`, `crop_totals`의 각 객체에
**grown_count, seed_count 두 필드만** 추가한다. 기존 harvest_count는 그대로 남는다.

```json
{
  "crop_id": "10000000-0000-4000-8000-000000000002",
  "crop_name": "당근",
  "focused_seconds": 150,
  "harvest_count": 3,
  "grown_count": 4,
  "seed_count": 1
}
```

성장 완료 4회와 실제 수확 3회는 서로 다른 정상 값이다. `grown_count`로 수확 횟수를 대체하지 않는다.
추가 숫자는 JSON number 정수이며 0을 null/문자열로 바꾸지 않는다. 내부 합계는 bigint다.
동일 스냅샷에서는 두 API의 일별 작물 객체가 crop API의 harvest_count를 제외하고 모두 일치한다.

## 호출·화면·오류

```js
const focus = await supabase.rpc('get_focus_history', { p_period: 'week' })
const crops = await supabase.rpc('get_crop_history', { p_period: 'all' })
```

기존 기록 화면을 유지하려면 focus.items[].crops를 사용한다.
월별·누적 작물 집계가 필요하면 crop.monthly[].crops와 crop.crop_totals를 사용한다.
두 API를 같은 날짜별 작물 목록 때문에 중복 호출할 필요는 없다.
로딩/빈 화면/이전 요청 폐기/오류 정규화·네트워크 1회 재시도 정책은 기존 가이드를 따른다.

기존 오류 유지: INVALID_INPUT(22023/HTTP400), NOT_FOUND(PT404/404),
JWT 없는 authenticated의 UNAUTHENTICATED(PT401/401), anon EXECUTE 차단(42501/401).
service_role 직접 실행도 계속 차단한다. 별도 Secret key를 프론트에 제공하지 않는다.

## 구현과 보안

신규 파일에서 두 함수만 CREATE OR REPLACE한다. PostgreSQL의 기존 owner/EXECUTE ACL을 유지하며
STABLE/SECURITY INVOKER/search_path=''/timezone=UTC를 명시한다.
RLS·테이블 권한·B 함수·Cron 함수/Job/스케줄은 변경하지 않는다.
Cron 운영 SQL의 정확 버전 목록에는 신규 버전만 추가한다.

get_crop_history의 materialized 필터와 날짜×작물 집계를 재사용해 grown/seed를 일·월·누적으로 합산한다.
get_focus_history는 이 RPC를 한 번 호출하고 JSON을 기존 형식으로 투영한다.
range.timezone을 위해 본인 프로필 1행만 추가 조회한다. 세션/수확 재집계 쿼리는 추가하지 않는다.
활성/비활성 작물 접근은 기존 승인된 crops 정책과 세션 소유권 RLS를 그대로 따른다.

## 검증

기존 419개 pgTAP을 보존했으며, 이전 작물 JSON 전체 기대값 한 곳에 승인된 두 키만 반영했다.
기존 필드 검증을 제거하지 않았다. 신규 전용 테스트는 기간·성장/씨앗/실수확 구분·동일 작물 합산·
자동/수동 수확·0초·비활성·격리·빈 날짜·7일·월별·읽기 전용·권한·초기화를 검사한다.
SDK 기존 History의 전체 JSON 기대값도 기존 값에 crops만 추가했다.
실제 pgTAP은 기존 419 + 신규 35 = **454/454 PASS**이며,
기존 Auth/RPC·History·reset 및 보강 Crop history SDK, DB lint, npm audit(취약점 0)도 통과했다.

SDK 로컬 호환성 시험은 **변경하지 않은 이전 migration 두 개의 함수 정의**를 pg_temp에 생성하고,
인증 역할로 today/week/all을 조회한다. 새 응답에서 승인된 추가 필드만 제거한 뒤 구버전 전체 JSON과
deepEqual로 비교하고 전체 임시 함수/권한을 ROLLBACK한다. 이 임시 DDL은 원격에서 실행하지 않는다.
Staging에서는 실제 Auth HTTP·SDK로 새 필드/두 API 일별 일치/격리/오류/초기화 및 정리를 검증한다.

로컬 기존 benchmark 재실행: 본인 10,000 세션/1,825일/61개월, 타 사용자 100,000 세션 공존 시
get_crop_history('all') 16.145ms / JSON 465,843 bytes. 기존 인덱스를 사용하며 새 인덱스는 없다.
단일 로컬 측정으로 운영 지연/동시 부하를 보장하지 않는다.

```sh
npm ci
npm run db:reset # 로컬 검증 DB만
npm run db:test
npm run test:integration
npm run test:history
npm run test:reset
npm run test:crop-history
npm run db:lint
npm audit
```

## 미포함 계약

focused_seconds는 씨앗과 성장 완료 시간을 합친다. grown_count/seed_count는 횟수이므로
씨앗/성장 완료의 **시간을 분리 표시할 수 없다**. 필요한 경우 seed_focused_seconds,
grown_focused_seconds를 후속 합의해야 한다. 이번에는 그 필드를 추가하지 않았다.
all 조회 페이지네이션 및 실제 프론트 UI 구현도 이번 범위에 포함하지 않는다.

## 프론트 공유용 메시지

> 기록 API에 작물별 grown_count(ripe+harvested 횟수), seed_count(seed_saved 횟수)를 추가했습니다.
> get_focus_history는 기존 일별 필드를 유지하고 items[].crops를 추가하며,
> get_crop_history는 일/월/누적 crops에 두 횟수를 추가합니다. 실제 수확은 기존 harvest_count입니다.
> 집중 초는 상태별로 분리되지 않으니 횟수로 시간 분리를 추정하지 말아 주세요.
> 실제 배포·검증 상태는 이 명세 상단을 확인해 주세요.
