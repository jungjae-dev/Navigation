import UIKit

/// 따릉이 공식 앱 실행 헬퍼.
/// URL Scheme 으로 열고, 실패하면 App Store 페이지로 이동.
@MainActor
enum BikeAppLauncher {

    /// 따릉이 앱 App Store ID
    private static let appStoreId = "1037272004"

    /// 따릉이 공식 앱 URL Scheme (path/parameter 미공개 — 앱 메인만 진입)
    private static let appScheme = "bikeseoul"

    static func openRent() {
        let url = URL(string: "\(appScheme)://")!
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        } else {
            openAppStore()
        }
    }

    private static func openAppStore() {
        // itms-apps 로 시도 → 실패 시 https 폴백 (시뮬레이터는 App Store 미설치라 https 사용)
        let itms = URL(string: "itms-apps://apps.apple.com/app/id\(appStoreId)")!
        let web = URL(string: "https://apps.apple.com/app/id\(appStoreId)")!
        if UIApplication.shared.canOpenURL(itms) {
            UIApplication.shared.open(itms, options: [:], completionHandler: nil)
        } else {
            UIApplication.shared.open(web, options: [:], completionHandler: nil)
        }
    }
}
