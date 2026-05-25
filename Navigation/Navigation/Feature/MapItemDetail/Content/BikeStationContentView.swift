import UIKit
import CoreLocation

/// 따릉이 정류소 상세 컨텐츠 — 대여 가능 자전거 + 거리·갱신 정보
final class BikeStationContentView: UIView {

    // MARK: - UI

    private let availableLabel = UILabel()
    private let availableCountLabel = UILabel()
    private let totalRacksLabel = UILabel()
    private let infoLabel = UILabel()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        availableLabel.text = "대여 가능"
        availableLabel.font = Theme.Fonts.caption
        availableLabel.textColor = Theme.Colors.secondaryLabel

        availableCountLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .bold)
        availableCountLabel.textColor = Theme.Colors.bikeBrand

        totalRacksLabel.font = Theme.Fonts.caption
        totalRacksLabel.textColor = Theme.Colors.secondaryLabel

        let countRow = UIStackView(arrangedSubviews: [availableCountLabel, totalRacksLabel])
        countRow.axis = .horizontal
        countRow.alignment = .lastBaseline
        countRow.spacing = 2

        let statColumn = UIStackView(arrangedSubviews: [availableLabel, countRow])
        statColumn.axis = .vertical
        statColumn.spacing = 2
        statColumn.alignment = .leading

        infoLabel.font = Theme.Fonts.caption
        infoLabel.textColor = Theme.Colors.secondaryLabel

        let contentStack = UIStackView(arrangedSubviews: [statColumn, infoLabel])
        contentStack.axis = .vertical
        contentStack.spacing = Theme.Spacing.lg
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    // MARK: - Public

    func configure(station: BikeStation) {
        availableCountLabel.text = "\(station.availableBikes)"
        availableCountLabel.textColor = station.availableBikes == 0 ? Theme.Colors.secondaryLabel : Theme.Colors.bikeBrand
        totalRacksLabel.text = "/ \(station.totalRacks)"
    }

    func setInfoText(_ text: String) {
        infoLabel.text = text
    }
}
