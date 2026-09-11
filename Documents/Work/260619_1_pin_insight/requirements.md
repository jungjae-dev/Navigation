# 요구사항 — 핀 기반 동네 인사이트

출처: Documents/Work/260614_service_review/07_killer_features.md (PART 1), 03_seoul_opendata.md
제품 방향: 도보 메인 + 살아있는 데이터 지도 (무료+광고). 서울 공공데이터만 사용.
대상 단계: speckit-specify 입력 브리프

---

## 1. 개요 / 목적
지도에 핀을 찍으면 **그 위치에 살면/가면 어떨지**를 서울 공공데이터로 한 화면(카드)에 종합해 보여준다.
- 핵심 기술 전제: 점(좌표) → **행정동 매핑**(Kakao `coord2regioncode`) + **반경 질의**(POI 실거리). 행정구역 경계 일괄 전처리 불필요(가벼움).
- 거대앱(네이버·카카오)은 "상호·리뷰"만 주고 **생활환경 종합은 공백** → 차별점.

## 2. 목표 / 비목표
- 목표: 임의 지점의 생활·환경·교통·편의·녹지·안전·행사 정보를 한 화면(팝업)에. 관심 동네 저장.
- 비목표(MVP): **두 지점 비교(→ Later)**, 종합 점수(0~100) 환산(→ Later), 서울 외 지역, 골목 단위 정밀도.

## 3. 사용자 시나리오
- (이사 준비) 후보 동네에 핀 → 환경·교통·안전 한눈에 확인 (두 동네는 차례로 핀 찍어 확인)
- (탐색) 처음 가는 동네에 핀 → "여긴 어떤 동네?"
- (저장) 관심 동네 즐겨찾기 → 나중에 다시 확인

## 4. 기능 요구사항 (FR)
- **FR-1 핀 드롭**: 지도 롱프레스 또는 검색결과/MapItem 선택 시 좌표 확보. 핀 마커 표시.
- **FR-2 행정동 판별**: 좌표 → Kakao `coord2regioncode`로 자치구·행정동 코드/명 획득. (실패 시 역지오코딩 폴백)
- **FR-3 인사이트 팝업**: **기존 POI 팝업(`MapItemDetailViewController`)을 재사용** — 롱프레스 핀 → POI 탭과 동일한 detent 시트가 뜨고, 인사이트가 그 팝업의 콘텐츠로 표시. 헤더 = 행정동 주소 + **한 줄 요약**("조용하고 공기 좋은 주거 동네" — 규칙 기반). 푸터 = 경로 버튼(기존) + 저장/공유.
- **FR-4 생활 활기 카드**: 생활인구 등급(활발/보통/한적) + 시간대 미니 추이. 데이터: 생활인구(행정동).
- **FR-5 환경 카드**: 실시간 대기질 등급(통합대기환경지수). 데이터: 실시간 대기환경(자치구). (소음은 S-DoT 좌표 비공개로 MVP 제외 → Later 대체)
- **FR-6 교통 카드**: 최근접 지하철역 도보 X분, 가까운 버스정류장, 따릉이 대여소(실시간 잔여). 반경 질의.
- **FR-7 편의 카드**: 반경 내 병원·약국·마트·편의점·공중화장실 개수 + 최근접 거리.
- **FR-8 녹지·산책 카드**: 최근접 공원/둘레길.
- **FR-9 안전 카드**: 야간 CCTV·보안등 밀도(반경), 자치구 범죄 수준, **침수 이력**(점-폴리곤 판정).
- **FR-10 지금 카드**: 주변에서 열리는 문화행사(반경 + 기간 필터).
- **FR-11 경로 버튼**: 팝업 푸터의 경로 버튼 → 기존 RoutePreview 흐름으로 이 지점까지 길찾기.
- **FR-12 관심 동네 저장**: SwiftData 저장. (Later: 변화 알림 구독)
- **FR-13 공유**: 인사이트 요약 카드 이미지/링크 공유.

## 5. 데이터 소스 (API 검증 완료 2026-06-19)
| 카드 | 데이터셋(검증) | 단위/좌표 | 상태 |
|---|---|---|---|
| 생활 활기 | 행정동 생활인구 OA-14991 | 행정동코드(좌표X) | ✅ coord2regioncode로 매칭 |
| 환경-대기 | RealtimeCityAir OA-1200 | 자치구(좌표X) | ✅ 자치구 매칭 |
| 환경-소음 | ~~S-DoT OA-15969~~ | 좌표 **비공개** | ❌ 좌표결합 불가 → 카드 제외/대체(Later) |
| 교통-따릉이 | 따릉이 OA-15493 | 좌표+잔여 | ✅ 반경 |
| 교통-지하철 | 1-8호선 역사좌표 **OA-22534**(서울 단독, CSV) | 좌표(위경도) | ✅ 반경, 변환 불필요 |
| 교통-버스 | 버스정류소 위치 **OA-15067**(파일)/**OA-1094**(OpenAPI) | 좌표(EPSG:5179 TM 가능성→변환) | ✅ 반경 |
| 편의 | 약국(NMC 15000576, WGS84)·공중화장실(파일)·공공와이파이 OA-20883 | 좌표 | ✅ 반경(일부 파일적재·좌표변환) |
| 녹지 | 도시공원 표준 `15012890` | 좌표 | ✅ 반경 (둘레길 OA-11986=누리4 금지→**제외**) |
| 안전 | 안심이 CCTV(OA-20923)+보안등(표준)+침수흔적도 OA-15636(폴리곤)+5대범죄 OA-13532 | 좌표/면/**자치구** | ⚠️ 방범CCTV OA-21097=누리4 금지→안심이 대체; 범죄=자치구 단위만 |
| 지금 | 문화행사 OA-15486 | 좌표+일정 | ✅ 반경 |

**검증 메모**:
- 라이선스: 대부분 **공공누리 1유형(상업 OK)**. 단 **둘레길(OA-11986)·방범CCTV(OA-21097)=4유형(상업 금지)** → 위 대체본 사용.
- 좌표계 **혼재**(약국 TM EPSG:5174/5174, 버스 GRS80) → **WGS84 변환 로직 필수**.
- OpenAPI 없음(파일 선적재 필요): 침수흔적도(ZIP), 공중화장실(CSV).
- 핀 좌표→행정동/자치구 매칭의 **핵심 접착제 = Kakao coord2regioncode**(무료 10만/일).
- ✅ **지하철·버스 좌표는 서울 열린데이터광장 단독으로 충당 가능**(OA-22534 / OA-15067·OA-1094) — data.go.kr 보완 불필요. 단 버스는 좌표계 변환 검토.

## 6. UI/UX 상세
- 카드형 리스트(스크롤). 각 카드: 아이콘 + 제목 + 핵심 값(배지/색) + 보조 설명.
- 등급 색상: Theme.Palette 경유(인디고 액센트), WCAG AA 준수.
- **카드별 독립 로딩 상태**(스켈레톤) — 느린 API가 전체를 막지 않게.
- 팝업 콘텐츠 영역에 카드들을 세로 스크롤로 배치(POI 상세와 동일 scaffold).

## 7. 기술 구현 노트 (기존 아키텍처 정합)
- 패턴: MVVM + Coordinator + Combine, 상태는 `CurrentValueSubject<T, Never>`.
- 신규 서비스: `NeighborhoodInsightService` (각 서울 API aggregator). 카드별 fetch를 `async let`/`TaskGroup`으로 **병렬** 호출.
- 캐싱: 실시간(대기질·따릉이) 분 단위, 준정적(시설) 일 단위, 정적(화장실 등) 앱 내장.
- 지도 연동: 기존 MapViewController 핀/롱프레스 제스처.
- 점→행정동: 기존 Kakao 클라이언트 확장(`coord2regioncode`).

## 8. 비기능 요구사항
- 성능: 핀 탭 후 첫 카드 1.5초 내, 전체 3초 내(병렬). 부분 실패 graceful.
- 오프라인: 정적 데이터(화장실·공원 등) 내장으로 일부 동작.
- 에러: API 실패 카드는 "정보 없음"으로 표시(전체 중단 금지).
- 프라이버시: 위치는 조회용, 저장은 사용자 동의 즐겨찾기만.

## 9. 엣지 케이스
- 서울 외 좌표 → "현재 서울만 지원" 안내.
- 데이터 없는 행정동/측정소 먼 경우 → 보간 또는 "정보 없음".
- API rate limit → 캐시/재시도/백오프.
- 동일 위치 반복 탭 → 캐시 활용.

## 10. 확인 필요 (API 검증 반영)
- ✅ **해결**: 대부분 좌표 포함 확인 / 범죄=자치구 단위 확정(행정동 불가) / 행정동 경계=`vuski/admdongkor` GeoJSON 자유이용 확보 / 소음(S-DoT)=좌표 비공개로 제외.
- 남은 검증: ① 좌표계(TM·GRS80→WGS84) 변환 처리 ② 파일 선적재(침수흔적도·공중화장실) 파이프라인 ③ 약국/병원 API 응답 필드 verbatim 1회 확인 ④ 소음 카드 Later 대체안(자치구 단위 등).

## 11. MVP 범위
- MVP: FR-1~10(원시값 카드 6~7장) + FR-11(경로 버튼) + FR-12(저장).
- Later: 두 지점 비교, 종합 점수화, 변화 알림 구독, 한 줄 요약 고도화, 부동산·이사 제휴 연동.

## 12. 현 앱 통합 (Integration)
현 구조: 탭바 없음 → `UINavigationController → HomeViewController(루트)` + 내장 `MapViewController` + `DrawerContainerManager`(하단 시트 스택). 화면 전환은 **AppCoordinator** 단일 허브. **신규 화면 0개 — 기존 POI 팝업을 그대로 재사용한다.**

- **진입점**: 지도 **롱프레스 → 핀** → `MapViewController`에 콜백 `onLongPressDropped((CLLocationCoordinate2D)->Void)` 추가 → `AppCoordinator`가 좌표로 콘텐츠 생성 → **기존 `showMapItemDetail(content:)` 호출**(POI 탭과 동일 팝업).
- **콘텐츠 = 새 `MapItemContent` 구현**: `Feature/MapItemDetail/Content/PinInsightContent.swift` (따릉이 `BikeStationContent`·버스 `BusStopContent`와 같은 위치/패턴).
  - 헤더: 행정동 주소 / 한 줄 요약
  - 콘텐츠뷰: 인사이트 카드들(생활·환경·교통·편의·녹지·안전·지금) 세로 스크롤
  - 푸터(`FooterAction`): **경로**(기존 길찾기 그대로) + 저장 + 공유
- **경로 연결(FR-11)**: 푸터 경로 → `content.onRouteTapped` → 기존 `AppCoordinator.showRoutePreview(to:)` → `RoutePreviewDrawerViewController`.
- **데이터 로딩**: 따릉이 레이어 패턴 차용 — `InsightViewModel`(`CurrentValueSubject`) + `NeighborhoodInsightService`(서울 API aggregator, `TaskGroup` 병렬). 카드별 독립 로딩.
- **점→행정동**: 기존 Kakao 클라이언트에 `coord2regioncode` 확장.
- **신규 파일(축소)**: `PinInsightContent.swift`(+카드 뷰), `Service/SeoulOpenAPI/Insight/NeighborhoodInsightService.swift`, `InsightViewModel`. + `MapViewController.onLongPressDropped` 콜백 / `AppCoordinator` 배선.
- **재사용**: `MapItemDetailViewController`, `MapItemContent`, `DrawerFooterProviding`(푸터), `DrawerContainerManager`(detent peek/half/full), RoutePreview 흐름 — 전부 그대로.
- **디자인 정합(002, in-scope)**: `Theme` 토큰 경유, 인디고 액센트 절제, Dynamic Type(고정폰트 금지), 라이트/다크 검증.
</content>
