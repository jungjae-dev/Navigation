# Data Model: 버스/지하철 대중교통 기능

## 정적 데이터 모델 (Gist JSON)

### TransitDataVersion
```
busStops: String          // "20260506"
subwayStations: String    // "20250814"
subwayLines: String       // "20260603"
```

### BusStop
```
stId: String              // 정류소 고유 ID (예: "100000001")
arsId: String             // 5자리 정류소 번호 (예: "01001")
name: String              // 정류소명
lat: Double
lng: Double
```

### SubwayStation
```
stationCode: String       // 4자리 역 코드 (예: "0222")
name: String              // 역명 (예: "강남")
lat: Double
lng: Double
lines: [String]           // ["2호선", "신분당선"] (환승역 포함)
```

### SubwayLines (호선별)
```
color: String             // HEX 색상 (예: "#00A84D")
circular: Bool?           // 2호선만 true
stationCodes: [String]    // 역 순서대로
```

---

## 실시간 API 모델

### BusArrival
```
routeId: String
routeName: String         // 노선 번호 (예: "140")
direction: String         // 방향 (예: "방화역")
firstArrivalSeconds: Int?
secondArrivalSeconds: Int?
firstArrivalMessage: String   // "3분 후", "곧 도착", "운행 종료"
secondArrivalMessage: String
routeType: BusRouteType   // .trunk, .branch, .circular, .express ...
isLastBus: Bool
```

### SubwayArrival
```
lineName: String          // "2호선"
direction: String         // "상행" / "하행" / "외선" / "내선"
destination: String       // "성수행"
arrivalSeconds: Int       // recptnDt 보정 적용
arrivalMessage: String    // "2분 후", "곧 도착", "진입"
arrivalCode: ArrivalCode
isExpress: Bool
```

---

## 서비스 상태 모델

### TransitDataState
```
loading
loaded(busStops: [BusStop], subwayStations: [SubwayStation], lines: SubwayLines)
failed(Error)
```

### POILayerState
```
bikeEnabled: Bool
busEnabled: Bool
subwayEnabled: Bool
```
