import Testing
import CoreLocation
@testable import Navigation

struct KakaoModelConverterTests {

    @Test func placeFromSearchDocument() {
        let doc = KakaoSearchResponse.Document(
            placeName: "강남역",
            addressName: "서울 강남구 역삼동 858",
            roadAddressName: "서울 강남구 강남대로 396",
            phone: "02-1234-5678",
            categoryName: "지하철역",
            categoryGroupName: nil,
            placeUrl: nil,
            distance: nil,
            x: "127.0276",
            y: "37.4979"
        )

        let place = KakaoModelConverter.place(from: doc)

        #expect(place.name == "강남역")
        #expect(place.address == "서울 강남구 강남대로 396")
        #expect(place.phoneNumber == "02-1234-5678")
        #expect(place.category == "지하철역")
        #expect(abs(place.coordinate.latitude - 37.4979) < 0.0001)
        #expect(abs(place.coordinate.longitude - 127.0276) < 0.0001)
    }

    @Test func placeFromSearchDocument_noRoadAddress() {
        let doc = KakaoSearchResponse.Document(
            placeName: "테스트",
            addressName: "서울 강남구 역삼동 858",
            roadAddressName: nil,
            phone: nil,
            categoryName: nil,
            categoryGroupName: nil,
            placeUrl: nil,
            distance: nil,
            x: "127.0",
            y: "37.5"
        )

        let place = KakaoModelConverter.place(from: doc)

        #expect(place.address == "서울 강남구 역삼동 858")
    }

    @Test func routeFromKakaoRoute_extractsPolyline() {
        let kakaoRoute = KakaoRouteResponse.KakaoRoute(
            resultCode: 0,
            resultMsg: "",
            summary: .init(distance: 5000, duration: 600),
            sections: [.init(
                distance: 5000,
                duration: 600,
                roads: [
                    .init(vertexes: [127.0, 37.5, 127.01, 37.51, 127.02, 37.52])
                ],
                guides: [
                    .init(name: "출발", x: 127.0, y: 37.5, distance: 2000, duration: 200, type: 0, guidance: "직진하세요"),
                    .init(name: "도착", x: 127.02, y: 37.52, distance: 3000, duration: 400, type: 100, guidance: "목적지"),
                ]
            )]
        )

        let route = KakaoModelConverter.route(from: kakaoRoute)

        #expect(route.polylineCoordinates.count == 3)
        #expect(route.distance == 5000)
        #expect(route.expectedTravelTime == 600)
        #expect(route.steps.count == 2)
        #expect(route.steps[0].instructions == "직진하세요")
        #expect(route.transportMode == .automobile)
        #expect(route.provider == .kakao)
        // 폴리라인 분할: step별 polyline이 점 1개가 아님
        #expect(route.steps[0].polylineCoordinates.count >= 1)
        #expect(route.steps[0].duration == 200)
    }

    @Test func routeFromKakaoRoute_stepPolylineSplit() {
        // 폴리라인: P0 → P1 → P2 → P3 → P4 (5점)
        // Guide 0: P1 근처 (distance=1000, type=13 우회전)
        // Guide 1: P3 근처 (distance=2000, type=12 좌회전)
        let kakaoRoute = KakaoRouteResponse.KakaoRoute(
            resultCode: 0,
            resultMsg: "",
            summary: .init(distance: 3000, duration: 300),
            sections: [.init(
                distance: 3000,
                duration: 300,
                roads: [
                    .init(vertexes: [127.000, 37.500, 127.001, 37.501, 127.002, 37.502, 127.003, 37.503, 127.004, 37.504])
                ],
                guides: [
                    .init(name: "테헤란로", x: 127.001, y: 37.501, distance: 1000, duration: 100, type: 13, guidance: "우회전"),
                    .init(name: "강남대로", x: 127.003, y: 37.503, distance: 2000, duration: 200, type: 12, guidance: "좌회전"),
                ]
            )]
        )

        let route = KakaoModelConverter.route(from: kakaoRoute)

        // Step 0: P0~P1 구간 (점 1개가 아닌 구간 좌표 배열)
        #expect(route.steps[0].polylineCoordinates.count >= 2)
        #expect(route.steps[0].turnType == .rightTurn)
        #expect(route.steps[0].roadName == "테헤란로")
        #expect(route.steps[0].duration == 100)

        // Step 1: P1~P4 구간 (마지막 step은 폴리라인 끝까지)
        #expect(route.steps[1].polylineCoordinates.count >= 2)
        #expect(route.steps[1].turnType == .leftTurn)
        #expect(route.steps[1].roadName == "강남대로")

        // provider
        #expect(route.provider == .kakao)
    }

    @Test func routeFromKakaoRoute_emptyRoadName() {
        let kakaoRoute = KakaoRouteResponse.KakaoRoute(
            resultCode: 0,
            resultMsg: "",
            summary: .init(distance: 1000, duration: 100),
            sections: [.init(
                distance: 1000,
                duration: 100,
                roads: [.init(vertexes: [127.0, 37.5, 127.01, 37.51])],
                guides: [.init(name: "", x: 127.01, y: 37.51, distance: 1000, duration: 100, type: 11, guidance: "직진")]
            )]
        )

        let route = KakaoModelConverter.route(from: kakaoRoute)

        // 빈 문자열은 nil로 변환
        #expect(route.steps[0].roadName == nil)
    }

    @Test func routeFromKakaoRoute_multipleSections() {
        let kakaoRoute = KakaoRouteResponse.KakaoRoute(
            resultCode: 0,
            resultMsg: "",
            summary: .init(distance: 10000, duration: 1200),
            sections: [
                .init(distance: 5000, duration: 600,
                      roads: [.init(vertexes: [127.0, 37.5, 127.01, 37.51])],
                      guides: [.init(name: "", x: 127.0, y: 37.5, distance: 5000, duration: 600, type: 0, guidance: "직진")]),
                .init(distance: 5000, duration: 600,
                      roads: [.init(vertexes: [127.01, 37.51, 127.02, 37.52])],
                      guides: [.init(name: "", x: 127.02, y: 37.52, distance: 5000, duration: 600, type: 100, guidance: "도착")]),
            ]
        )

        let route = KakaoModelConverter.route(from: kakaoRoute)

        #expect(route.polylineCoordinates.count == 4)
        #expect(route.steps.count == 2)
    }
}
