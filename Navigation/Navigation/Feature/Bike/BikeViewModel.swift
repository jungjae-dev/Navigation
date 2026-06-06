import Foundation
import Combine
import OSLog

private let bikeLogger = Logger(subsystem: "nav.bike", category: "ViewModel")

/// 따릉이 레이어 ViewModel
/// - 레이어 ON/OFF 상태 관리
/// - API 호출 + 캐시 갱신 트리거
/// - 로딩/에러 상태를 UI에 전달
@MainActor
final class BikeViewModel: ObservableObject {

    enum State: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    // MARK: - Published

    @Published private(set) var state: State = .idle
    @Published private(set) var isLayerOn: Bool = false
    private var isFetching: Bool = false

    private static let layerDefaultsKey = "layer.bike.enabled"

    // MARK: - Dependencies

    private let api: BikeStationAPI
    private let cache: BikeStationCache

    init(api: BikeStationAPI = BikeStationAPI(), cache: BikeStationCache = .shared) {
        self.api = api
        self.cache = cache
        self.isLayerOn = UserDefaults.standard.bool(forKey: Self.layerDefaultsKey)
    }

    // MARK: - Actions

    /// 레이어 ON/OFF 토글
    /// - ON 전환 시 캐시가 비어있으면 fetchAll
    /// - OFF 전환 시 단순히 표시만 끔 (캐시는 유지)
    func toggleLayer() async {
        // fetch 진행 중엔 재진입 방지 — 빠른 연타로 상태가 꼬이는 문제 차단
        guard !isFetching else { return }
        isLayerOn.toggle()
        UserDefaults.standard.set(isLayerOn, forKey: Self.layerDefaultsKey)
        guard isLayerOn else { return }

        // 이미 캐시가 있으면 재호출 안 함 (수동 갱신 정책)
        guard cache.allStations.isEmpty else {
            state = .loaded
            return
        }

        await fetchAll()
    }

    /// 앱 시작 시 저장된 레이어 상태 복원 — ON 으로 저장돼 있으면 데이터 확보
    func restoreLayerIfNeeded() async {
        guard isLayerOn else { return }
        if cache.allStations.isEmpty {
            await fetchAll()
        } else {
            state = .loaded
        }
    }

    /// 전체 정류소 fetch + 캐시 업데이트
    func fetchAll() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }
        state = .loading
        do {
            let stations = try await api.fetchAll()
            cache.update(stations)
            state = .loaded
            bikeLogger.info("✅ fetchAll \(stations.count, privacy: .public)개 정류소")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state = .error(message)
            bikeLogger.error("❌ fetchAll \(message, privacy: .public)")
        }
    }

    /// 단일 정류소 새로고침 — 상세 시트에서 사용
    /// - 결과를 캐시에 반영하고 호출자에게도 반환
    @discardableResult
    func refreshSingle(stationId: String) async -> BikeStation? {
        do {
            guard let station = try await api.fetchOne(stationId: stationId) else {
                bikeLogger.warning("refreshSingle \(stationId, privacy: .public): nil")
                return nil
            }
            cache.update(single: station)
            bikeLogger.debug("refreshed \(stationId, privacy: .public)")
            return station
        } catch {
            bikeLogger.error("❌ refreshSingle \(stationId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
