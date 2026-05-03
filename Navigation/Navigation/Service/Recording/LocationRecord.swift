import CoreLocation

/// NDJSON 한 줄 단위로 저장/읽기 되는 위치 데이터.
/// CLLocation 의 모든 필드를 보존하여 재생 시 원본과 동일한 course/speed/accuracy 제공.
struct LocationRecord: Codable {
    let lat: Double
    let lon: Double
    let alt: Double
    let hAcc: Double
    let vAcc: Double
    let crs: Double        // course (GPS 진행방향, 0~360. -1 이면 미확보)
    let crsAcc: Double
    let spd: Double
    let spdAcc: Double
    let ts: Double         // epoch seconds (timeIntervalSince1970)

    init(from location: CLLocation) {
        lat    = location.coordinate.latitude
        lon    = location.coordinate.longitude
        alt    = location.altitude
        hAcc   = location.horizontalAccuracy
        vAcc   = location.verticalAccuracy
        crs    = location.course
        crsAcc = location.courseAccuracy
        spd    = location.speed
        spdAcc = location.speedAccuracy
        ts     = location.timestamp.timeIntervalSince1970
    }

    func toCLLocation() -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: alt,
            horizontalAccuracy: hAcc,
            verticalAccuracy: vAcc,
            course: crs,
            courseAccuracy: crsAcc,
            speed: spd,
            speedAccuracy: spdAcc,
            timestamp: Date(timeIntervalSince1970: ts)
        )
    }
}
