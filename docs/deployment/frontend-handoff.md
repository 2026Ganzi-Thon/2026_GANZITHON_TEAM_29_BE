# 집중농장 Staging 프론트엔드 인계

추가 요구사항의 현재 상태와 필드: [두 기록 API 성장·씨앗 집계](../api/history-crop-counts.md).
추가 필드도 Staging 실제 Auth SDK **VERIFIED_REMOTE**입니다. 기존 get_focus_history 호출을 유지할 수 있습니다.

작물별 기록 신규 API: [get_crop_history 계약·검증 상태](../api/crop-history.md).
S14는 crop_totals, S15는 items[].crops, S15-1은 monthly[].crops와 crop_totals를 사용합니다.
신규 API도 실제 Auth/RPC·비활성 작물 RLS E2E **VERIFIED_REMOTE**입니다.
[배포·CI·테스트 정리 기록](crop-history-staging-verification.md)을 확인합니다.

최신 추가 검증일: 2026-11-18 (Asia/Seoul, get_crop_history). 기존 2026-11-15 **Staging 실제 Auth·인증 RPC·예약 자동 수확 E2E 통과**의 범위와 제한은 [원격 E2E 기록](staging-remote-e2e.md)을 따릅니다. 이번 작업은 Cron 설정·ACTIVE 유지 확인이며 예약 수확 E2E를 새로 수행했다고 주장하지 않습니다.

## 연결 정보

| 항목 | 실제 조회 값 |
|---|---|
| 환경 / 이름 | STAGING / focus-farm-staging |
| Project Ref | klanbfvywwudprunaqdf |
| 리전 / PostgreSQL | ap-northeast-2 / 17.11 (프로젝트 build 17.11.0.018) |
| Project URL | https://klanbfvywwudprunaqdf.supabase.co |
| REST API Base URL | https://klanbfvywwudprunaqdf.supabase.co/rest/v1 |
| Publishable key | `sb_publishable_BhYc2LCiC6QLv6bVUiyzlA_XP7sbz29` |
| 배포한 main SHA | `743c88a50fc2d31201a573b6d5ea592ff8e9ddbb` (grown/seed 집계 보강, 2026-11-18) |
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

공개 Auth `/auth/v1/settings`에서 `external.email=true`, `disable_signup=false`, `mailer_autoconfirm=true`를 확인했습니다. 승인된 고유 임시 계정 2개로 실제 signUp/signInWithPassword/setSession/getSession/getUser/signOut을 검증했고 가입 즉시 세션도 확인했습니다. `nickname` metadata는 표시용이며 권한 판단에 사용하지 않습니다. 테스트 계정과 관련 데이터는 검증 후 삭제했습니다.

## 실제 검증 범위

- `VERIFIED_REMOTE`: 원격에서 해당 검증을 실제 실행함.
- `VERIFIED_LOCAL_ONLY`: 성공 동작은 로컬에서 검증했으며 원격 인증 성공 경로는 미실행.
- `PENDING`: 구현·정책·예약 또는 승인이 남음.
- `FAILED`: 검증 실패. 이번 배포 명령·로컬 테스트·익명 차단 검사에는 없음.

아래 앱 RPC 19개의 성공 호출과 Auth는 **VERIFIED_REMOTE**입니다. `claim_overwork_notice`는 정상적인 비대상 세션의 `false` 분기만 원격 검증했으며, 90분 초과 `true`·일별 경합은 VERIFIED_LOCAL_ONLY입니다. 자동 수확은 실제 예약 실행에 의한 테스트 세션 수확을 확인했습니다. 관리자 직접 실행은 이번 E2E에서 호출하지 않았습니다. 모든 오류·시간 경계·동시성 조합을 원격 전수검증한 의미는 아닙니다.

## RPC 요청·응답

공통 호출: `const { data, error } = await supabase.rpc(name, args)`; 인자가 없으면 두 번째 인자를 생략합니다. 시각 문자열은 UTC ISO 형식이고 UUID는 문자열입니다. 아래 응답은 구현으로 확인한 구조 예시이며 원격 사용자 실측 응답이 아닙니다.

| RPC / 요청 JSON | 성공 응답 예시 또는 구조 | 화면 / 재시도 |
|---|---|---|
| `get_my_profile()` | `[{nickname:'농부',timezone:'Asia/Seoul',onboarded:false,onboarded_at:null}]` | S01 / 네트워크 1회 |
| `complete_onboarding()` | `'2026-11-15T12:00:00+00:00'` | S01 / 멱등 재시도 |
| `list_crops({p_energy:'low'})` | `[{crop_id:'uuid',name:'새싹채소',target_seconds:600,recommended:true,sort_order:1}, ...]` | S04/S05 / 네트워크 1회 |
| `get_my_farm()` | `[{plot_id:'uuid',plot_index:1,farm_status:'empty',session_id:null,session_status:null,crop_id:null,crop_name:null,target_seconds:null}, ...]` | S02/S03 / 네트워크 1회 |
| `get_focus_history({p_period:'week'})` | `{period,range:{start_date,end_date,timezone},summary:{focused_seconds,seed_count,harvest_count},items:[{record_date,focused_seconds,seed_count,harvest_count,crops:[{crop_id,crop_name,focused_seconds,grown_count,seed_count}]}],capabilities:{harvest_count:true}}` | S14/S15 / 네트워크 1회 |
| `get_crop_history({p_period:'week'})` | `{period,summary:{focused_seconds,seed_count,harvest_count},items:[{record_date,focused_seconds,harvest_count,crops}],monthly:[],crop_totals:[{crop_id,crop_name,focused_seconds,harvest_count,grown_count,seed_count}]}` | S14/S15/S15-1 / 네트워크 1회 |
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

모든 앱 RPC는 로그인한 `authenticated` 사용자 전용입니다. 추가 DB 관리 함수 `process_due_harvests()`는 `{processed_count}`를 반환하지만 **anon/authenticated/service_role 모두 EXECUTE 없음**, DB 소유자의 관리 실행 전용입니다. 프론트에서 호출하지 않습니다. 신규 `reset_farm_history()`도 배포 및 실제 SDK **VERIFIED_REMOTE**입니다. [S16 명세](../api/s16-reset-contract.md)·[보존/삭제/E2E/재시도 기록](s16-staging-verification.md)을 따릅니다. 앱 RPC는 현재 21개이며 원격 migration은 17개입니다.

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

미확인 조회·ack·재시도·타인 ack 차단·확인 후 목록 제거와 익명 차단은 VERIFIED_REMOTE입니다. 밭마다 사용자 전체 알림 ID를 중복 추가하지 않습니다.

**자동 수확 Cron ACTIVE**입니다(2026-11-15). `focus-farm-auto-harvest-staging`이 관리자 `postgres`로 `* * * * *`마다 DB 내부 `SELECT public.process_due_harvests();`를 실행합니다. 한국 시각 23:52의 실제 예약 실행이 테스트 세션을 수확했고 수확 기록 1건·auto_harvested=true·빈 밭·알림 조회와 ack를 확인했습니다. 테스트 계정 전용 시각만 승인 범위에서 조정했습니다. 사용자 현지 날짜 기준 다음 자정 이후 처리하며 배치·잠금·작업 시간·장애에 따라 1분 이상 지연될 수 있습니다. 실제 현지 자정까지의 자연 경과와 수동 수확/Cron 경합의 모든 순서는 원격 미검증입니다. [Cron 운영 기록](auto-harvest-cron.md)을 참고하세요.

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

최초 배포 스모크: 앱 RPC 19개+DB 관리 함수 1개 익명 POST 모두 401/42501; public 테이블 5개 익명 SELECT 모두 401. 이후 승인된 실제 Auth E2E에서는 임시 계정 2개를 생성하고 해당 계정 소유 세션의 시각만 조정했습니다. 완료 후 계정·관련 업무 데이터·Auth 세션·보조 데이터 모두 0건으로 정리했습니다.

## Advisor 분류

| 분류 | 결과·판단 |
|---|---|
| Security INFO 2 | private 테이블 2개의 RLS 정책 없음. 앱 권한을 모두 철회한 비공개 내부 저장소이므로 의도된 차단이며 공개 정책 추가 금지 |
| Security WARN 15 | authenticated의 앱 SECURITY DEFINER 호출. 소유권 검사·고정 search_path·역할별 GRANT를 갖춘 쓰기 RPC 설계에 따른 알림. 성공 경로는 로컬 검증 |
| Security WARN 2 | 배포 전부터 존재한 rls_auto_enable의 anon/authenticated EXECUTE. event_trigger 반환 함수이며 일반 호출 가능성·플랫폼 기본 권한 정리는 별도 확인 필요. 이번에 기존 플랫폼 객체 권한을 변경하지 않음 |
| Performance INFO 2 | focus_sessions.crop_id 및 focus_stop_previews.user_id FK 보조 인덱스 없음. 데이터 증가·삭제 부하에 따라 B 담당 검토 |
| Performance INFO 2 | due_harvest/streak 인덱스 미사용. 신규·빈 DB이므로 삭제 근거 아님 |
| Health | 프로젝트 ACTIVE_HEALTHY 확인. 현재 CLI advisor type은 all/security/performance만 제공; 별도 Health Advisor 결과·장기 로그 관찰은 미검증 |

Advisor 경고가 0이라고 보고하지 않습니다. Auth·앱 RPC·실제 예약 수확의 검증 결과는 [원격 E2E 기록](staging-remote-e2e.md)에 정리했습니다. Notion 대조·장기 부하·일부 오류/시간 경계는 미검증입니다.

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
- 로컬 303개 DB 테스트와 통합 테스트 통과, 실제 임시 계정 2개로 Auth·RPC·계정 간 RLS를 원격 검증했습니다. 테스트 계정과 데이터는 모두 정리됐습니다.
- 자동 수확 Cron은 1분 주기로 ACTIVE입니다. S16 reset도 Staging 배포·SDK 검증됐으며 초기화 후 예약 실행에서 과거 데이터가 복원되지 않음을 확인했습니다. 로그인·온보딩·plot ID는 유지합니다. 파괴적 reset은 자동 재시도하지 마세요. 과로 안내 true 분기는 로컬 검증입니다.
- 연동 중 응답·화면 계약 차이가 보이면 API 이름, 입력 형태, 오류 code/details와 재현 순서를 공유해주세요. 토큰·비밀번호는 공유하지 마세요.
