# Navigation

도보·자전거·대중교통 특화 내비 + 서울 실시간 데이터 지도. iOS 26 / Xcode 26 / Swift 6.
UIKit programmatic + MVVM + Coordinator + Combine.
제품 방향의 근거: Documents/Work/260614_service_review/04_positioning_decision.md

## 규범

개발 규칙은 `.specify/memory/constitution.md`에 있다. **코드를 쓰기 전에 읽는다.**
(Swift 6 동시성, MVVM/Combine, YAGNI, 로그 기반 검증, iOS 26 API, 아키텍처 제약, 문서 워크플로우)

## 문서 지도

| 찾는 것 | 위치 |
|---|---|
| 현재 피처의 현행 설계·요구·태스크 | `specs/NNN-*/` (아래 speckit 블록이 현재 폴더를 가리킴) |
| 과거 작업의 배경·결정·결과 | `Documents/Work/YYMMDD_주제/` — 폴더명이 곧 시간순 인덱스 |
| 그 작업이 무엇이고 어떻게 끝났나 | 각 폴더의 `completion.md` 상단 고정 헤더 |
| 현행 아님(2026-02 초기 문서) | `Documents/Archive/` — **근거로 인용 금지** |
| 정적 데이터 파이프라인 | `Navigation/Scripts/TransitData/SOURCE.md` |

## 작업 흐름

`Documents/Work/YYMMDD_주제/requirements.md`(사람 언어) → speckit(`specs/`에 spec·plan·tasks)
→ 브랜치 + 단계별 커밋 → 같은 Work 폴더에 `completion.md` → PR.
**Work/ = 사람의 맥락(왜·무엇을·결과). specs/ = 기계의 계약(어떻게·검증). 설계가 바뀌면 spec.md를 고친다.**

## 자주 틀리는 것

- 시뮬레이터: `iPhone 17 Pro` (iOS 26). `iPhone 16 Pro` 아님
- 테스트: `Navigation/` 디렉터리에서 `xcodebuild test -project Navigation.xcodeproj -scheme Navigation -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- 현장 로그 원본(`*.ndjson`)은 커밋하지 않는다. 테스트가 읽는 세션만 `Navigation/NavigationTests/ParkingFinder/Fixtures/`로 승격
- `NavigationSessionManager`는 CarPlay 폴더에 있지만 아이폰 내비 세션의 핵심 — 삭제 금지

<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan

**Current Feature**: 지하주차장 내 차 찾기 (기둥코드 OCR 스캔 등록 + AR 랜드마크 맵 격자 추정 방향 안내)
**Plan**: specs/005-parking-car-finder/plan.md
**Spec**: specs/005-parking-car-finder/spec.md
**Data Model**: specs/005-parking-car-finder/data-model.md
<!-- SPECKIT END -->
