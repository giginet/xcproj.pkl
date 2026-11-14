import DemoCore
import DemoNetworking
import DemoNotifications
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        print(Greeting.message)
        print(NotificationFormatter.title(for: APIClient().welcomeMessage()))
        return true
    }
}
