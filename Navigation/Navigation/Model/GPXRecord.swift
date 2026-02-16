import SwiftData
import Foundation

@Model
final class GPXRecord {

    var id: UUID
    var fileName: String
    var filePath: String
    var duration: TimeInterval
    var distance: Double
    var pointCount: Int
    var recordedAt: Date
    var fileSize: Int64

    init(
        fileName: String,
        filePath: String,
        duration: TimeInterval,
        distance: Double,
        pointCount: Int,
        fileSize: Int64 = 0
    ) {
        self.id = UUID()
        self.fileName = fileName
        self.filePath = filePath
        self.duration = duration
        self.distance = distance
        self.pointCount = pointCount
        self.recordedAt = Date()
        self.fileSize = fileSize
    }

    /// Full file URL resolved from Documents directory
    var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filePath)
    }
}
