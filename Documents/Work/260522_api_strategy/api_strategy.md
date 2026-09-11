# API 전략 결정 — 네비게이션 앱

**결정일**: 2026-05-22  
**배포 대상**: 한국 (App Store KR)

---

## 결정 사항

| 기능 | API | 이유 |
|------|-----|------|
| 주변 검색 (키워드/카테고리) | **카카오 로컬 API** | 한국 POI 품질 압도적, 약관 적합 |
| 주소/좌표 변환 (Geocoding) | **카카오 로컬 API** | 동일 |
| 자동차 길찾기 | **Apple MapKit (MKDirections)** | 제휴 불필요, 무료, 약관 적합 |
| 도보 길찾기 | **Apple MapKit (MKDirections)** | 카카오 도보 API는 제휴 계약 필수 |

---

## 카카오 로컬 API

### 사용 엔드포인트

| 엔드포인트 | 용도 | 파일 |
|-----------|------|------|
| `GET /v2/local/search/keyword.json` | 키워드 주변 검색 | `KakaoSearchService.swift` |
| `GET /v2/local/search/category.json` | 카테고리 주변 검색 | `KakaoSearchService.swift` |
| `GET /v2/local/search/address.json` | 주소 → 좌표 변환 | `KakaoGeocodingService.swift` |
| `GET /v2/local/geo/coord2address.json` | 좌표 → 주소 변환 | `KakaoGeocodingService.swift` |

### 무료 쿼터

- 일 **100,000건** / 엔드포인트 (앱 단위)
- 월 **3,000,000건** 합산
- 초과 시: 키워드/카테고리 **2원/건**, 좌표변환 **0.5원/건**

### 파라미터 제한

| 파라미터 | 최대값 |
|---------|--------|
| `size` (페이지당 결과) | 15개 |
| `page` | 45 |
| `radius` | 20,000m |
| **한 쿼리 최대 결과** | **45개** |

### 약관 핵심 제약 (위반 시 API 차단)

1. **실시간 호출 필수** — 응답 데이터를 DB/디스크에 영구 저장 금지
   - 즐겨찾기·최근검색에 좌표/이름만 저장하는 것은 허용 (사용자 선택 행동 결과)
   - API 응답 배열 통째로 캐싱 금지
2. **배치/크롤링성 호출 금지** — 짧은 시간 집중 호출 시 429 + 정책 위반 처리
3. **출처 표기 의무 없음** — REST API는 로고·워터마크 의무 없음

### 현재 코드 약관 준수 상태

- ✅ 응답 → 메모리(`CurrentValueSubject`)만 전달, 디스크 저장 없음
- ✅ 즐겨찾기/검색기록 — 이름·주소·좌표만 추출 저장 (`providerRawData = nil`)
- ✅ 사용자 식별자(IDFV 등) 미전송

---

## Apple MapKit (길찾기)

### 사용 API

| API | 용도 | 파일 |
|-----|------|------|
| `MKDirections` | 자동차/도보 경로 계산 | `FallbackRouteService.swift` |
| `MKDirections.Request.transportType` | `.automobile` / `.walking` | 동일 |

### 약관

- 상업적 사용 **허용** — Apple이 공식 "라우팅 앱" 카테고리 지원
- 경쟁 서비스 금지 조항: Apple Maps 데이터 추출·재배포 금지 (단순 MKDirections 사용은 무관)
- 응답 데이터 영구 저장 금지 (카카오와 동일)
- **비용**: Apple Developer Program $99/년 외 추가 없음
- **쿼터**: iOS 네이티브는 디바이스당 rate limit만 (정상 사용 시 거의 닿지 않음)

### App Store 출시 추가 요구사항

#### 1. Info.plist 키 추가

```xml
<key>MKDirectionsApplicationSupportedModes</key>
<array>
  <string>MKDirectionsModeCar</string>
  <string>MKDirectionsModePedestrian</string>
</array>
```

#### 2. Routing App Coverage File (GeoJSON)

App Store Connect 업로드 필수. 없으면 심사 통과 불가.

```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "properties": {
        "name": "South Korea",
        "modes": ["MKDirectionsModeCar", "MKDirectionsModePedestrian"]
      },
      "geometry": {
        "type": "MultiPolygon",
        "coordinates": [
          [[[126.117, 37.731], [129.620, 37.731],
            [129.620, 33.190], [126.117, 33.190],
            [126.117, 37.731]]]
        ]
      }
    }
  ]
}
```

> 위는 단순화된 사각형. 실제 제출 시 [Natural Earth KOR 폴리곤](https://www.naturalearthdata.com/)으로 교체 (제주도·울릉도 포함).  
> 좌표 순서: `[경도, 위도]` ← 위경도 반대 순서

### 한국 길찾기 품질 주의

- 한국 도로 데이터 정밀도가 카카오/티맵 대비 낮음
- 신설 도로, 골목, 실시간 교통 반영 부족
- **MVP 출시 후 사용자 피드백에 따라 카카오 모빌리티 제휴 검토** 여지 남겨둠

---

## 카카오 모빌리티 (보류)

| API | 상태 | 이유 |
|-----|------|------|
| 자동차 길찾기 `GET /v1/directions` | **보류** | Apple로 대체. 일 10k 쿼터 + 트래픽 증가 시 제휴 필요 |
| 도보 길찾기 `POST /affiliate/walking/v1/directions` | **사용 불가** | 제휴 계약 필수 (단독 불가, 자동차 유료 묶음) |

트래픽 증가 또는 길찾기 품질 이슈 발생 시 [카카오모빌리티 파트너 신청](https://developers.kakaomobility.com/price/).

---

## 배포 전 체크리스트

### App Store 심사 필수

- [ ] `MKDirectionsApplicationSupportedModes` Info.plist 추가
- [ ] `RoutingAppCoverage.geojson` 작성 (한국 폴리곤)
- [ ] App Store Connect 업로드 (앱 정보 → 라우팅 앱 커버리지)
- [ ] 개인정보처리방침 작성 (앱 내 + App Store Connect URL)
- [ ] App Store Connect Privacy Details 입력 (Precise Location, User Content 등)
- [ ] 앱 내 안전 면책 문구 ("길찾기 정보는 참고용, 도로 표지판 우선 확인")

### CarPlay (선택)

- [ ] Apple CarPlay Navigation Entitlement 신청 (별도 승인, 수주 소요)
- 현재 `NavigationSessionManager` CarPlay 통합 코드 존재

### 한국 법적 고려 (사이드 프로젝트 기준)

| 항목 | 판단 |
|------|------|
| 위치기반서비스 사업자 신고 | 사이드 프로젝트 단계 → 보류. 수익화·대규모 사용자 시 1인 창조기업 + 간이 신고 |
| 개인정보처리방침 | 작성 필요 (위치정보 외부 전송: 카카오 API, Apple 서버 명시) |
| 위치정보 이용약관 | 신고 시 필요. 신고 전엔 개인정보처리방침에 위치정보 조항 포함으로 대체 가능 |

---

## 아키텍처 변경 요약

```
기존: 검색+경로 단일 provider (Kakao | Apple)
변경: 검색 provider + 경로 provider 독립 선택

기본값:
  검색   → 카카오 로컬 API (Kakao)
  경로   → Apple MapKit    (Apple, 기본값)
  경로   → 카카오 모빌리티 (Kakao, 개발자 메뉴에서 선택 가능)
```

**429 처리 방침**

| 서비스 | 한도 초과 시 |
|--------|-------------|
| 카카오 검색 | Apple 폴백 없이 팝업 후 검색 중단 (당일 복구 없음) |
| 카카오 경로 | Apple로 자동 폴백 + 팝업 1회 (1시간 후 자동 복구) |

**코드 작업 범위** → [requirements.md](requirements.md), [plan.md](plan.md) 참고
