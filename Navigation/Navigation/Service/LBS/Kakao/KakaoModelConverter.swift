import CoreLocation

enum KakaoModelConverter {

    static func place(from doc: KakaoSearchResponse.Document) -> Place {
        let lat = Double(doc.y) ?? 0
        let lng = Double(doc.x) ?? 0
        let placeURL = doc.placeUrl.flatMap { URL(string: $0) }
        return Place(
            name: doc.placeName,
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            address: doc.roadAddressName ?? doc.addressName,
            phoneNumber: doc.phone,
            url: placeURL,
            category: doc.categoryName,
            providerRawData: doc
        )
    }

    static func route(from kakaoRoute: KakaoRouteResponse.KakaoRoute) -> Route {
        let sections = kakaoRoute.sections ?? []

        // 1. 전체 폴리라인 추출 (vertexes: [lng, lat, lng, lat, ...])
        var polyline: [CLLocationCoordinate2D] = []
        for section in sections {
            for road in section.roads {
                let vertexes = road.vertexes
                for i in stride(from: 0, to: vertexes.count - 1, by: 2) {
                    polyline.append(
                        CLLocationCoordinate2D(latitude: vertexes[i + 1], longitude: vertexes[i])
                    )
                }
            }
        }

        // 2. guide 목록 추출
        let allGuides = sections.flatMap { $0.guides }

        // 3. 폴리라인을 guide 좌표 기준으로 분할하여 step별 polyline 생성
        let steps = splitPolylineByGuides(polyline: polyline, guides: allGuides)

        return Route(
            id: UUID().uuidString,
            distance: CLLocationDistance(kakaoRoute.summary?.distance ?? 0),
            expectedTravelTime: TimeInterval(kakaoRoute.summary?.duration ?? 0),
            name: "",
            steps: steps,
            polylineCoordinates: polyline,
            transportMode: .automobile,
            provider: .kakao
        )
    }

    // MARK: - Polyline Split

    /// 전체 폴리라인을 guide 좌표 기준으로 분할하여 RouteStep 배열 생성
    /// 순방향 탐색으로 U턴/겹침 경로도 정확히 처리
    static func splitPolylineByGuides(
        polyline: [CLLocationCoordinate2D],
        guides: [KakaoRouteResponse.Guide]
    ) -> [RouteStep] {
        guard !polyline.isEmpty, !guides.isEmpty else { return [] }

        var steps: [RouteStep] = []
        var searchStartIndex = 0

        for (i, guide) in guides.enumerated() {
            let guideCoord = CLLocationCoordinate2D(latitude: guide.y, longitude: guide.x)

            // guide 좌표에 가장 가까운 폴리라인 점 찾기 (순방향 탐색)
            let nearestIndex = findNearestIndex(
                in: polyline,
                from: searchStartIndex,
                to: guideCoord
            )

            // 이전 searchStartIndex ~ nearestIndex 구간이 이 step의 폴리라인
            let endIndex = min(nearestIndex + 1, polyline.count)
            let stepPolyline = Array(polyline[searchStartIndex..<endIndex])

            let step = RouteStep(
                instructions: guide.guidance,
                distance: CLLocationDistance(guide.distance),
                polylineCoordinates: stepPolyline.isEmpty ? [guideCoord] : stepPolyline,
                duration: TimeInterval(guide.duration),
                turnType: TurnType.from(kakaoType: guide.type),
                roadName: guide.name.isEmpty ? nil : guide.name
            )
            steps.append(step)

            // 다음 guide는 여기서부터 탐색
            searchStartIndex = nearestIndex

            // 마지막 guide이고 폴리라인 끝까지 남아있으면 마지막 step에 포함
            if i == guides.count - 1, nearestIndex < polyline.count - 1 {
                // 마지막 step의 polyline을 폴리라인 끝까지 확장
                let lastStepPolyline = Array(polyline[searchStartIndex...])
                if !lastStepPolyline.isEmpty {
                    steps[steps.count - 1] = RouteStep(
                        instructions: guide.guidance,
                        distance: CLLocationDistance(guide.distance),
                        polylineCoordinates: lastStepPolyline,
                        duration: TimeInterval(guide.duration),
                        turnType: TurnType.from(kakaoType: guide.type),
                        roadName: guide.name.isEmpty ? nil : guide.name
                    )
                }
            }
        }

        return steps
    }

    /// 순방향 탐색: fromIndex 이후에서 target에 가장 가까운 폴리라인 점의 인덱스
    private static func findNearestIndex(
        in polyline: [CLLocationCoordinate2D],
        from fromIndex: Int,
        to target: CLLocationCoordinate2D
    ) -> Int {
        guard fromIndex < polyline.count else { return max(0, polyline.count - 1) }

        var bestIndex = fromIndex
        var bestDistance = CLLocationCoordinate2D.distance(from: polyline[fromIndex], to: target)

        for i in (fromIndex + 1)..<polyline.count {
            let dist = CLLocationCoordinate2D.distance(from: polyline[i], to: target)
            if dist < bestDistance {
                bestDistance = dist
                bestIndex = i
            }
            // 거리가 다시 멀어지기 시작하면 탐색 중단 (최적화)
            // 단, 최소 10개는 더 탐색 (비직선 경로 대응)
            if dist > bestDistance * 2 && i > bestIndex + 10 {
                break
            }
        }

        return bestIndex
    }
}

// MARK: - Coordinate Distance Helper

private extension CLLocationCoordinate2D {
    /// 두 좌표 간 거리 (미터, 간이 계산)
    static func distance(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> CLLocationDistance {
        let loc1 = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let loc2 = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return loc1.distance(from: loc2)
    }
}
