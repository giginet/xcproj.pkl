import Foundation

public struct ProjectError: Error, CustomStringConvertible, LocalizedError, Sendable {
    public let diagnostics: [String]

    public init(_ message: String) { diagnostics = [message] }
    public init(_ diagnostics: [String]) { self.diagnostics = diagnostics }
    public var description: String { diagnostics.joined(separator: "\n") }
    public var errorDescription: String? { description }
}
