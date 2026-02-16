import UIKit
import CoreLocation
import Combine

final class DebugOverlayView: UIView {

    // MARK: - UI

    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        return stack
    }()

    private let latLabel = UILabel()
    private let lonLabel = UILabel()
    private let accuracyLabel = UILabel()
    private let speedLabel = UILabel()
    private let headingLabel = UILabel()
    private let altitudeLabel = UILabel()
    private let timestampLabel = UILabel()

    // MARK: - Properties

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor.black.withAlphaComponent(0.7)
        layer.cornerRadius = Theme.CornerRadius.small

        let allLabels = [latLabel, lonLabel, accuracyLabel, speedLabel,
                         headingLabel, altitudeLabel, timestampLabel]

        for label in allLabels {
            label.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            label.textColor = .systemGreen
            stackView.addArrangedSubview(label)
        }

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])

        // Set initial placeholder text
        updateLocation(nil)
        updateHeading(nil)
    }

    // MARK: - Bind

    func bind(to locationService: LocationService) {
        cancellables.removeAll()

        locationService.locationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                self?.updateLocation(location)
            }
            .store(in: &cancellables)

        locationService.headingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] heading in
                self?.updateHeading(heading)
            }
            .store(in: &cancellables)
    }

    func unbind() {
        cancellables.removeAll()
    }

    // MARK: - Update

    private func updateLocation(_ location: CLLocation?) {
        guard let loc = location else {
            latLabel.text = "LAT: --"
            lonLabel.text = "LON: --"
            accuracyLabel.text = "ACC: --"
            speedLabel.text = "SPD: --"
            altitudeLabel.text = "ALT: --"
            timestampLabel.text = "TIME: --"
            return
        }

        latLabel.text = String(format: "LAT: %.6f", loc.coordinate.latitude)
        lonLabel.text = String(format: "LON: %.6f", loc.coordinate.longitude)
        accuracyLabel.text = String(format: "ACC: %.1fm (H) %.1fm (V)",
                                     loc.horizontalAccuracy, loc.verticalAccuracy)
        speedLabel.text = String(format: "SPD: %.1f m/s (%.0f km/h)",
                                  Swift.max(0, loc.speed), Swift.max(0, loc.speed * 3.6))
        altitudeLabel.text = String(format: "ALT: %.1fm", loc.altitude)

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        timestampLabel.text = "TIME: \(formatter.string(from: loc.timestamp))"
    }

    private func updateHeading(_ heading: CLHeading?) {
        if let h = heading {
            headingLabel.text = String(format: "HDG: %.1f\u{00B0}", h.trueHeading)
        } else {
            headingLabel.text = "HDG: --"
        }
    }
}
