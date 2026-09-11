# Quickstart: 핀 기반 동네 인사이트

## 빌드 & 실행
- Xcode 26, 시뮬레이터 **iPhone 17 Pro** (iOS 26)
- 인증키: `Secrets.xcconfig`에 Kakao REST 키 + 서울 열린데이터광장 키 설정(커밋 금지)

## 수동 검증 시나리오
1. 앱 실행 → 지도가 서울 표시
2. 임의 지점 **롱프레스** → 핀이 찍히고 동네 인사이트 팝업이 올라옴(POI 팝업과 동일 모습)
3. 헤더에 "OO구 OO동" + 한 줄 요약 표시
4. 카드 스크롤 → 활기·대기질·교통·편의·녹지·안전·지금 행사
5. 실시간 카드(따릉이·대기질)에 "○분 전" 표시 확인
6. 한 API를 의도적으로 실패시켜도(네트워크 차단) 나머지 카드 정상, 해당 카드만 "정보 없음"
7. 푸터 **경로** → 해당 지점 경로 미리보기
8. **저장** 후 관심 목록에서 다시 열기 → 최신 데이터로 재조회 확인
9. 서울 밖 지점 롱프레스 → "서울만 지원" 안내

## 로그 검증 포인트 (헌법 IV)
- `[Insight] longPress dropped at (lat,lng)`
- `[Insight] region resolved: {gu} {dong}`
- `[Insight] card {kind} → loaded/failed (asOf=...)`
- `[Insight] aggregate done in {ms}ms (loaded n/7)`

## 성능 기준 (Success Criteria)
- 첫 카드 <1.5s, 전체 <3s (로그의 aggregate 시간으로 확인)
- 부분 실패 시 전체 팝업 정상(SC-003)

## 테스트 (Swift Testing)
- `CoordinateTransform`: TM/GRS80→WGS84 변환 정확도
- `NeighborhoodInsightService`: 카드별 병렬 집계 + 부분 실패 격리(stub 주입)
- 반경 필터: 카드별 반경 경계값
- `SavedNeighborhoodStore`: 저장/재조회(최신 갱신)
</content>
