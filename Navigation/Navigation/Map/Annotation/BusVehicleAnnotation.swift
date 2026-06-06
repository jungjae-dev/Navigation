import MapKit

/// 실시간 운행 버스 위치 마커 (노선 보기 중 표시)
final class BusVehicleAnnotation: NSObject, MKAnnotation {
    let vehicle: BusVehicle

    var coordinate: CLLocationCoordinate2D { vehicle.coordinate }
    var title: String? { vehicle.plateNo.isEmpty ? "운행 중" : vehicle.plateNo }

    init(vehicle: BusVehicle) {
        self.vehicle = vehicle
        super.init()
    }
}
