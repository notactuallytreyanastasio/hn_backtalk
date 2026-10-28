import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        log("launch")
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Only the main scene asks: rear scenes use the accessory's own
        // configuration (9 of 9 in ../duo_rear's probe log).
        let c = UISceneConfiguration(name: "Main", sessionRole: session.role)
        c.delegateClass = MainSceneDelegate.self
        return c
    }
}

final class MainSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var rear: UISceneAccessoryRegistration?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: scene)
#if DEBUG
        if UserDefaults.standard.bool(forKey: "previewRear") {
            w.rootViewController = RearViewController()
            w.makeKeyAndVisible()
            window = w
            if !UserDefaults.standard.bool(forKey: "previewCover") { Roast.shared.preview() }
            Task { Roast.shared.show(frontPage: (try? await HN.frontPage()) ?? []) }
            return
        }
#endif
        let nav = UINavigationController(rootViewController: StoriesViewController())
        styleNavigation(nav)
        w.rootViewController = nav
        w.tintColor = Theme.orange
        w.makeKeyAndVisible()
        window = w
        // Registered by the front page, the rear went dark when a thread was
        // pushed over it: the accessory lasts while its view controller is on
        // screen. The navigation controller always is.
        rear = Rear.register(from: nav)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        if Rear.bright { Camera.shared.start() }
    }
}
