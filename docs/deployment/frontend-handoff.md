# 집중농장 Staging 프론트엔드 인계

검증일: 2026-11-15 (Asia/Seoul). **Staging DB 배포 완료, 인증 사용자 E2E는 아직 미검증**입니다.

## 연결 정보

| 항목 | 실제 조회 값 |
|---|---|
| 환경 / 이름 | STAGING / focus-farm-staging |
| Project Ref | klanbfvywwudprunaqdf |
| 리전 / PostgreSQL | ap-northeast-2 / 17.11 (프로젝트 build 17.11.0.018) |
| Project URL | https://klanbfvywwudprunaqdf.supabase.co |
| REST API Base URL | https://klanbfvywwudprunaqdf.supabase.co/rest/v1 |
| Publishable key | `sb_publishable_BhYc2LCiC6QLv6bVUiyzlA_XP7sbz29` |
| 배포한 main SHA | `7471dddc028df1c87f2e33e93dbbae33b34b31f5` |
| Supabase CLI | 3.1.0 |

위 key는 이 프로젝트에서 조회한 브라우저용 공개 키입니다. Secret/service_role key, DB 비밀번호, access/refresh token은 프론트 환경변수·문서·로그에 넣지 않습니다. CLI의 `production` 출력은 해당 프로젝트의 기본 브랜치 분류이며 팀 환경은 STAGING입니다.

프론트 저장소와 빌드 도구는 이번 작업에서 확인되지 않았습니다. 다음은 **중립 변수명**이며 실제 빌드 도구의 공개 접두사는 프론트에서 적용합니다. Vite 사용이 확인된 경우에만 `VITE_`, Next.js인 경우에만 `NEXT_PUBLIC_` 등으로 변환합니다.

```dotenv
SUPABASE_URL=https://klanbfvywwudprunaqdf.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_BhYc2LCiC6QLv6bVUiyzlA_XP7sbz29
```

```js
import { createClient } from '@supabase/supabase-js'
// publicEnv는 빌드 도구에 맞게 읽은 공개 설정 객체입니다.
const supabase = createClient(publicEnv.SUPABASE_URL, publicEnv.SUPABASE_PUBLISHABLE_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
})

await supabase.auth.signUp({ email, password, options: { data: { nickname } } })
await supabase.auth.signInWithPassword({ email, password })
await supabase.auth.getSession()
await supabase.auth.signOut()
```

공개 Auth `/auth/v1/settings`에서 `external.email=true`, `disable_signup=false`, `mailer_autoconfirm=true`를 확인했습니다. 이메일/비밀번호 가입 허용, Confirm email OFF 정책과 일치합니다. 실제 signUp/signIn/getSession/signOut의 원격 사용자 성공 경로는 계정 생성 승인·테스트 계정 부재로 실행하지 않았습니다. `nickname` metadata는 표시용이며 권한 판단에 사용하지 않습니다.

## 실제 검증 범위

- `VERIFIED_REMOTE`: 원격에서 해당 검증을 실제 실행함.
- `VERIFIED_LOCAL_ONLY`: 성공 동작은 로컬에서 검증했으며 원격 인증 성공 경로는 미실행.
- `PENDING`: 구현·정책·예약 또는 승인이 남음.
- `FAILED`: 검증 실패. 이번 배포 명령·로컬 테스트·익명 차단 검사에는 없음.

**아래 모든 앱 RPC의 성공 동작은 VERIFIED_LOCAL_ONLY**입니다. 원격에서 함수·입력·반환 타입·권한은 확인했고 20개 함수의 익명 POST가 HTTP 401 / SQLSTATE 42501인 것은 VERIFIED_REMOTE입니다. 이것을 원격 인증 E2E 통과로 해석하지 않습니다.

## RPC 요청·응답

공통 호출: `const { data, error } = await supabase.rpc(name, args)`; 인자가 없으면 두 번째 인자를 생략합니다. 시각 문자열은 UTC ISO 형식이고 UUID는 문자열입니다. 아래 응답은 구현으로 확인한 구조 예시이며 원격 사용자 실측 응답이 아닙니다.

| RPC / 요청 JSON | 성공 응답 예시 또는 구조 | 화면 / 재시도 |
|---|---|---|
| `get_my_profile()` | `[{nickname:'농부',timezone:'Asia/Seoul',onboarded:false,onboarded_at:null}]` | S01 / 네트워크 1회 |
| `complete_onboarding()` | `'2026-11-15T12:00:00+00:00'` | S01 / 멱등 재시도 |
| `list_crops({p_energy:'low'})` | `[{crop_id:'uuid',name:'새싹채소',target_seconds:600,recommended:true,sort_order:1}, ...]` | S04/S05 / 네트워크 1회 |
| `get_my_farm()` | `[{plot_id:'uuid',plot_index:1,farm_status:'empty',session_id:null,session_status:null,crop_id:null,crop_name:null,target_seconds:null}, ...]` | S02/S03 / 네트워크 1회 |
| `get_focus_history({p_period:'week'})` | `{period,range:{start_date,end_date,timezone},summary:{focused_seconds,seed_count,harvest_count},items:[{record_date,focused_seconds,seed_count,harvest_count}],capabilities:{harvest_count:true}}` | S14/S15 / 네트워크 1회 |
| `ensure_farm()` | `[{plot_id:'uuid',plot_index:1}, ...]` 초기 12개 | S01 / 멱등 재시도 |
| `start_focus({p_plot_id:'uuid',p_crop_id:'uuid'})` | `{session_id,plot_id,crop_id,status:'focusing',started_at,target_seconds,server_now}` | 작물 선택 후 / 자동 재시도 금지, 활성 세션 먼저 복원 |
| `get_active_focus()` | `{session:null,server_now,show_overwork_notice:false}` 또는 아래 세션 객체 | 집중 화면 / 네트워크 1회 |
| `pause_focus({p_session_id:'uuid'})` | `{session_id,status:'paused',paused_at,remaining_seconds,server_now}` | 집중 화면 / 같은 ID 멱등 재시도; 상태 변동 시 재조회 |
| `resume_focus({p_session_id:'uuid'})` | `{session_id,status:'focusing',remaining_seconds,server_now}` | 집중 화면 / 같은 ID 멱등 재시도; 상태 변동 시 재조회 |
| `finalize_my_focus()` | `{session_id,status:'ripe',focused_seconds:600}` 또는 `seed_saved` 또는 `null` | 재접속·홈 진입 전 / 재시도 가능 |
| `preview_stop_focus({p_session_id:'uuid'})` | `{session_id,stop_token,previewed_at,expires_at,focused_seconds,focus_minutes,progress_percent,result:'seed'}` | S09 / 새 호출은 이전 토큰 교체, 자동 재시도 금지 |
| `confirm_stop_focus({p_stop_token:'token'})` | `{session_id,status:'seed_saved',result:'seed',focused_seconds,plot_status:'empty'}` | S09 / 동일 토큰 멱등 재시도 |
| `cancel_stop_focus({p_stop_token:'token'})` | `{session_id,cancelled:true}`; 이미 확정 시 `false` | S09 / 동일 토큰 재시도 가능 |
| `harvest_crop({p_session_id:'uuid'})` | `{harvest_id,session_id,plot_id,crop_id,focused_seconds,harvested_at,auto_harvested:false}` | S17 / 동일 ID 멱등 재시도 |
| `ack_auto_harvest_notice({p_harvest_ids:['uuid']})` | `{acknowledged_count:1}`; 반복 시 `0` | S03 / 표시한 ID만 멱등 재시도 |
| `save_harvest_note({p_harvest_id:'uuid',p_note:'오늘 집중 기록'})` | `{saved:true,guidance_required:false}` 또는 `{saved:false,guidance_required:true}` | S10 / 동일 내용 재시도 가능, 동시 편집 덮어쓰기 주의 |
| `start_rest({p_harvest_id:'uuid'})` | `{rest_ends_at,server_now}` | 수동 수확 후 / 동일 ID 멱등 재시도 |
| `claim_overwork_notice({p_session_id:'uuid'})` | `{show_overwork_notice:true}` 또는 `false` | 집중 화면 후보→S12 / 응답 유실 후 true 재전달 보장 없음 |

모든 앱 RPC는 로그인한 `authenticated` 사용자 전용입니다. 추가 DB 관리 함수 `process_due_harvests()`는 `{processed_count}`를 반환하지만 **anon/authenticated/service_role 모두 EXECUTE 없음**, DB 소유자의 관리 실행 전용입니다. 프론트에서 호출하지 않습니다. `reset_farm_history()`는 현재 배포에 없으며 PENDING입니다.

`get_active_focus().session`이 존재하면 `{session_id,plot_id,crop_id,status,started_at,paused_at,target_seconds,focused_seconds,remaining_seconds}`입니다. 목표에 도달하거나 일시정지 24시간 만료 시 조회에서는 숨기므로 `finalize_my_focus()`로 상태를 확정한 뒤 재조회합니다. 미리보기 유효 토큰은 자동 확정을 최대 5분 보류합니다.

`list_crops` 입력은 `low | medium | high | null`입니다. null이면 활성 작물 6종 모두 추천 false입니다. `get_focus_history`는 `today | week | all`만 허용합니다. today는 1일, week는 월~일 7일을 0 채우며 all은 기록 있는 날짜만 반환합니다. 빈 all은 날짜 범위 null, 요약 0, items 빈 배열입니다. **현재 수확 집계는 실제 harvests 기반 숫자이며 capability=true**입니다. 예전 null/false 계약을 사용하지 않습니다. 일자 귀속은 세션 시작일 `record_date`로 수확 시각과 다를 수 있습니다.

## 오류 및 화면 상태

```js
function normalizeBackendError(error, hasSession) {
  if (!error) return null
  if (['PGRST301', 'PT401'].includes(error.code)) return 'UNAUTHENTICATED'
  if (error.code === '42501' && !hasSession) return 'UNAUTHENTICATED'
  if (error.code === '22023') return 'INVALID_INPUT'
  if (error.code === 'PT400') return error.details || 'INVALID_INPUT'
  if (error.code === 'PT404') return error.details || 'NOT_FOUND'
  if (error.code === 'PT409') return error.details || 'INVALID_STATE'
  return 'UNKNOWN'
}
```

PT400/401/404/409는 각각 HTTP 400/401/404/409이며 A의 22023은 HTTP 400입니다. B 오류는 `details`를 사용하고 한국어 message 문자열에 로직을 의존하지 않습니다. 표의 오류는 각 RPC에 해당하는 항목만 반환됩니다.

| 대상 | 오류 식별자 |
|---|---|
| A profile/onboarding | UNAUTHENTICATED, NOT_FOUND |
| A crops/history | UNAUTHENTICATED, INVALID_INPUT; history는 NOT_FOUND도 가능 |
| A farm | UNAUTHENTICATED |
| ensure_farm | 익명 42501; 프로필 부재 PT404/NOT_FOUND |
| start_focus | INVALID_INPUT, PLOT_NOT_FOUND, CROP_NOT_FOUND, PLOT_OCCUPIED, ACTIVE_SESSION_EXISTS |
| pause/resume | INVALID_INPUT, SESSION_NOT_FOUND, INVALID_STATE; resume의 PAUSE_EXPIRED |
| preview | INVALID_INPUT, SESSION_NOT_FOUND, INVALID_STATE |
| confirm/cancel | INVALID_INPUT, STOP_TOKEN_NOT_FOUND; confirm은 STOP_TOKEN_EXPIRED, INVALID_STATE |
| harvest | INVALID_INPUT, SESSION_NOT_FOUND, NOT_RIPE |
| ack | INVALID_INPUT, AUTO_HARVEST_NOT_FOUND |
| note | INVALID_INPUT, NOTE_TOO_LONG, HARVEST_NOT_FOUND |
| rest | INVALID_INPUT, HARVEST_NOT_FOUND, INVALID_STATE |
| claim | INVALID_INPUT; 타인/없는/부적격 세션은 false |

모든 B 공개 RPC는 인증 컨텍스트 부재 시 PT401이며 익명 요청은 먼저 실행 권한에서 차단됩니다. `finalize_my_focus()`와 `get_active_focus()`에는 별도 입력이 없습니다.

- loading: 첫 요청 중 표시하고 중복 쓰기 버튼을 잠급니다.
- empty: 농장 `[]`은 초기화 흐름으로 복구; 기록 빈 배열·0은 정상 데이터입니다.
- UNAUTHENTICATED: 세션 복원/갱신 확인 후 로그인으로 이동합니다. 비밀번호 오류 자동 재시도는 하지 않습니다.
- 세션이 있는 42501: 권한 배포 오류로 기록하고 SQL·키·토큰을 사용자에게 표시하지 않습니다.
- PLOT_OCCUPIED / ACTIVE_SESSION_EXISTS: 농장·활성 세션을 다시 읽고 서버 상태에 맞춥니다.
- INVALID_STATE / PAUSE_EXPIRED / NOT_RIPE: finalize 및 농장·활성 세션 재조회 후 가능한 동작을 표시합니다.
- 기간·에너지 탭을 변경하면 늦게 도착한 이전 요청 결과는 폐기합니다. 네트워크 재시도는 1회로 제한합니다.

## 호출 순서와 화면 연결

1. S19 가입은 nickname metadata를 보내며 S18은 이메일/비밀번호 로그인입니다. 가입 응답의 user/session을 확인합니다.
2. S01: 프로필 조회 → `ensure_farm()` → 1~12번 밭 확인 → `complete_onboarding()`. 중간 실패는 같은 순서로 멱등 재시도합니다.
3. 재접속: 해당 사용자에게 보관된 stop token이 있으면 cancel → finalize → 활성 세션·농장 조회. 토큰을 잃으면 5분 TTL까지 보류될 수 있습니다.
4. S02/S03: get_my_farm. focusing/paused는 growing, ripe는 ripe, seed_saved/harvested는 empty입니다. 조회 자체는 밭을 생성하거나 상태를 변경하지 않습니다.
5. S04/S05: list_crops 추천 → 선택 ID로 start_focus → 서버 응답을 타이머 기준으로 사용합니다. 활성 세션 복원은 get_active_focus입니다.
6. S09: preview의 스냅샷 표시 → 저장은 confirm, 계속 키우기·닫기는 cancel. 5분 만료 시 닫고 finalize 후 재조회합니다. stop token은 사용자별 세션 보관소에 잠시 보관하고 로그에 출력하지 않습니다.
7. S17: ripe 세션 harvest → 농장과 기록을 재조회합니다. 수확 직후 밭 재사용이 가능합니다. 자동 수확 결과라면 미확인 목록도 갱신합니다.
8. 메모: 1~50자(앞뒤 공백 제거). guidance_required이면 S13 안내를 표시하며 메모는 저장되지 않습니다. 초기 문자열 탐지 정책이며 전문적인 위험 평가를 의미하지 않습니다.
9. 휴식: 본인 수동 수확만 신규 시작 가능. 서버 기준 5분이며 `max(0, Date.parse(rest_ends_at)-Date.parse(server_now))`로 초기 남은 시간을 계산합니다. 반복 요청은 최초 종료 시각을 유지합니다.
10. S14/S15: today/week/all 호출. 수동·자동 수확은 각 세션당 1건만 집계됩니다.
11. S12: get_active_focus의 후보가 true이면 claim_overwork_notice 호출 후 true 응답인 기기만 표시합니다. 연속 집중 5400초 초과, 30분 이상 공백 시 연속성 종료, 일별 1회 획득 정책입니다. 렌더링 전 앱이 종료되면 재표시되지 않을 수 있습니다.

화면 번호는 저장소 계약에 기반합니다. Notion 원문 대조는 미검증이므로 번호·UI 필드 확정은 프론트가 원본과 확인해야 합니다.

## 자동 수확 알림과 Cron

```js
const { data: notices, error } = await supabase.from('harvests')
  .select('id').eq('auto_harvested', true).is('notice_acknowledged_at', null)
  .order('harvested_at').order('id')
// RLS가 본인 세션의 수확만 허용합니다. []은 정상입니다.
// 실제 표시한 ID만 ack_auto_harvest_notice({ p_harvest_ids: displayedIds })로 확인합니다.
```

미확인 조회 성공 동작은 VERIFIED_LOCAL_ONLY, 익명 차단은 VERIFIED_REMOTE입니다. 밭마다 사용자 전체 알림 ID를 중복 추가하지 않습니다.

**자동 수확 스케줄은 PENDING**입니다. 원격 pg_cron 확장이 없으며 자동 수확 예약은 구성하지 않았습니다. process_due_harvests 함수 존재만 확인됐고 원격 실행·예약 로그·실제 자정 처리·수동 수확과의 원격 경쟁은 미검증입니다. 함수는 사용자 시간대에서 목표 달성일의 다음 자정을 기한으로 계산하지만, 예약이 없으면 백그라운드 자동 실행은 일어나지 않습니다. 기한 이후 수동 harvest 호출은 auto_harvested=true일 수 있습니다. B와 주기·DB 실행 역할·배치 최대 100명 처리 정책을 합의한 뒤 별도 배포해야 합니다.

## 배포 및 검증 기록

배포 전: 원격 migration 0, 업무 테이블 0, Auth 사용자 0. 사전 존재한 `public.rls_auto_enable()` event-trigger 함수는 업무 RPC와 구분해 보존했습니다.

CLI 실제 결과: `npx supabase db push --dry-run --skip-vault --remote` → 아래 14개 적용 예정. 이어 `npx supabase db push --skip-vault --remote --yes` → 14개 모두 적용, `Finished supabase db push.`. 적용 후 migration list의 local/remote 버전 전부 일치, 재 dry-run `Remote database is up to date.` / 적용 예정 0개. role/seed/Vault 변경 없음.

```text
20261110152140_a_foundation.sql
20261113012151_b_farm_foundation.sql
20261113020509_b_focus_sessions.sql
20261113143508_a_farm_read_model.sql
20261113145323_a_focus_history.sql
20261114054245_b_finalize_focus.sql
20261114070324_b_stop_focus.sql
20261114072516_b_harvest.sql
20261115011444_a_focus_history_harvest_count.sql
20261115013511_b_save_harvest_note.sql
20261115015534_b_start_rest.sql
20261115020000_b_harvest_note_guidance.sql
20261115020500_b_focus_streak.sql
20261115021000_b_overwork_precision.sql
```

로컬 검증: npm ci, db:reset, db:test **303/303**, Auth/RPC 통합(수확·메모·휴식·S12 경쟁 포함), History 통합, db:lint 모두 PASS; npm audit 취약점 0. 원격 사용자 성공 경로로 오인하지 않습니다. 기존 로컬 Auth 사용자 0명 확인 후 테스트 DB만 reset했습니다.

원격 확인: public `profiles/crops/farm_plots/focus_sessions/harvests`, private `focus_stop_previews/overwork_notices` 전부 RLS 활성화. 사용자 테이블 정책은 auth.uid 기반이며 수확은 소유 세션 JOIN을 사용합니다. 앱 RPC 19개는 authenticated만 실행 가능하고 process_due_harvests는 앱 role 실행 금지입니다. 프로필 생성·timezone 검증·stop 무효화·ripe 기한·집중 종료 시각 트리거, 세션당 수확 UNIQUE, 복합 소유권 FK, 활성 세션·점유 UNIQUE 및 관련 인덱스를 조회했습니다. pgcrypto 1.3 존재. 작물 6종, Auth 사용자/프로필/세션/수확 0명·0건을 확인했습니다.

원격 스모크: 앱 RPC 19개+DB 관리 함수 1개 익명 POST 모두 401/42501; public 테이블 5개 익명 SELECT 모두 401. `/auth/v1/settings` 정책 확인. 원격 테스트 사용자는 생성하지 않았고 업무 데이터·시간을 조작하지 않았습니다.

## Advisor 분류

| 분류 | 결과·판단 |
|---|---|
| Security INFO 2 | private 테이블 2개의 RLS 정책 없음. 앱 권한을 모두 철회한 비공개 내부 저장소이므로 의도된 차단이며 공개 정책 추가 금지 |
| Security WARN 15 | authenticated의 앱 SECURITY DEFINER 호출. 소유권 검사·고정 search_path·역할별 GRANT를 갖춘 쓰기 RPC 설계에 따른 알림. 성공 경로는 로컬 검증 |
| Security WARN 2 | 배포 전부터 존재한 rls_auto_enable의 anon/authenticated EXECUTE. event_trigger 반환 함수이며 일반 호출 가능성·플랫폼 기본 권한 정리는 별도 확인 필요. 이번에 기존 플랫폼 객체 권한을 변경하지 않음 |
| Performance INFO 2 | focus_sessions.crop_id 및 focus_stop_previews.user_id FK 보조 인덱스 없음. 데이터 증가·삭제 부하에 따라 B 담당 검토 |
| Performance INFO 2 | due_harvest/streak 인덱스 미사용. 신규·빈 DB이므로 삭제 근거 아님 |
| Health | 프로젝트 ACTIVE_HEALTHY 확인. 현재 CLI advisor type은 all/security/performance만 제공; 별도 Health Advisor 결과·장기 로그 관찰은 미검증 |

Advisor 경고가 0이라고 보고하지 않습니다. API 연결은 가능하지만 원격 인증 E2E와 Cron은 별도 완료가 필요합니다.

## Notion 대조

[Notion API 명세](https://app.notion.com/p/API-8becc0a84f5e8370814501e647d668d9?source=copy_link)는 조회 도구에서 접근 불가였습니다. 이름·인자·응답·오류·인증·호출 시점·화면 번호의 Notion 일치 여부는 모두 PENDING이며 차이를 추측하지 않았습니다. 인계 기준은 배포 main의 SQL과 [RPC 계약](../api/rpc-contracts.md), [프론트 연동 가이드](../api/frontend-integration.md)입니다.

기존 RPC 계약의 일부 오래된 TBD/오류 정규화 예시보다 이 문서의 배포 관측과 최신 SQL을 우선 참고합니다. 신규 breaking change는 적용하지 않았습니다.

## Discord 공유문

집중농장 Staging DB 배포 완료했습니다.

- URL: https://klanbfvywwudprunaqdf.supabase.co
- Publishable Key: 이 인계 문서의 연결 정보에서 복사해주세요. Secret/service_role key는 사용하지 않습니다.
- 가이드: 저장소 `docs/deployment/frontend-handoff.md`
- 명세: https://app.notion.com/p/API-8becc0a84f5e8370814501e647d668d9?source=copy_link (백엔드에서는 접근 불가로 대조 미검증)
- 이메일/비밀번호, 가입 허용, Confirm email OFF, nickname metadata 정책입니다.
- 프로필·온보딩·작물·농장·집중·중단·수확·집중 기록·수확 메모·휴식·과로 안내 API가 배포됐습니다. 수확 집계는 이제 숫자/capability=true입니다.
- 로컬 303개 DB 테스트와 통합 테스트 통과, 원격 스키마·권한·익명 차단·Auth 공개 설정 확인했습니다. 원격 계정 생성 승인이 없어 로그인 사용자 E2E는 아직 미검증입니다.
- 자동 수확 DB 함수는 있지만 Cron은 미설정입니다. 백그라운드 자동 수확이 켜진 상태는 아닙니다. 기록 초기화 API도 미구현입니다.
- 연동 중 응답·화면 계약 차이가 보이면 API 이름, 입력 형태, 오류 code/details와 재현 순서를 공유해주세요. 토큰·비밀번호는 공유하지 마세요.
