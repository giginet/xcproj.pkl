import DemoCore

public enum NotificationFormatter {
    public static func title(for title: String) -> String {
        "[\(Greeting.message)] \(title)"
    }
}
