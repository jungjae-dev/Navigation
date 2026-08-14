import Foundation

/// 현장 튜닝 대상 임계값 (research "현장 튜닝 항목" 표).
/// 초기값은 설계 추정치 — 실주차장 DR-003 로그 기반으로 조정한다(T045).
enum ParkingTuning {

    /// Vision 인식 신뢰도 하한 — 미만은 후보에서 기각
    static let ocrMinConfidence: Float = 0.6

    /// 동일 코드 반복 관측 확정 횟수 (오인식 완화, R4)
    static let confirmHits = 2

    /// 스캔 등록: 첫 확정 코드 이후 자동 저장까지 안정화 유예 (FR-002 — 인접 대기 아님)
    static let saveStabilization: TimeInterval = 3.0

    /// 스캔 등록: 코드 무확보 시 수동 입력 전환 안내까지 (FR-004)
    static let scanTimeout: TimeInterval = 15.0

    /// 자동 저장 사진 최대 장수 (코드 확정 시점 프레임)
    static let maxAutoPhotos = 2

    /// 격자 모순 감지 잔차 임계 (m) — max(고정값, 추정 기둥 간격 × 계수) (FR-012)
    static let residualLimitFloor: Double = 3.0
    static let residualSpacingFactor: Double = 0.7

    /// 강등 후 안내 복귀에 필요한 연속 정합 관측 수
    static let recoveryConsistentCount = 2

    /// 도착 확정: 목표 코드 연속 인식 횟수·최소 간격 (FR-013)
    static let arrivalConsecutive = 2
    static let arrivalMinInterval: TimeInterval = 1.0

    /// raycast 연속 실패 → 근접/손전등 안내 배너 (FR-015)
    static let raycastFailBannerAfter = 3

    // MARK: - 260801 현장 로그 반영 (목표 추정 10.2m 오차 대응)

    /// 이 시간 이상 재관측되지 않은 관측은 격자 피팅에서 제외 —
    /// 걷는 동안 누적된 VIO 드리프트로 낡은 좌표가 격자를 오염 (260801: 초반 F3/F4가 47초 뒤 피팅에 잔류)
    static let observationStaleAfter: TimeInterval = 30.0

    /// high 신뢰도 표시에 필요한 최소 위치 관측 수 —
    /// 점 4개/미지수 6개는 과결정 2뿐이라 잔차가 낮아도 정확 보장 없음 (260801: 잔차 0.22m인데 오차 10.2m)
    static let minObservationsForHighConfidence = 5

    /// sceneDepth 폴백 유효 깊이 상한(m) — 원거리 depth는 신뢰 불가
    static let depthFallbackMaxDistance: Float = 15.0
}
