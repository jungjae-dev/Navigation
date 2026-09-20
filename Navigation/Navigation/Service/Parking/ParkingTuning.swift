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

    // MARK: - 260911 현장 로그 반영 (동일 코드 다중 표지판 → 30.3m 오차)

    /// 같은 코드의 재관측 위치가 이 거리 이상 점프하면 다중 표지판(주차면 번호 반복 표기)으로 판단 —
    /// 해당 코드는 격자 피팅에서 제외(층·도착 확인엔 유지). 드리프트 재앵커(1~3m)와 구분되는 값.
    /// 260911: J23·J24·G25가 8~10.7m 떨어진 복수 표지판에서 관측되어 축 벡터 왜곡.
    /// 주의(설계 개정 v2): 실측 점프 공백은 [0.8, 4.87) — 4.0은 그 안의 경험적 상수이며
    /// "데이터가 지목한 값"은 아님. raycast 바닥 오탐(4.87m, 1초 간격)도 함께 걸러진다.
    static let sameCodeJumpThreshold: Float = 4.0

    // MARK: - 3중 가드 (설계 개정 v2, 260911 교차 검증 — 잔차 강등의 구조적 사망 대체)

    /// G1 외삽 레버 상한 — √(aᵀM⁻¹a). 관측 배치 대비 목표 외삽 정도.
    /// 실측: 성공 세션 1.50 vs 실패 세션 3.61(J22)·6.98(J21) — 이 한 가드가 두 실패를 차단
    static let extrapolationLeverLimit = 2.5

    /// G2 축 간격 사전확률 — 인덱스 1스텝당 물리적 타당 범위(m).
    /// 실측 정상 피치 1.5~16.7m, 실패 세션의 오염 축 21.5m/스텝 차단.
    /// 하한 1.0은 H22 실측 최소 피치 1.5m를 통과시키기 위해 설계 문서(2m)보다 완화
    static let axisStepMinMeters = 1.0
    static let axisStepMaxMeters = 15.0

    /// G3 표시 거리 상한(m) — 주차장 물리 규모 초과 목표는 표시하지 않음 (J21의 102m 표시 차단)
    static let maxGuidanceDisplayDistance = 60.0

    /// 잔차가 품질 신호로 유효한 최소 관측 수 — 아핀은 3점 정확결정계(잔차 항등 0)라 4점부터,
    /// 1D 직선은 2점 정확결정계라 3점부터 의미를 가짐
    static let residualInformativeMinCountAffine = 4
    static let residualInformativeMinCount1D = 3

    // MARK: - v3 점진 정확도 (spec 006 — 260919 로그·PR#58 교차 리뷰)

    /// FR-101 측방 각도 보장 임계(rad). asin(U/d⁻) ≤ 이 값일 때만 화살표.
    /// 초기값 30°, 도착 성공 세션 참값으로 캘리브레이션 (SC-102: 캘리브레이션·검증 세션 분리)
    static let guaranteeMaxAngle: Double = 30.0 * .pi / 180.0

    /// 미지 축 피치의 보수적 사전값(m/스텝) — 등방성 가정 금지(FR-101).
    /// 축 역할별로 다르다: 구역축은 통로 폭 규모(실측 11.5~16.9), 번호축은 주차면 규모(실측 4.6~10.5).
    /// 하나의 전역 상한(17m)을 쓰면 번호축이 미지일 때 보장이 35m 밖에서 끊겨 화살표가 과도하게 사라진다 —
    /// 등방성을 깬 바로 그 실측(구역 16.4 vs 번호 4.8)이 축별 사전값을 쓰라는 근거다.
    static let unknownZoneAxisPitchPrior = 17.0
    static let unknownNumberAxisPitchPrior = 12.0

    /// 외삽 1스텝당 누적되는 격자 불규칙성 비율 — 잔차가 못 보는 계통 오차.
    /// 잔차×레버만 쓰면 J21(잔차 0.10m·6스텝 외삽)의 위험이 0.5m로 과소평가된다
    static let modelErrorPerStepRatio = 0.15

    /// FR-105 위생 검사 — 명백한 부조리만 차단(안전망 아님, 차단 책임은 FR-101)
    static let axisStepAbsurdMin = 0.5
    static let axisStepAbsurdMax = 25.0
    /// 정상 범위(실측) — 벗어나면 차단이 아니라 백분율 감점
    static let axisStepNormalMin = 1.5
    static let axisStepNormalMax = 17.0

    /// FR-106 표시 거리 상대 기준 — 랜드마크 간 최대 이격(관측 스팬)의 배수.
    /// 기기 이동 경로는 분모에 넣지 않는다(걸을수록 관용이 커지는 역스케일링 방지)
    static let displayDistanceSpanFactor = 1.2

    /// FR-108 불확실성 팽창 — 관측 노화 m/s와 상한. 제외 대신 팽창(점추정은 오염하지 않음)
    static let expansionMetersPerSecond = 0.05
    static let expansionMaxMeters = 12.0

    /// FR-103 백분율 — 상한 95(100 미표시), 실선·거리 표시 전환점, 경계 깜빡임 억제 이력
    static let confidencePercentCap = 95
    static let confidencePercentFloor = 5
    static let confidencePercentSolidThreshold = 45
    static let confidencePercentHysteresis = 5

    /// FR-104 관측 수 게이트 — 상위 구간 진입 최소 채택 관측 수
    static let observationsForSolid = 3
}
