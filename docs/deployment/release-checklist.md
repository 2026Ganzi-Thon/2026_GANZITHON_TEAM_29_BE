# Staging 최초 배포 체크리스트

## 2026-11-13 사전 검증

- [x] \`focus-farm-staging (klanbfvywwudprunaqdf)\`, Seoul, PostgreSQL 17.11
- [x] CLI 3.1.0 인증 및 IPv4 Session Pooler
- [x] 원격 migration·업무 객체 0개
- [x] 로컬 DB reset
- [x] pgTAP 103개
- [x] Auth/RPC 통합 테스트
- [x] DB lint 오류 없음
- [x] npm audit 취약점 0개
- [x] dry-run 후보 3개
- [ ] 집중 세션 완료·만료 상태 확정 문제 해결
- [ ] 같은 SHA의 GitHub Actions 성공
- [ ] A/B 리뷰와 실제 배포 승인
- [ ] 실제 마이그레이션 적용

미완료 항목 때문에 현재는 **배포 보류**입니다.

## 배포 전

- [ ] 승인된 \`develop\` SHA 또는 릴리스 후보와 배포 SHA 일치
- [ ] 프로젝트 이름·Ref를 두 명이 대조하고 GoldenLook이 아님을 확인
- [ ] 원격 migration list와 업무 객체 재확인
- [ ] dry-run 목록과 승인 목록의 순서 일치
- [ ] RLS, GRANT/REVOKE, definer 함수와 트리거 검토
- [ ] \`focus_sessions.crop_id\` FK 인덱스 advisor INFO 수용 또는 후속 마이그레이션 결정
- [ ] Staging 데이터와 복구 담당자 확인
- [ ] Confirm email OFF와 신규 가입 허용 확인
- [ ] 프론트가 Staging URL/Publishable key만 사용

## 배포와 스모크 테스트

- [ ] 기록된 수동 승인 후 한 명만 \`db push --skip-vault --remote\`
- [ ] reset, seed, repair와 원격 초기화 미실행
- [ ] 적용 version과 출력 보존
- [ ] 가입 직후 세션 발급, nickname 프로필 생성
- [ ] A RPC 3개와 작물 6종
- [ ] \`ensure_farm()\` 멱등성과 밭 12개
- [ ] 타 사용자 접근 거부와 RLS 격리
- [ ] 집중 시작·조회·일시정지·재개
- [ ] 익명 접근 차단
- [ ] Auth/API/DB 로그 확인

원격 테스트 계정 생성은 별도 승인 후 수행합니다. 문제 발생 시 추가 배포를 중단하고 [마이그레이션 런북](migration-runbook.md)의 데이터 보존 우선 복구 절차를 따릅니다.
