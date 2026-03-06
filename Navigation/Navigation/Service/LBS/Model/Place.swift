import CoreLocation

struct Place: Sendable {
    let name: String?
    let coordinate: CLLocationCoordinate2D
    let address: String?
    let phoneNumber: String?
    let url: URL?
    let category: String?
    let providerRawData: (any Sendable)?

    init(
        name: String?,
        coordinate: CLLocationCoordinate2D,
        address: String? = nil,
        phoneNumber: String? = nil,
        url: URL? = nil,
        category: String? = nil,
        providerRawData: (any Sendable)? = nil
    ) {
        self.name = name
        self.coordinate = coordinate
        self.address = address
        self.phoneNumber = phoneNumber
        self.url = url
        self.category = category
        self.providerRawData = providerRawData
    }
}
