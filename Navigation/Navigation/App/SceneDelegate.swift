import UIKit
import SwiftData

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var appCoordinator: AppCoordinator?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        // Initialize SwiftData
        setupSwiftData()

        let window = UIWindow(windowScene: windowScene)
        self.window = window

        appCoordinator = AppCoordinator(window: window)
        appCoordinator?.start()
    }

    private func setupSwiftData() {
        do {
            let storeDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

            // 모델별 독립 SQLite 파일 — 각 도메인의 schema 변경이 서로 영향을 주지 않음
            let container = try ModelContainer(
                for: Schema([FavoritePlace.self, SearchHistory.self, Recording.self]),
                configurations: [
                    ModelConfiguration(
                        "Favorites",
                        schema: Schema([FavoritePlace.self]),
                        url: storeDir.appendingPathComponent("Favorites.store")
                    ),
                    ModelConfiguration(
                        "SearchHistory",
                        schema: Schema([SearchHistory.self]),
                        url: storeDir.appendingPathComponent("SearchHistory.store")
                    ),
                    ModelConfiguration(
                        "Recordings",
                        schema: Schema([Recording.self]),
                        url: storeDir.appendingPathComponent("Recordings.store")
                    ),
                ]
            )
            DataService.shared.configure(with: container)
        } catch {
            print("[SceneDelegate] SwiftData setup failed: \(error)")
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {}

    func sceneDidBecomeActive(_ scene: UIScene) {}

    func sceneWillResignActive(_ scene: UIScene) {}

    func sceneWillEnterForeground(_ scene: UIScene) {}

    func sceneDidEnterBackground(_ scene: UIScene) {}
}
