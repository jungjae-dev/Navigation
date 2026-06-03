# Research: 버스/지하철 대중교통 기능

**Date**: 2026-06-03

## 정적 데이터 배포

- **Decision**: GitHub Gist (public) — 4개 JSON 파일
- **Rationale**: Firebase Storage는 Spark 플랜에서 미지원. Gist는 무료이며 Raw URL로 직접 접근 가능.
- **Gist**: https://gist.github.com/jungjae-dev/2d049aa1765d273905fa1a440e2b4bc6
- **버전 관리**: version.json으로 파일별 버전 체크, 변경된 파일만 다운로드

## API 구성

| 데이터 | API | 키 |
|--------|-----|-----|
| 버스 실시간 도착 | ws.bus.go.kr/api/rest/arrive | BUS_API_KEY |
| 버스 노선 정류소 | ws.bus.go.kr/api/rest/busRouteInfo | BUS_API_KEY |
| 지하철 실시간 도착 | swopenAPI.seoul.go.kr/api/subway | SEOUL_OPEN_API_KEY |
| 지하철 시간표 | openapi.seoul.go.kr:8088 (OA-101) | SEOUL_OPEN_API_KEY |

## 기존 패턴 재사용

- **BusAPIClient**: `SeoulAPIClient` 패턴 재사용 (기존 Bike API와 동일 구조)
- **Annotation**: BikeAnnotation/BikeAnnotationView 패턴 재사용
- **ViewModel**: BikeViewModel 패턴 재사용 (CurrentValueSubject)

## 줌 임계값

- 버스 마커: `latitudinialMeters` 기준 latΔ ≤ 0.03 (약 3km)
- 지하철 마커: latΔ ≤ 0.15 (약 15km) — 역 수가 적어 더 넓은 범위 허용

## 드로어 스택 제한

- 정류소/역 상세: 스택에 1개만 유지
- 노선 드로어: 스택에 1개만 유지
- 지도 마커 탭 시 노선 드로어 열려있으면 먼저 팝 후 정류소 상세 push

## 캐시 전략

| 데이터 | 전략 | 초기화 |
|--------|------|--------|
| 정류장/역 위치 | Gist 버전 기반 갱신 | 설정 수동 갱신 |
| 버스 시간표 | 디스크 영구 | 설정 수동 갱신 |
| 지하철 시간표 | 디스크 영구 | 설정 수동 갱신 |
| 실시간 도착 | 캐시 없음 (온디맨드) | - |
