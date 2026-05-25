import UIKit
import CoreLocation

/// 지도 위 항목 (POI, 따릉이 정류소, 향후 버스/지하철 등) 통합 상세 시트
/// MapItemContent 프로토콜을 구현한 어떤 컨텐츠도 호스팅 가능
/// scaffold (헤더 + 컨텐츠 호스트 + 푸터) 만 담당
final class MapItemDetailViewController: UIViewController {

    // MARK: - Callbacks

    var onClose: (() -> Void)?

    // MARK: - Properties

    private(set) var content: any MapItemContent

    // MARK: - UI

    private let headerView = DrawerHeaderView()
    private let closeButton = DrawerIconButton(preset: .close)
    private let contentContainer = UIView()
    private var footerActionStack: UIStackView?

    // MARK: - Init

    init(content: any MapItemContent) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        configure()
    }

    // MARK: - Public

    /// 다른 항목으로 컨텐츠 교체 (같은 드로어에서 컨텐츠만 swap)
    func update(content: any MapItemContent) {
        self.content = content
        configure()
        rebuildFooterButtons()
    }

    /// 같은 식별자인지 체크 (호출자가 update vs push 결정용)
    func isSameItem(_ other: any MapItemContent) -> Bool {
        return content.identifier == other.identifier
    }

    /// 현재 위치 → 항목 거리 갱신
    func updateDistance(from coordinate: CLLocationCoordinate2D?) {
        content.updateDistance(from: coordinate)
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = Theme.Colors.background

        headerView.addRightAction(closeButton)

        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(headerView)
        view.addSubview(contentContainer)

        let padding = Theme.Drawer.Layout.contentHorizontalPadding

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            contentContainer.topAnchor.constraint(
                equalTo: headerView.bottomAnchor,
                constant: Theme.Drawer.Layout.contentTopPadding
            ),
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            contentContainer.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
        ])

        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    }

    // MARK: - Configure

    private func configure() {
        headerView.setLeftIcon(content.iconImage, size: Theme.Drawer.Cell.iconSize)
        headerView.setTitle(content.title)

        // 컨텐츠 view 교체 (같은 인스턴스면 skip)
        let newContent = content.contentView
        if contentContainer.subviews.first !== newContent {
            contentContainer.subviews.forEach { $0.removeFromSuperview() }
            newContent.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(newContent)
            NSLayoutConstraint.activate([
                newContent.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                newContent.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                newContent.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
                newContent.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            ])
        }
    }

    private func rebuildFooterButtons() {
        guard let stack = footerActionStack else { return }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for action in content.footerActions {
            let button = DrawerActionButton(style: action.style, title: action.title, iconName: action.iconName)
            button.addAction(UIAction { _ in action.handler() }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        onClose?()
    }
}

// MARK: - DrawerFooterProviding (하단 고정 액션 버튼)

extension MapItemDetailViewController: DrawerFooterProviding {

    var footerContentView: UIView {
        let container = UIView()
        container.backgroundColor = Theme.Colors.background

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .center   // primary(48)/secondary(40) 높이 충돌 방지
        stack.spacing = Theme.Spacing.sm
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        self.footerActionStack = stack

        let padding = Theme.Drawer.Layout.contentHorizontalPadding

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: Theme.Spacing.md),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Theme.Spacing.md),
        ])

        // 초기 액션 버튼 채우기
        rebuildFooterButtons()

        return container
    }
}
