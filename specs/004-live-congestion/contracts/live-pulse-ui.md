# UI/Service Contract: 실시간 도시 혼잡 지도 (Live City Pulse)

내부 iOS 앱이라 외부 API 계약 없음. 신규/변경 컴포넌트의 입력·동작 계약을 tasks·테스트 기준으로 정의.

## C1. MapControlButtonsView (진입점, FR-001)
- 신규 콜백 `var onLivePulseTapped: (() -> Void)?` + 전용 버튼(맥박/혼잡 아이콘, `configureButton`+stackView). 기존 버튼 동작 보존.

## C2. AppCoordinator (모드 전환)
- `showLivePulse()`: 따릉이·버스 레이어 on/off 저장→OFF, 표준 지도 고정, 카메라 유지 → `MapViewController.setCongestion(...)` → `pushDrawer(LivePulseDrawerVC)`. 진입 시 가시 영역 로딩 트리거.
- `exitLivePulse()`: `popDrawer` → `clearCongestion()` → 레이어 복원(토글 값 불변) → 홈 드로어 복귀.
- 마커 탭 → `showMapItemDetail(content: CongestionContent)`(핀 인사이트 팝업 재사용, US3).

## C3. MapViewController (마커 레이어, FR-002/009/010)
- `setCongestion(places:colorProvider:)`: 핫스팟 좌표에 혼잡 마커 추가, 표준 지도 고정, 카메라 유지.
- `clearCongestion()`: 마커 제거.
- `updateCongestionColors()`: offset 변경 시 마커 색 갱신.
- `onRegionChanged`(L460, 기존) 구독 → 가시 영역 핫스팟 로딩 요청(FR-007a).
- `rendererFor`는 불필요(마커=annotation). annotation view는 bike/bus 패턴.

## C4. LivePulseViewModel (상태/데이터, 헌법 II)
- `state: CurrentValueSubject<TimelineState, Never>`(offsetHour, isRefreshing).
- `places: CurrentValueSubject<[CongestionPlace], Never>`(가시 영역 누적, TTL).
- `setOffset(_:)` / `refresh()` / `loadVisible(rect:)`.
- `markerLevel(place:offset:) -> CongestionLevel`: offset 0=live, N=forecast[N-1].
- `maxOffset`: 가시 장소 예측 길이의 안전 최소.

## C5. LivePulseDrawerViewController (컨트롤, FR-004/007)
- 시간 슬라이더(지금 0 → +N) + 기준 시각 라벨(FR-003) + 새로고침 버튼.
- 입력→ViewModel; 상태 구독→슬라이더/라벨 동기화. 닫기→`exitLivePulse()`.

## C6. CitydataService (데이터, FR-005/007a/012)
- `fetchPlaces(areaNames:) async -> [CongestionPlace]`: `SeoulAPIClient`로 `citydata_ppltn` **장소별 병렬 호출**(타임아웃·부분실패 허용 → 받은 것만 반환). 장소별 **TTL 캐시**.
- `catalog`: 번들 HotspotCatalog(장소명→좌표) 로드.
- `visibleAreas(in rect:) -> [String]`: 카탈로그 ∩ 가시 영역.
- 전체 실패/오프라인 → 빈/캐시 + 상태 플래그.

## C7. CongestionContent: MapItemContent (상세, FR-006)
- 실시간 혼잡 단계 + 인구 + 예측 곡선 + 기준 시각. SwiftUI 미니 차트. 기존 상세 팝업 슬롯에 주입.

## C8. 혼잡 단계 매핑 (순수 함수, 테스트 대상)
- `CongestionLevel(rawText:)`: "붐빔/약간 붐빔/보통/여유/(미상)" → enum(공백·표기 변형 허용).
- `color(for level:)`: enum → Theme 색(WCAG). unknown→표시 안 함/중립.
- 단위 테스트: 4단계 파싱, 변형/결측 → unknown, offset→level 선택(0=live, N=forecast).
