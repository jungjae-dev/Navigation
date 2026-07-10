import UIKit

/// 주차 사진 확대 뷰어 — 핀치줌 (T019)
final class ParkingPhotoViewerViewController: UIViewController, UIScrollViewDelegate {

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let photoURL: URL

    init(photoURL: URL) {
        self.photoURL = photoURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
        )

        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        view.addSubview(scrollView)

        imageView.image = UIImage(contentsOfFile: photoURL.path)
        imageView.contentMode = .scaleAspectFit
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.addSubview(imageView)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }
}
