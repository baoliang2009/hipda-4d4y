import UIKit
import SDWebImage

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Configure SDWebImage for optimal image loading
        ImageLoader.configure()

        // 必须在任何网络请求之前恢复登录 Cookie。
        // AccountManager / LoginManager 都是懒加载单例，之前直到用户点开某个页面
        // 才被首次访问，导致首屏的 fetchForumList / fetchThreadList 是在
        // HTTPCookieStorage 为空的情况下发出的（日志里 "cookies BEFORE request:" 为空），
        // 请求以游客身份发出、拿不到数据。这里提前触发初始化。
        _ = AccountManager.shared
        _ = LoginManager.shared

        // Apply dark mode theme
        if #available(iOS 15.0, *) {
            Theme.applyDarkMode(to: nil)
        }

        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }
}