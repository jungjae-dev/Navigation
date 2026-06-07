import UIKit

/// 빈 상태/로딩 상태 공통 표현.
/// 검색 결과 없음·즐겨찾기/최근기록 없음·도착정보 없음·로딩 중을 단일 스타일로 통일한다.
final class EmptyStateView: UIView {

    enum State {
        /// 아이콘 + 제목 + 선택적 부제
        case empty(iconName: String, title: String, subtitle: String?)
        /// 인디케이터 + 선택적 캡션
        case loading(caption: String?)
    }

    // MARK: - Subviews

    private let iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Theme.Colors.secondaryLabel
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: Theme.IconSize.xxxl, weight: .regular)
        return imageView
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.color = Theme.Colors.secondaryLabel
        indicator.hidesWhenStopped = true
        return indicator
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Fonts.headline
        label.textColor = Theme.Colors.label
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Fonts.footnote
        label.textColor = Theme.Colors.secondaryLabel
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var stack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [iconView, activityIndicator, titleLabel, subtitleLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = Theme.Spacing.sm
        stack.setCustomSpacing(Theme.Spacing.md, after: iconView)
        return stack
    }()

    // MARK: - Init

    /// - Parameter centered: `true`(기본)면 컨테이너 중앙에 배치(예: tableView.backgroundView).
    ///   `false`면 콘텐츠 높이에 맞춰 self-size(예: 스택/스크롤 안 인라인 배치).
    init(state: State, centered: Bool = true) {
        super.init(frame: .zero)
        setup(centered: centered)
        apply(state)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setup(centered: Bool) {
        addSubview(stack)
        var constraints: [NSLayoutConstraint] = [
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: Theme.Spacing.xl),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Theme.Spacing.xl),
        ]
        if centered {
            constraints.append(stack.centerYAnchor.constraint(equalTo: centerYAnchor))
        } else {
            // 콘텐츠 높이로 self-size (인라인 배치용)
            constraints.append(stack.topAnchor.constraint(equalTo: topAnchor, constant: Theme.Spacing.xl))
            constraints.append(stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Theme.Spacing.xl))
        }
        NSLayoutConstraint.activate(constraints)
    }

    // MARK: - State

    func apply(_ state: State) {
        switch state {
        case let .empty(iconName, title, subtitle):
            activityIndicator.stopAnimating()
            iconView.isHidden = false
            iconView.image = UIImage(systemName: iconName)
            titleLabel.isHidden = false
            titleLabel.text = title
            subtitleLabel.isHidden = subtitle == nil
            subtitleLabel.text = subtitle

        case let .loading(caption):
            iconView.isHidden = true
            activityIndicator.startAnimating()
            titleLabel.isHidden = caption == nil
            titleLabel.text = caption
            subtitleLabel.isHidden = true
        }
    }
}
