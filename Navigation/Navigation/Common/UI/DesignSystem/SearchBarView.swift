import UIKit

final class SearchBarView: UIView {

    // MARK: - Callback

    var onTapped: (() -> Void)?

    // MARK: - UI Components

    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.tintColor = Theme.Drawer.SearchBar.iconColor
        iv.image = UIImage(systemName: "magnifyingglass")?
            .withConfiguration(UIImage.SymbolConfiguration(
                pointSize: Theme.Drawer.SearchBar.iconSize, weight: .medium
            ))
        return iv
    }()

    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Drawer.SearchBar.font
        label.textColor = Theme.Drawer.SearchBar.placeholderColor
        return label
    }()

    // MARK: - Init

    init(placeholder: String = "여기서 검색") {
        super.init(frame: .zero)
        placeholderLabel.text = placeholder
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = Theme.Drawer.SearchBar.backgroundColor
        layer.cornerRadius = Theme.Drawer.SearchBar.cornerRadius

        addSubview(iconImageView)
        addSubview(placeholderLabel)

        let hPadding = Theme.Drawer.SearchBar.horizontalPadding
        let iconSize = Theme.Drawer.SearchBar.iconSize

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Theme.Drawer.SearchBar.height),

            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hPadding),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: iconSize),

            placeholderLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: Theme.Spacing.sm),
            placeholderLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hPadding),
            placeholderLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }

    @objc private func handleTap() {
        onTapped?()
    }
}
