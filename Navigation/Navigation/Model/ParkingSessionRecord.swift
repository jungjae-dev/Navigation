import SwiftData
import Foundation

/// 한 번의 주차 기록. 활성(active) 레코드는 항상 1개 이하.
/// AR 세션 좌표계는 세션마다 새로 생성되므로 좌표·벡터는 저장하지 않는다 —
/// 세션을 넘어 유효한 것은 코드 문자열·토큰·스칼라 거리뿐.
@Model
final class ParkingSessionRecord {

    enum Status: String {
        case active
        case completed
    }

    enum FloorSource: String {
        case code    // 코드 문자열에 층 토큰 포함 (B2-A-3)
        case manual  // 코드에 층이 없어 사용자가 별도 입력 (A-3 + "B2")
    }

    var id: UUID
    var targetCodeRaw: String
    var floorToken: String?
    var floorSourceRaw: String
    var zoneToken: String?
    var numberValue: Int?
    var templateSkeleton: String
    var photoPaths: [String]
    var createdAt: Date
    var statusRaw: String
    var completedAt: Date?
    var neighborsData: Data

    init(
        targetCodeRaw: String,
        floorToken: String?,
        floorSource: FloorSource,
        zoneToken: String?,
        numberValue: Int?,
        templateSkeleton: String,
        photoPaths: [String] = [],
        neighbors: [NeighborCode] = []
    ) {
        self.id = UUID()
        self.targetCodeRaw = targetCodeRaw
        self.floorToken = floorToken
        self.floorSourceRaw = floorSource.rawValue
        self.zoneToken = zoneToken
        self.numberValue = numberValue
        self.templateSkeleton = templateSkeleton
        self.photoPaths = photoPaths
        self.createdAt = Date()
        self.statusRaw = Status.active.rawValue
        self.completedAt = nil
        self.neighborsData = (try? JSONEncoder().encode(neighbors)) ?? Data()
    }

    var status: Status {
        get { Status(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var floorSource: FloorSource {
        FloorSource(rawValue: floorSourceRaw) ?? .code
    }

    var neighbors: [NeighborCode] {
        get { (try? JSONDecoder().decode([NeighborCode].self, from: neighborsData)) ?? [] }
        set { neighborsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var photoURLs: [URL] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return photoPaths.map { docs.appendingPathComponent($0) }
    }
}

/// 등록 스캔 중 함께 인식된 인접 기둥 코드 (스캔 부산물, FR-002b).
/// distanceToTarget: 목표 앵커까지 스칼라 거리(m) — 회전 불변이라 세션을 넘어 유효.
/// 어느 한쪽의 공간 위치 파악에 실패한 쌍은 nil.
struct NeighborCode: Codable, Equatable {
    let codeRaw: String
    let zoneToken: String?
    let numberValue: Int?
    let distanceToTarget: Double?
}
