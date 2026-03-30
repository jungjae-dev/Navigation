import MapKit
import CoreLocation

enum AppleModelConverter {

    // MARK: - Place ↔ MKMapItem

    static func place(from mapItem: MKMapItem) -> Place {
        Place(
            name: mapItem.name,
            coordinate: mapItem.location.coordinate,
            address: mapItem.address?.fullAddress ?? mapItem.address?.shortAddress,
            phoneNumber: mapItem.phoneNumber,
            url: mapItem.url,
            category: mapItem.pointOfInterestCategory?.rawValue,
            providerRawData: mapItem
        )
    }

    static func mapItem(from place: Place) -> MKMapItem {
        if let original = place.providerRawData as? MKMapItem {
            return original
        }
        let item = MKMapItem(
            location: CLLocation(
                latitude: place.coordinate.latitude,
                longitude: place.coordinate.longitude
            ),
            address: nil
        )
        item.name = place.name
        return item
    }

    // MARK: - Route ↔ MKRoute

    static func route(from mkRoute: MKRoute) -> Route {
        let steps = mkRoute.steps.map { routeStep(from: $0) }
        let polyline = mkRoute.polyline.coordinates

        let route = Route(
            id: UUID().uuidString,
            distance: mkRoute.distance,
            expectedTravelTime: mkRoute.expectedTravelTime,
            name: mkRoute.name,
            steps: steps,
            polylineCoordinates: polyline,
            transportMode: mkRoute.transportType == .walking ? .walking : .automobile,
            provider: .apple
        )

        // 변환 결과 로그
        let logger = NavigationLogger.shared
        logger.logRouteConverted(provider: .apple, stepCount: steps.count, polylineCount: polyline.count)
        for (i, step) in steps.enumerated() {
            logger.logRouteStep(index: i, instruction: step.instructions, turnType: step.turnType, roadName: step.roadName, polylineCount: step.polylineCoordinates.count)
        }

        return route
    }

    static func routeStep(from mkStep: MKRoute.Step) -> RouteStep {
        RouteStep(
            instructions: mkStep.instructions,
            distance: mkStep.distance,
            polylineCoordinates: mkStep.polyline.coordinates,
            duration: nil,
            turnType: TurnType.from(appleInstructions: mkStep.instructions),
            roadName: nil
        )
    }

    // MARK: - SearchCompletion ↔ MKLocalSearchCompletion

    static func searchCompletion(from mkCompletion: MKLocalSearchCompletion) -> SearchCompletion {
        SearchCompletion(
            id: "\(mkCompletion.title)_\(mkCompletion.subtitle)",
            title: mkCompletion.title,
            subtitle: mkCompletion.subtitle,
            highlightRanges: nil
        )
    }
}
