import UIKit

final class DrawerIconButton: UIButton {

    enum Preset {
        case close
        case favorite
        case settings
        case back

        var iconName: String {
            switch self {
            case .close: "xmark.circle.fill"
            case .favorite: "star"
            case .settings: "gearshape.fill"
            case .back: "chevron.left"
            }
        }

        var tintColorValue: UIColor {
            switch self {
            case .close: Theme.Button.Icon.tintColor
            case .favorite: Theme.Colors.primary
            case .settings: Theme.Button.Icon.tintColor
            case .back: Theme.Colors.label
            }
        }
    }

    private var preset: Preset?

    init(preset: Preset) {
        self.preset = preset
        super.init(frame: .zero)
        setupWithPreset(preset)
    }

    init(iconName: String, tintColor: UIColor = Theme.Button.Icon.tintColor) {
        super.init(frame: .zero)
        setupWithIcon(iconName: iconName, tintColor: tintColor)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupWithPreset(_ preset: Preset) {
        setupWithIcon(iconName: preset.iconName, tintColor: preset.tintColorValue)
    }

    private func setupWithIcon(iconName: String, tintColor: UIColor) {
        translatesAutoresizingMaskIntoConstraints = false

        let config = UIImage.SymbolConfiguration(pointSize: Theme.Button.Icon.imageSize, weight: .medium)
        let image = UIImage(systemName: iconName)?.withConfiguration(config)
        setImage(image, for: .normal)
        self.tintColor = tintColor

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Theme.Button.Icon.size),
            heightAnchor.constraint(equalToConstant: Theme.Button.Icon.size),
        ])
    }

    func setFavoriteState(_ isFavorite: Bool) {
        let iconName = isFavorite ? "star.fill" : "star"
        let config = UIImage.SymbolConfiguration(pointSize: Theme.Button.Icon.imageSize, weight: .medium)
        let image = UIImage(systemName: iconName)?.withConfiguration(config)
        setImage(image, for: .normal)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let minSize = Theme.Button.Icon.hitAreaMinimum
        let dx = max(0, (minSize - bounds.width) / 2)
        let dy = max(0, (minSize - bounds.height) / 2)
        let expandedBounds = bounds.insetBy(dx: -dx, dy: -dy)
        return expandedBounds.contains(point)
    }
}
