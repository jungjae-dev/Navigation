import Testing
import CoreLocation
@testable import Navigation

struct RouteModelTests {

    @Test func formattedDistance_meters() {
        let route = Route(
            id: "1", distance: 800, expectedTravelTime: 60, name: "",
            steps: [], polylineCoordinates: [], transportMode: .automobile
        )
        #expect(route.formattedDistance == "800m")
    }

    @Test func formattedDistance_kilometers() {
        let route = Route(
            id: "1", distance: 1500, expectedTravelTime: 60, name: "",
            steps: [], polylineCoordinates: [], transportMode: .automobile
        )
        #expect(route.formattedDistance == "1.5km")
    }

    @Test func formattedTravelTime_minutesOnly() {
        let route = Route(
            id: "1", distance: 1000, expectedTravelTime: 45 * 60, name: "",
            steps: [], polylineCoordinates: [], transportMode: .automobile
        )
        #expect(route.formattedTravelTime == "45분")
    }

    @Test func formattedTravelTime_hoursAndMinutes() {
        let route = Route(
            id: "1", distance: 1000, expectedTravelTime: 65 * 60, name: "",
            steps: [], polylineCoordinates: [], transportMode: .automobile
        )
        #expect(route.formattedTravelTime == "1시간 5분")
    }

    @Test func formattedTravelTime_exactHours() {
        let route = Route(
            id: "1", distance: 1000, expectedTravelTime: 120 * 60, name: "",
            steps: [], polylineCoordinates: [], transportMode: .automobile
        )
        #expect(route.formattedTravelTime == "2시간")
    }
}
