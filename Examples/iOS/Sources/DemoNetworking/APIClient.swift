import DemoCore

public struct APIClient: Sendable {
    public init() {}

    public func welcomeMessage() -> String {
        Greeting.message
    }
}
