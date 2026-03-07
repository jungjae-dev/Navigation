import UIKit

final class DrawerActionButton: UIButton {

    enum Style {
        case primary
        case secondary
        case destructive
    }

    private let style: Style

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    private var originalTitle: String?

    var isLoading: Bool = false {
        didSet {
            if isLoading {
                originalTitle = title(for: .normal)
                setTitle(nil, for: .normal)
                loadingIndicator.startAnimating()
                isEnabled = false
            } else {
                setTitle(originalTitle, for: .normal)
                loadingIndicator.stopAnimating()
                isEnabled = true
            }
        }
    }

    // MARK: - Init

    init(style: Style, title: String, iconName: String? = nil) {
        self.style = style
        super.init(frame: .zero)
        setupStyle(title: title, iconName: iconName)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupStyle(title: String, iconName: String?) {
        translatesAutoresizingMaskIntoConstraints = false

        var config = UIButton.Configuration.filled()
        config.title = title
        config.cornerStyle = .fixed
        config.imagePadding = Theme.Spacing.sm

        if let iconName {
            config.image = UIImage(systemName: iconName)
        }

        switch style {
        case .primary:
            config.baseBackgroundColor = Theme.Button.Primary.backgroundColor
            config.baseForegroundColor = Theme.Button.Primary.foregroundColor
            titleLabel?.font = Theme.Button.Primary.font
            layer.cornerRadius = Theme.Button.Primary.cornerRadius
            heightAnchor.constraint(equalToConstant: Theme.Button.Primary.height).isActive = true

        case .secondary:
            config.baseBackgroundColor = Theme.Button.Secondary.backgroundColor
            config.baseForegroundColor = Theme.Button.Secondary.foregroundColor
            titleLabel?.font = Theme.Button.Secondary.font
            layer.cornerRadius = Theme.Button.Secondary.cornerRadius
            layer.borderColor = Theme.Button.Secondary.borderColor.cgColor
            layer.borderWidth = Theme.Button.Secondary.borderWidth
            heightAnchor.constraint(equalToConstant: Theme.Button.Secondary.height).isActive = true

        case .destructive:
            config.baseBackgroundColor = Theme.Button.Destructive.backgroundColor
            config.baseForegroundColor = Theme.Button.Destructive.foregroundColor
            titleLabel?.font = Theme.Button.Destructive.font
            layer.cornerRadius = Theme.Button.Destructive.cornerRadius
            heightAnchor.constraint(equalToConstant: Theme.Button.Destructive.height).isActive = true
        }

        config.background.cornerRadius = layer.cornerRadius
        configuration = config

        addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}
