import DemoNotifications
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        content.title = NotificationFormatter.title(for: content.title)
        // This example finishes synchronously and calls the handler exactly once.
        contentHandler(content)
    }
}
