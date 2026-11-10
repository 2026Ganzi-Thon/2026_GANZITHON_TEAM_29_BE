# Phase 2 구현 범위

Phase 2는 A 담당 기반 도메인만 구현합니다.

## 구현 완료

- `profiles`: Auth UUID PK/FK, 닉네임, 시간대, 온보딩 시각, 생성 시각
- Auth 트리거: 메타데이터 닉네임으로 멱등적 프로필 생성
- `crops`: UUID 카탈로그와 안정적 기본 작물 6종
- `get_my_profile()`, `complete_onboarding()`, `list_crops(p_energy)`
- RLS, 직접 쓰기 차단, 함수 실행 권한 최소화
- pgTAP 37개 검증과 로컬 Auth/RPC 통합 테스트

## 안전한 MVP 기본값—검토 필요

- 닉네임 누락·공백: `농부`
- 닉네임: trim 후 1~30자, 회원가입 메타데이터가 길면 30자로 잘라 트리거 실패를 방지
- 시간대 기본값: `Asia/Seoul`, 1~64자
- 시간대는 현재 길이만 검증합니다. IANA 식별자 검증/변경 RPC는 팀 합의 후 추가합니다.
- 이메일 확인 여부, redirect URL, Auth 오류 매핑은 운영 프로젝트 확정 후 합의합니다.

## 제외

- 밭, 집중 세션, 일시정지, 씨앗, 수확, 휴식, 기록 초기화, Cron
- B의 `ensure_farm()` 및 나머지 RPC
- `get_my_farm()`, `get_focus_history(p_period)`
- 프론트엔드 코드
- 원격 Supabase 연결·배포

농장/기록 조회는 B 쓰기 모델과 상태 전이가 확정된 뒤 구현합니다.
