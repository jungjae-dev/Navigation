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
            let schema = Schema([FavoritePlace.self, SearchHistory.self, GPXRecord.self])
            let config = ModelConfiguration(isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [config])
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
