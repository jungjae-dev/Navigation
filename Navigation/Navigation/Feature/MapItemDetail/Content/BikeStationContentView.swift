import UIKit
import CoreLocation

/// 따릉이 정류소 상세 컨텐츠 — 대여/반납 통계 + 거리·갱신 정보
final class BikeStationContentView: UIView {

    private static let brandGreen = UIColor(red: 0.18, green: 0.72, blue: 0.42, alpha: 1)

    // MARK: - UI

    private let availableLabel = UILabel()
    private let availableCountLabel = UILabel()
    private let totalRacksLabel1 = UILabel()
    private let returnLabel = UILabel()
    private let returnCountLabel = UILabel()
    private let totalRacksLabel2 = UILabel()
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
        availableCountLabel.textColor = Self.brandGreen

        totalRacksLabel1.font = Theme.Fonts.caption
        totalRacksLabel1.textColor = Theme.Colors.secondaryLabel

        returnLabel.text = "반납 가능"
        returnLabel.font = Theme.Fonts.caption
        returnLabel.textColor = Theme.Colors.secondaryLabel

        returnCountLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .bold)
        returnCountLabel.textColor = Theme.Colors.label

        totalRacksLabel2.font = Theme.Fonts.caption
        totalRacksLabel2.textColor = Theme.Colors.secondaryLabel

        let availStack = makeStatColumn(label: availableLabel, count: availableCountLabel, total: totalRacksLabel1)
        let returnStack = makeStatColumn(label: returnLabel, count: returnCountLabel, total: totalRacksLabel2)

        let divider = UIView()
        divider.backgroundColor = Theme.Colors.separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true

        let statsRow = UIStackView(arrangedSubviews: [availStack, divider, returnStack])
        statsRow.axis = .horizontal
        statsRow.distribution = .fill
        statsRow.alignment = .center
        statsRow.spacing = Theme.Spacing.md

        infoLabel.font = Theme.Fonts.caption
        infoLabel.textColor = Theme.Colors.secondaryLabel

        let contentStack = UIStackView(arrangedSubviews: [statsRow, infoLabel])
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

    private func makeStatColumn(label: UILabel, count: UILabel, total: UILabel) -> UIStackView {
        let countRow = UIStackView(arrangedSubviews: [count, total])
        countRow.axis = .horizontal
        countRow.alignment = .lastBaseline
        countRow.spacing = 2

        let stack = UIStackView(arrangedSubviews: [label, countRow])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        return stack
    }

    // MARK: - Public

    func configure(station: BikeStation) {
        availableCountLabel.text = "\(station.availableBikes)"
        availableCountLabel.textColor = station.availableBikes == 0 ? Theme.Colors.secondaryLabel : Self.brandGreen
        totalRacksLabel1.text = "/ \(station.totalRacks)"

        returnCountLabel.text = "\(station.availableRacks)"
        totalRacksLabel2.text = "/ \(station.totalRacks)"
    }

    func setInfoText(_ text: String) {
        infoLabel.text = text
    }
}
