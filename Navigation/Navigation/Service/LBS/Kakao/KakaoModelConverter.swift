import CoreLocation

enum KakaoModelConverter {

    static func place(from doc: KakaoSearchResponse.Document) -> Place {
        let lat = Double(doc.y) ?? 0
        let lng = Double(doc.x) ?? 0
        return Place(
            name: doc.placeName,
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            address: doc.roadAddressName ?? doc.addressName,
            phoneNumber: doc.phone,
            category: doc.categoryName,
            providerRawData: doc
        )
    }

    static func route(from kakaoRoute: KakaoRouteResponse.KakaoRoute) -> Route {
        let sections = kakaoRoute.sections ?? []

        // Extract polyline coordinates (vertexes: [lng, lat, lng, lat, ...])
        var coordinates: [CLLocationCoordinate2D] = []
        for section in sections {
            for road in section.roads {
                let vertexes = road.vertexes
                for i in stride(from: 0, to: vertexes.count - 1, by: 2) {
                    coordinates.append(
                        CLLocationCoordinate2D(latitude: vertexes[i + 1], longitude: vertexes[i])
                    )
                }
            }
        }

        // Extract steps from guides
        let steps = sections.flatMap { section in
            section.guides.map { guide in
                RouteStep(
                    instructions: guide.guidance,
                    distance: CLLocationDistance(guide.distance),
                    polylineCoordinates: [
                        CLLocationCoordinate2D(latitude: guide.y, longitude: guide.x)
                    ]
                )
            }
        }

        return Route(
            id: UUID().uuidString,
            distance: CLLocationDistance(kakaoRoute.summary?.distance ?? 0),
            expectedTravelTime: TimeInterval(kakaoRoute.summary?.duration ?? 0),
            name: "",
            steps: steps,
            polylineCoordinates: coordinates,
            transportMode: .automobile
        )
    }
}
