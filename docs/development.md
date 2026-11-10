# 개발 및 협업 규칙

## 최초 저장소 초기화

원격 저장소에 커밋이 없으므로 로컬 `main`에서 최초 부트스트랩 커밋을 만든 뒤 원격 `main`을 생성해야 합니다. 이번 작업에서는 커밋과 push를 수행하지 않습니다.

최초 부트스트랩을 검토하고 승인한 뒤 다음 순서로 진행합니다.

```bash
git add .
git commit -m "chore: bootstrap Supabase backend"
git push -u origin main
git switch -c develop
git push -u origin develop
```

첫 커밋 전에는 Git이 가리킬 커밋이 없으므로 `develop`을 정상 브랜치로 만들 수 없습니다.

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
- 원격 프로젝트가 확정되기 전에는 `supabase link`를 실행하지 않습니다.

## 보안

- `.env.example` 외의 환경 파일은 커밋하지 않습니다.
- secret key, legacy service-role key, DB 비밀번호, access token은 클라이언트나 저장소에 노출하지 않습니다.
- publishable key는 공개 클라이언트용이며, 데이터 권한은 RLS로 제한합니다.
- 실제 사용자 데이터는 seed나 테스트 fixture로 사용하지 않습니다.
