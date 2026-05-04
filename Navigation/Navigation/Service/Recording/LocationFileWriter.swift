import CoreLocation
import Foundation

/// NDJSON 스트리밍 기록기. 위치 하나당 JSON 한 줄씩 즉시 파일에 append.
/// 모든 좌표를 메모리에 쌓지 않으므로 장시간(수 시간) 녹화에 적합.
/// 크래시·강제 종료 시에도 이미 append 된 데이터는 보존됨.
final class LocationFileWriter {

    private let fileHandle: FileHandle
    private let encoder = JSONEncoder()

    var fileURL: URL

    init(fileURL: URL) throws {
        self.fileURL = fileURL

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        do {
            fileHandle = try FileHandle(forWritingTo: fileURL)
            fileHandle.seekToEndOfFile()
        } catch {
            // FileHandle 생성 실패 시 빈 파일 정리
            try? FileManager.default.removeItem(at: fileURL)
            throw error
        }
    }

    func write(_ location: CLLocation) throws {
        let record = LocationRecord(from: location)
        var data = try encoder.encode(record)
        data.append(0x0A) // newline
        try fileHandle.write(contentsOf: data)
    }

    func close() {
        try? fileHandle.close()
    }
}
