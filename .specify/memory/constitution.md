<!--
SYNC IMPACT REPORT
==================
Version change: 1.0.0 → 1.1.0
Added sections: Documentation Workflow
Modified sections: Architecture Constraints (+4 제약: NDJSON 포맷, 디자인 토큰, 맵매칭 heading, 리루팅 가드)
Templates requiring updates:
  ✅ plan-template.md (no principle-specific references to update)
  ✅ spec-template.md (no principle-specific references to update)
  ✅ tasks-template.md (no principle-specific references to update)
Deferred TODOs: none
-->

# Navigation Constitution

## Core Principles

### I. Swift 6 Concurrency (NON-NEGOTIABLE)
모든 코드는 Swift 6 strict concurrency를 준수해야 한다. `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`가 적용되어 있으며, delegate는 `nonisolated` + `MainActor.assumeIsolated` 패턴을 사용해야 한다. Data race는 허용하지 않는다.

### II. MVVM + Coordinator + Combine
아키텍처는 UIKit programmatic + MVVM + Coordinator + Combine을 따른다. 상태는 `CurrentValueSubject<T, Never>`로 노출하며 `@Published`는 사용하지 않는다. Coordinator가 화면 전환을 담당하고, ViewModel은 비즈니스 로직만 보유한다.

### III. 단순성 우선 (YAGNI)
현재 요구사항만 구현한다. 추측 기반 추상화, 미래를 위한 플래그, 하위 호환 shim은 금지한다. 유사한 3줄이 조기 추상화보다 낫다. 에러 핸들링은 실제 발생 가능한 케이스만 처리한다.

### IV. 로그 기반 검증
각 Phase는 Logger를 통한 로그 포인트로 검증한다. 기능 완료 기준은 단순 빌드 성공이 아니라 실기기/시뮬레이터에서 예상 로그 출력 확인이다.

### V. iOS 26 / Xcode 26 대응
`MKPlacemark` 대신 `MKMapItem(location:address:)`, `mapItem.location.coordinate` 사용. CarPlay API는 `add()` / `trip:` 파라미터를 사용한다. 시뮬레이터는 `iPhone 17 Pro` (iOS 26)를 사용한다.

## Architecture Constraints

- **싱글턴**: `LocationService`, `NavigationSessionManager`는 싱글턴으로 유지
- **파일 참조**: PBXFileSystemSynchronizedRootGroup(auto-sync) 사용 — pbxproj에 수동 파일 참조 추가 금지
- **API 키**: `Secrets.xcconfig`에 관리, Git 커밋 금지
- **정적 데이터**: 버스/지하철 정류장·호선 데이터는 GitHub Gist에서 다운로드 후 `Documents/TransitData/`에 캐시, 앱 번들 fallback 제공
- **지도 POI**: 따릉이, 버스, 지하철 레이어는 POI 팝업으로 통합 관리
- **기록 포맷**: GPS·관측 레코딩은 NDJSON(.ndjson)이 표준 — GPX 아님. `LocationRecorder`/`LocationFileReader` 사용, 저장 위치 `Documents/Recordings/`
- **디자인 토큰**: 색상은 항상 `Theme.Colors` 등 Theme 토큰 경유(하드코딩 금지), WCAG AA 대비 준수. (`Theme.Palette` 통합은 T022 계획 — 아직 코드에 없음)
- **맵매칭 heading**: GPS course(`CLLocation.course`)만 사용 — 나침반(`headingPublisher`)은 UserLocationPresenter(.compass) 전용, 내비/매칭 파이프라인 연결 금지
- **리루팅 가드**: 시간창 기반 리루팅 차단 추가 금지(도입 후 제거된 이력). `isRerouteInProgress`·`maxRerouteAttempts=3`·연속 이탈 3회 확정·출발 보호(5초/35m)로 충분

## Development Workflow

- **브랜치**: feature/{issue번호}-{기능명} 형식
- **검증**: 각 Phase 완료 시 체크리스트 기반 시뮬레이터 검증 후 커밋
- **주석**: 비자명한 이유(숨겨진 제약, 버그 우회)가 있을 때만 작성. 코드가 무엇을 하는지 설명하는 주석 금지
- **테스트**: Swift Testing 프레임워크 사용 (`import Testing`, `#expect`, `@Test`)

## Documentation Workflow

- **역할 분담**: `Documents/Work/` = 사람의 맥락(왜·무엇을·결과), `specs/` = 기계의 계약(어떻게·검증), `CLAUDE.md` = 이정표. 설계가 바뀌면 현재 피처의 `spec.md`를 고친다
- **수명**: 살아있는 문서는 3개뿐(CLAUDE.md·이 문서·현재 피처 spec) — 틀리면 그 자리에서 고친다. `Documents/Work/YYMMDD_주제/`는 append-only 이력 — 완료 후 수정·이동 금지(상호참조 경로가 계약), 정정은 새 날짜 폴더에서 링크. `Documents/Archive/`는 동결 — 인용 금지
- **작업 파일**: 시작 시 `requirements.md`, 종료 시 `completion.md`(고정 헤더 5줄: 상태·기간·브랜치/PR·스펙·후속). speckit 미사용 작업만 `plan.md`, 로그 분석은 `analysis.md`. 그 외 자유
- **인덱스 없음**: 폴더명(`YYMMDD_주제`)과 completion.md 헤더가 인덱스다. 전역 INDEX.md를 만들지 않는다
- **데이터 승격**: 현장 로그(.ndjson)는 커밋하지 않는다 — 테스트가 읽는 세션만 `NavigationTests/…/Fixtures/`로 승격. 3자 원본(pdf/xlsx/shp/zip)은 출처 URL·취득일만 문서에 남긴다
- **메모리 규칙**: AI 자동 메모리에는 상태와 포인터만 — 사실(제약·규범)은 이 문서·코드 주석·Work 문서로 승격하되, 코드 주석 승격은 해당 제약이 그 코드에 실재할 때만

## Governance

이 Constitution은 프로젝트의 모든 개발 관행보다 우선한다. 원칙 수정 시 버전을 올리고 영향받는 템플릿을 함께 업데이트해야 한다. 모든 구현은 Core Principles 준수 여부를 검토한다.

**Version**: 1.1.0 | **Ratified**: 2026-06-03 | **Last Amended**: 2026-09-11
