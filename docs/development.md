# 개발 및 협업 규칙

## 저장소 상태

원격 `main`과 `develop`의 최초 부트스트랩은 완료되었습니다. 새 작업은 최신 `origin/develop`에서 이슈 브랜치를 만들고 PR로 병합합니다. 초기화 명령을 다시 실행하거나 기존 Git 기록을 재작성하지 않습니다.

## 브랜치

- `main`: 운영 배포 기준
- `develop`: 통합 기준
- `issue/<번호>-<설명>`: `develop`에서 분기하는 기능 개발 브랜치

기능 PR은 `develop`으로 제출합니다. `develop`에서 검증된 변경만 릴리스 PR을 통해 `main`으로 병합합니다.

## 리뷰와 병합

- 모든 PR은 최소 1회 리뷰가 필요합니다.
- 마이그레이션 변경은 A/B 양측이 검토합니다.
- 병합된 마이그레이션 파일은 수정하지 않습니다. 후속 변경은 새 마이그레이션으로 작성합니다.
- 공유 브랜치에서 force push하지 않습니다.
- B 담당자의 GitHub 사용자명이 확정되면 CODEOWNERS에 A/B를 함께 등록합니다.

## Supabase CLI v3

- 저장소에 고정된 CLI는 `npx supabase` 또는 npm script로 실행합니다.
- 로컬 실행이 기본입니다. 호스팅 프로젝트 대상 명령은 반드시 `--remote`로 명시합니다.
- 원격 변경 전에는 대상과 dry-run 결과를 확인합니다.
- `SUPABASE_YES`를 환경 파일에 저장하지 않습니다.
- Staging 연결은 승인된 `focus-farm-staging (klanbfvywwudprunaqdf)`에만 수행하며 명령 전후 대상 Ref를 확인합니다.
- 원격 환경 준비와 배포는 [환경 분리 전략](deployment/environment-strategy.md)과 [마이그레이션 런북](deployment/migration-runbook.md)을 따릅니다.

## 보안

- `.env.example` 외의 환경 파일은 커밋하지 않습니다.
- secret key, legacy service-role key, DB 비밀번호, access token은 클라이언트나 저장소에 노출하지 않습니다.
- publishable key는 공개 클라이언트용이며, 데이터 권한은 RLS로 제한합니다.
- 실제 사용자 데이터는 seed나 테스트 fixture로 사용하지 않습니다.

## S13 수확 메모 판정

Figma v1.0의 1-9, S10, S13 기준으로 S10 메모 저장 시 검사합니다. 초기 후보는 `죽고 싶`, `자살`, `사라지고 싶`, `살기 싫`, `끝내고 싶`입니다. 최종 승인 목록과 확장 규칙은 협의 중입니다. 목록을 변경할 때 이 문서와 신규 SQL 마이그레이션 및 테스트를 함께 갱신합니다.

입력 앞뒤 공백을 제거한 뒤 PostgreSQL `char_length`로 길이를 검사하고 `strpos`로 정확한 부분 문자열을 찾습니다. 내부 공백과 구두점은 원형을 유지하고, 대소문자 변환과 유니코드 정규화는 수행하지 않습니다. 후보가 문장 안에 그대로 있으면 위치와 관계없이 감지합니다. 인용이나 부정 문맥에서도 감지될 수 있고 띄어쓰기 변형이나 목록 밖 표현은 놓칠 수 있습니다. 이 결과는 S13 안내 표시 여부에만 쓰며 사용자 상태를 진단하거나 판단하는 데 사용하지 않습니다.

## S12 운영 점검

기존 시간대 트리거는 INSERT와 timezone UPDATE에 적용됩니다. 배포 전에 다음 읽기 전용 쿼리로 보정 검토가 필요한 과거 행을 확인합니다.

```sql
select p.id, p.timezone
from public.profiles p
where not exists (
  select 1 from pg_catalog.pg_timezone_names z where z.name = p.timezone
);
```

장기간 이력을 보유한 계정은 운영과 비슷한 스테이징에서 `private.focus_streak_seconds` 내부의 두 SELECT를 각각 `EXPLAIN (ANALYZE, BUFFERS)`로 확인합니다. 마지막 휴식을 구하는 `max(rest_ends_at)` 조인의 처리 행 수와, 종료된 세션을 최신순으로 읽는 쿼리의 `focus_sessions_streak_history` 사용 여부를 확인합니다. 휴식이 없는 계정과 짧은 공백으로 이력이 길게 연결된 계정을 포함합니다. 독립 SELECT 실행 계획은 루프의 조기 종료를 반영하지 않으므로 읽기 전용 후보 조회 지연도 함께 측정합니다. ANALYZE는 쿼리를 실제 실행하므로 운영 트래픽이 많은 시간대와 안내 기록을 쓰는 획득 RPC에는 사용하지 않습니다.
