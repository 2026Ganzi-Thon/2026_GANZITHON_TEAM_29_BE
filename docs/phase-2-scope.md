# Phase 2 구현 범위

Phase 2는 A 담당 기반 도메인만 구현합니다.

## 포함

1. 이메일/비밀번호 Auth 정책 확정 및 로컬 설정 반영
2. 프로필 스키마와 `auth.users` 연계 방식 구현
3. `get_my_profile()` 구현
4. `complete_onboarding()` 구현
5. 작물 카탈로그 최소 스키마와 개발용 seed 구현
6. `list_crops(p_energy)` 구현
7. 위 테이블과 RPC의 RLS, `GRANT`, 함수 실행 권한 구현
8. 인증 사용자 본인 접근, 타 사용자/익명 거부, 입력 경계에 대한 pgTAP 테스트
9. RPC 계약 문서의 Phase 2 관련 `TBD`를 합의된 값으로 갱신

## 선행 조건

- 원격과 분리된 로컬 컨테이너 런타임 준비
- 프로필 필드, 온보딩 완료 조건과 프로필 생성 시점 확정
- 이메일 확인 여부와 Auth redirect URL 확정
- `p_energy` 타입, 허용 범위와 정렬 규칙 확정
- 작물 카탈로그 필드와 초기 seed 목록 확정
- 반환 JSON/row 타입과 공통 오류 코드 확정
- B 담당자의 GitHub 사용자명과 마이그레이션 리뷰 절차 확정

## 제외

- 밭, 집중 세션, 일시정지, 씨앗, 수확, 휴식, 초기화, Cron
- `get_my_farm()`과 `get_focus_history(p_period)` 구현
- 프론트엔드 코드
- 원격 Supabase 배포

농장 및 기록 조회 RPC는 B의 쓰기 모델과 상태 전이가 확정된 후 구현합니다.
