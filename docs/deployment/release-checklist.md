# 운영 릴리스 체크리스트

실제 원격 프로젝트가 없으므로 아래 항목은 아직 PASS가 아닙니다.

## 배포 전

- [ ] 배포 환경, 조직, 프로젝트명, Project Ref를 두 명이 대조
- [ ] GoldenLook 및 다른 프로젝트가 아님을 확인
- [ ] 배포 커밋이 승인된 `develop` 또는 `main` HEAD와 일치
- [ ] PR 리뷰와 GitHub Actions 성공
- [ ] 로컬 `db:reset`, pgTAP, Auth/RPC 통합, lint, audit 성공
- [ ] `migration list --remote` 차이가 예상과 일치
- [ ] `db push --dry-run --remote` 적용 목록 승인
- [ ] RLS, GRANT/REVOKE, definer 함수와 Cron 권한 검토
- [ ] Production 최신 백업과 복구 담당자 확인
- [ ] Site URL, Redirect URL, 이메일 확인, SMTP 정책 확인
- [ ] 프론트가 해당 환경의 URL/Publishable key만 사용하는지 확인

## 배포

- [ ] GitHub Environment 또는 기록된 수동 승인 완료
- [ ] 한 명만 마이그레이션 실행
- [ ] Production에서 reset, seed, migration repair를 실행하지 않음
- [ ] 적용된 migration version과 명령 결과 보존

## 클라우드 스모크 테스트

환경별 테스트 계정만 사용합니다. Production에서는 데이터 삭제·초기화·동시성 파괴 테스트를 실행하지 않습니다.

- [ ] 이메일/비밀번호 회원가입 정책이 설정대로 동작
- [ ] 이메일 확인 활성 시 확인 전/후 로그인 동작
- [ ] 로그인과 JWT 발급·refresh
- [ ] 회원가입 후 프로필이 정확히 1개 생성
- [ ] `get_my_profile()` 호출
- [ ] `complete_onboarding()` 반복 호출이 동일 시각 반환
- [ ] `list_crops(p_energy)`와 고정 작물 6종/UUID/목표 초 확인
- [ ] 사용자 A가 사용자 B 프로필을 읽거나 변경할 수 없음
- [ ] 익명 사용자가 보호 RPC를 호출할 수 없음
- [ ] DB 연결이 SSL과 승인된 자격 증명으로만 동작
- [ ] 프론트 CORS/Site URL/Redirect URL이 해당 환경과 일치
- [ ] Secret이 브라우저 요청·번들·로그에 없음

## 배포 후

- [ ] `migration list --remote`가 저장소와 일치
- [ ] DB lint/advisors 결과 검토
- [ ] Auth 4xx/429/5xx, Data API 오류, DB 로그 확인
- [ ] 성능·연결 수·DB 크기·rate limit 관찰
- [ ] 문제가 없다는 관찰 담당자 확인 후 릴리스 종료
- [ ] 문제 발생 시 [마이그레이션 런북](migration-runbook.md)의 복구 절차 실행

## B 기능 병합 이후 추가

- 밭 생성과 복합 소유권 FK
- 집중 세션 상태 전이 및 0초 `seed_saved`
- 수확 1회 보장과 동시성
- 사용자 시간대 `record_date`
- 자동 수확 Cron의 실행 역할·멱등성·실패 로그

이 항목들은 B 스키마가 병합되기 전에는 검증 완료로 표시하지 않습니다.
