<!--
SYNC IMPACT REPORT
==================
Version change: N/A → 1.0.0 (initial)
Added sections: Core Principles, Architecture Constraints, Development Workflow, Governance
Templates requiring updates:
  ✅ constitution-template.md (source)
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

## Development Workflow

- **브랜치**: feature/{issue번호}-{기능명} 형식
- **검증**: 각 Phase 완료 시 체크리스트 기반 시뮬레이터 검증 후 커밋
- **주석**: 비자명한 이유(숨겨진 제약, 버그 우회)가 있을 때만 작성. 코드가 무엇을 하는지 설명하는 주석 금지
- **테스트**: Swift Testing 프레임워크 사용 (`import Testing`, `#expect`, `@Test`)

## Governance

이 Constitution은 프로젝트의 모든 개발 관행보다 우선한다. 원칙 수정 시 버전을 올리고 영향받는 템플릿을 함께 업데이트해야 한다. 모든 구현은 Core Principles 준수 여부를 검토한다.

**Version**: 1.0.0 | **Ratified**: 2026-06-03 | **Last Amended**: 2026-06-03
