# Staging 자동 수확 Cron 운영

대상은 `focus-farm-staging` / `klanbfvywwudprunaqdf`, 서울, PostgreSQL 17.11입니다. 운영 SQL은 일반 마이그레이션이 아니며 Production에 적용하지 않습니다.

작업 기준 develop: `cb14939f3d47f87e41d99086b6a325d1bc7a965b`. 배포 코드 main: `7471dddc028df1c87f2e33e93dbbae33b34b31f5`. 작업 브랜치: `infra/staging-auto-harvest-cron`.

## 구성과 적용

- Job: `focus-farm-auto-harvest-staging`, jobid 1
- 스케줄: `* * * * *` (1분마다)
- 명령: `SELECT public.process_due_harvests();`
- 실행 역할 / DB: `postgres` / `postgres`
- DB 내부 SQL만 실행하며 API key·HTTP·Edge Function을 사용하지 않습니다.
- pg_cron 1.6.4. 정책은 [공식 설치](https://supabase.com/docs/guides/cron/install), [Quickstart](https://supabase.com/docs/guides/cron/quickstart)에 따라 확인했습니다.

먼저 프로젝트 API에서 이름·Ref·리전·DB 버전을 확인하고 원격 migration list가 기존 14개와 일치하는지 확인합니다. `ops/staging/enable-auto-harvest-cron.sql`을 관리자 연결에서 실행합니다. 이번 실행은 Supabase execute_sql 도구에 **project_id=klanbfvywwudprunaqdf**를 명시해 파일 원문을 실행했습니다. apply_migration, migration repair, db reset은 원격에서 실행하지 않았습니다.

재실행은 승인된 프로젝트 확인 후 CLI 연결과 사용자 확인을 거쳐 다음과 같이 할 수 있습니다(실제 옵션은 CLI 3.1.0 help 확인).

```sh
npx supabase link --project-ref klanbfvywwudprunaqdf
npx supabase db query --remote --file ops/staging/enable-auto-harvest-cron.sql
```

SQL은 current_user=postgres, 승인된 클러스터 system_identifier, 마이그레이션 버전 14개, 관리 함수 권한을 검사합니다. 클러스터 ID는 비밀값이 아니며 DB 복제·복구 후 달라질 수 있습니다. 클러스터 복제본이 같은 ID를 가질 수 있으므로 이 검사만 믿지 말고 프로젝트 Ref를 별도로 확인합니다. 복구 후 가드를 임의 제거하지 않습니다.

동일 이름·소유자의 올바른 Job은 그대로 유지하고 잘못된 주기·명령·활성 상태만 수정합니다. 다른 소유자나 중복 Job은 중단합니다. 무관한 Job을 수정하지 않습니다.

초기 설치 후 재실행에서 `CREATE EXTENSION IF NOT EXISTS`에 대해 Supabase 확장 권한 훅이 재실행되어 `dependent privileges exist`가 발생했습니다. 해당 재실행 트랜잭션은 롤백됐고 최초 Job은 유지됐습니다. 최종 SQL은 pg_extension 존재 확인 후 없는 경우에만 CREATE하여 재실행을 검증했습니다. 기존 관리 권한을 CASCADE REVOKE하지 않았습니다.

## 동작과 장애 경계

기존 B 함수는 사용자 프로필을 정렬해 `LIMIT 100 FOR NO KEY UPDATE SKIP LOCKED`로 선점하고 세션을 처리합니다. 잠긴 사용자는 다른 실행에서 처리하고 다음 주기에도 다시 검사합니다. 한 사용자에게 여러 ripe 세션이 있으면 사용자 배치 안에서 기한이 지난 세션을 처리합니다.

목표 달성한 focusing 세션은 기존 finalize 함수로 ripe로 확정하고, 사용자의 timezone 기준 목표 달성일 다음 자정을 수확 기한으로 삼습니다. 유효한 stop preview 보류 규칙도 유지합니다. 기한이 지난 ripe만 수확하며 이미 harvested인 세션은 제외합니다. harvests.session_id UNIQUE와 프로필→세션 행 잠금으로 중복 수확을 방어합니다. B 함수·테스트는 변경하지 않았습니다.

한 호출은 하나의 트랜잭션입니다. 오류면 그 배치 전체가 롤백되며 부분 성공을 커밋하지 않습니다. 다음 분에 다시 조회하지만 특정 데이터의 지속 오류는 같은 배치를 계속 실패시킬 수 있습니다. 자동으로 실패 사용자를 건너뛰거나 무한 성공을 보장하지 않습니다. 이 경우 로그와 해당 사용자 데이터를 B 담당자가 분석해야 합니다. 데이터 삭제로 우회하지 않습니다.

일시 DB 중단 후에는 다음 실행이 현재 기한 초과 대상을 조회합니다. pg_cron이 중단 중의 매 분 실행을 모두 재생한다는 의미는 아닙니다. 100명 이상 잔여, 잠금, 긴 작업, 장애 때문에 처리 지연이 1분을 넘을 수 있습니다.

## 모니터링

```sql
select jobid,jobname,schedule,command,username,database,active
from cron.job where jobname='focus-farm-auto-harvest-staging';

select jobid,status,return_message,start_time,end_time
from cron.job_run_details
where jobid=(select jobid from cron.job where jobname='focus-farm-auto-harvest-staging')
order by start_time desc limit 10;

select status,count(*) from cron.job_run_details
where jobid=(select jobid from cron.job where jobname='focus-farm-auto-harvest-staging')
  and start_time > now()-interval '1 day'
group by status;
```

매 운영 점검에서 실패 이력·실행 지연·최근 성공 여부를 확인합니다. 최근 3분 이상 성공 이력이 없거나 반복 failed가 있으면 조사합니다. `return_message='1 row'`는 SELECT가 반환한 행 수이지 수확 1건이나 processed_count 값이 아닙니다. 수확 결과는 harvests 및 잔여 기한 초과 세션으로 별도 확인합니다.

비활성화/재활성화는 프로젝트·역할을 재확인한 후 해당 Job 하나만 변경합니다.

```sql
select cron.alter_job((select jobid from cron.job
  where jobname='focus-farm-auto-harvest-staging'), active := false);
-- 원인 해결 후
select cron.alter_job((select jobid from cron.job
  where jobname='focus-farm-auto-harvest-staging'), active := true);
```

실행 중인 트랜잭션을 즉시 취소하는 명령은 아닙니다. 확장 DROP은 모든 Job·이력을 지우므로 복구 방법으로 사용하지 않습니다. 이번 작업에서는 비활성화·로그 삭제를 실행하지 않았습니다.

이력 보관 권장안은 30일입니다. 매일 약 1,440행이 증가합니다. 자동 삭제 Job은 등록하지 않았으며, 보관 정책 승인 후 이 Job의 30일 이전 종료 이력만 대상으로 정리합니다. 실패 원인 조사 전 로그를 삭제하지 않습니다.

## 검증

2026-11-15 로컬 npm ci·db:reset·pgTAP **303/303**·Auth/RPC 통합·History 통합·DB lint·npm audit 모두 통과했습니다. 원격 db lint는 오류 없음, Security Advisor는 기존 INFO/WARN과 동일하며 새 Cron 관련 보안 경고는 없었습니다.

추가 `ops/staging/test-auto-harvest-local.sql`은 빈 로컬 DB의 Unix socket에서만 실행하며 101명 fixture를 생성한 뒤 첫 배치 100명, 다음 배치 1명, 재실행 0건, 자동 수확 기록 101개를 검증하고 전부 ROLLBACK합니다. 기존 B 테스트는 다음 자정·수동 수확 재시도·기한 초과 worker·preview 보류·ack·밭 재사용을 검증합니다. 기존 통합 테스트의 병렬 수확 요청은 중복 방지를 검증합니다.

원격은 사용자·세션·수확 0건입니다. 수확 대상을 임의 생성하거나 시간을 조작하지 않았습니다. 관리자 직접 빈 실행은 `{processed_count:0}`이었습니다. 이는 예약 실행 이력과 별개의 검사입니다.

원격 예약 실행 결과는 아래 실행 기록에 남깁니다. 실제 수확 처리 성공 경로는 VERIFIED_LOCAL_ONLY이며 원격은 스케줄러 실행만 VERIFIED_REMOTE입니다. Cron/수동 수확의 모든 잠금 순서, 장애 주입·재시작, timezone 조합 전수검증은 수행하지 않았습니다.

| Job ID | UTC 시작 | UTC 종료 | 상태 / return_message |
|---|---|---|---|
| 1 | 2026-11-15 14:36:00.111556 | 14:36:00.117483 | succeeded / 1 row |
| 1 | 2026-11-15 14:37:00.063224 | 14:37:00.070029 | succeeded / 1 row |

한국 시각 23:36·23:37의 실제 예약 실행 **2회 성공**입니다. 수동 직접 실행을 이 횟수에 포함하지 않았습니다. 운영 SQL 재실행 후에도 Job ID 1 하나만 존재했습니다.

## 권한

관리 함수 EXECUTE: postgres=true, anon/authenticated/service_role=false. cron 스키마 USAGE도 관리자만 가능하며 일반 세 역할은 false입니다. 확장이 생성한 cron 테이블의 ACL 조회에서는 일반 역할 SELECT가 true로 보일 수 있으나 스키마 USAGE가 없어 직접 이름으로 접근할 수 없습니다. 기존 Supabase 관리 테이블 ACL을 무분별하게 철회하지 않았습니다.

앱의 public/private 테이블 RLS와 기존 API 권한은 유지합니다. 신규 마이그레이션을 추가하지 않아 원격 이력은 14개 그대로입니다.
