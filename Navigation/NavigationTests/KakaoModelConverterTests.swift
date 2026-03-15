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
