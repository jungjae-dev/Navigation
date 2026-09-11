# Quickstart 검증: 실시간 도시 혼잡 지도 (Live City Pulse)

헌법 IV(로그 기반) — 시뮬레이터 `iPhone 17 Pro`(iOS 26) + 로그. 혼잡 단계 파싱·offset 선택 등 순수 로직은 Swift Testing.

## 사전 준비
- 번들에 HotspotCatalog(장소명→좌표) 동봉.
- `Secrets.xcconfig`의 SEOUL_OPEN_API_KEY 유효(citydata_ppltn 동일 키).

## S1. 진입/종료 (US1 / SC-001, SC-005)
1. 홈 → 혼잡 버튼 → **기대**: 가시 영역 핫스팟에 혼잡색 마커 + 시간 드로어 + 기준 시각. 따릉이/버스 OFF, 위성→표준, 카메라 유지.
2. 드로어 닫기 → **기대**: 마커 사라짐, 진입 전 레이어·홈 드로어·영역 복원, 토글 값 불변.

## S2. 뷰포트 로딩 (FR-007a)
1. 지도 다른 구로 이동 → **기대**: 그 영역 핫스팟 추가 로딩. **로그**: `[LivePulse] visible=8 fetch=8 cacheHit=…`.
2. 같은 영역 재진입(5분 내) → **기대**: 캐시 사용(재호출 없음).

## S3. 예측 슬라이더 (US2 / SC-002, SC-006)
1. 슬라이더 +3h → **기대**: 마커 색이 3시간 뒤 예측으로 0.3초 내 갱신(네트워크 없이).
2. "지금"으로 → 실시간 복귀.
3. 예측 부족 장소 → 그 offset에서 중립.

## S4. 부분 실패/오프라인 (FR-011/012 / SC-004)
1. 일부 장소 실패 유도 → **기대**: 받은 것만 표시, 빈 곳 색 없음.
2. 비행기모드 → **기대**: 마지막 캐시 + 기준 시각 + 새로고침 유도. 전체 실패 시 안내.

## S5. 장소 상세 (US3)
1. 마커 탭 → **기대**: 실시간 혼잡 + 예측 곡선 + 기준 시각.

## S6. 신선도 (FR-003 / SC-003)
1. 화면에 항상 기준 시각 노출 확인.

## S7. 단위 테스트
- 혼잡 단계 파싱(4단계+변형+결측→unknown) / offset→level(0=live, N=forecast[N-1]) / 가시영역 필터.

## 빌드/테스트
```bash
xcodebuild -project Navigation/Navigation.xcodeproj -scheme Navigation \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild test -project Navigation/Navigation.xcodeproj -scheme Navigation \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:NavigationTests/CongestionLevelTests
```
