import CoreLocation
import Foundation

/// NDJSON 파일을 읽어 CLLocation 배열로 반환.
/// 한 줄씩 파싱하므로 파일이 크래시로 중간에 잘려도 유효한 줄까지 복원.
enum LocationFileReader {

    static func read(fileURL: URL) throws -> [CLLocation] {
        let data = try Data(contentsOf: fileURL)
        guard let content = String(data: data, encoding: .utf8) else {
            throw LocationFileError.invalidEncoding
        }

        let decoder = JSONDecoder()
        var locations: [CLLocation] = []

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8) else { continue }
            do {
                let record = try decoder.decode(LocationRecord.self, from: lineData)
                locations.append(record.toCLLocation())
            } catch {
                // 잘린 줄(파일 끝) 또는 손상된 줄 — 조용히 스킵
                continue
            }
        }

        return locations
    }
}

enum LocationFileError: Error {
    case invalidEncoding
}
