import SwiftData
import Foundation

@Model
final class Recording {

    var id: UUID
    var fileName: String
    var filePath: String
    var duration: TimeInterval
    var distance: Double
    var pointCount: Int
    var recordedAt: Date
    var fileSize: Int64
    var recordingMode: String
    var originName: String?
    var destinationName: String?

    init(
        fileName: String,
        filePath: String,
        duration: TimeInterval,
        distance: Double,
        pointCount: Int,
        fileSize: Int64 = 0,
        recordingMode: String = "real",
        originName: String? = nil,
        destinationName: String? = nil
    ) {
        self.id = UUID()
        self.fileName = fileName
        self.filePath = filePath
        self.duration = duration
        self.distance = distance
        self.pointCount = pointCount
        self.recordedAt = Date()
        self.fileSize = fileSize
        self.recordingMode = recordingMode
        self.originName = originName
        self.destinationName = destinationName
    }

    var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filePath)
    }
}
