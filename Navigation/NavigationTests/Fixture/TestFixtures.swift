import CoreLocation
@testable import Navigation

enum TestFixtures {

    static let gangnam = CLLocationCoordinate2D(latitude: 37.4979, longitude: 127.0276)
    static let seolleung = CLLocationCoordinate2D(latitude: 37.5045, longitude: 127.0490)

    static let samplePlace = Place(
        name: "강남역",
        coordinate: gangnam,
        address: "서울 강남구 강남대로 396",
        phoneNumber: "02-1234-5678",
        category: "지하철역"
    )

    static let sampleRoute = Route(
        id: "test-1",
        distance: 5000,
        expectedTravelTime: 600,
        name: "테스트 경로",
        steps: [
            RouteStep(
                instructions: "직진",
                distance: 3000,
                polylineCoordinates: [gangnam, CLLocationCoordinate2D(latitude: 37.500, longitude: 127.030)],
                duration: 180,
                turnType: .straight,
                roadName: "테헤란로"
            ),
            RouteStep(
                instructions: "우회전하세요",
                distance: 1500,
                polylineCoordinates: [CLLocationCoordinate2D(latitude: 37.500, longitude: 127.030), CLLocationCoordinate2D(latitude: 37.503, longitude: 127.045)],
                duration: 120,
                turnType: .rightTurn,
                roadName: "강남대로"
            ),
            RouteStep(
                instructions: "목적지",
                distance: 500,
                polylineCoordinates: [CLLocationCoordinate2D(latitude: 37.503, longitude: 127.045), seolleung],
                duration: 60,
                turnType: .destination,
                roadName: nil
            ),
        ],
        polylineCoordinates: [
            gangnam,
            CLLocationCoordinate2D(latitude: 37.500, longitude: 127.030),
            CLLocationCoordinate2D(latitude: 37.503, longitude: 127.045),
            seolleung,
        ],
        transportMode: .automobile,
        provider: .kakao
    )

    static let walkingRoute = Route(
        id: "test-walk",
        distance: 1200,
        expectedTravelTime: 900,
        name: "도보 경로",
        steps: [
            RouteStep(
                instructions: "직진",
                distance: 1200,
                polylineCoordinates: [gangnam, seolleung],
                duration: nil,
                turnType: .straight,
                roadName: nil
            ),
        ],
        polylineCoordinates: [gangnam, seolleung],
        transportMode: .walking,
        provider: .apple
    )
}
