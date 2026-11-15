import Foundation

/// Resolve Xcode tools through xcrun, honoring xcode-select and DEVELOPER_DIR.
public enum XcodeTool: String, CaseIterable, Sendable {
    case xcodeproj
    case xcprojformatter

    /// Check both tool discovery and launchability.
    public func check() throws -> URL {
        let path = String(decoding: try run(find: true), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try run(arguments: ["--help"])
        return URL(fileURLWithPath: path)
    }

    func run(arguments: [String] = [], input: Data? = nil, find: Bool = false) throws -> Data {
        do {
            return try runTool(
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: (find ? ["--find"] : []) + [rawValue] + arguments,
                input: input, operation: "xcrun \(rawValue)")
        } catch {
            throw ProjectError(
                "\(error.localizedDescription)\n"
                    + "Install Xcode 27.2 or later, then select it with xcode-select or DEVELOPER_DIR. "
                    + "Run 'xcprojgen doctor' to check the tools.")
        }
    }
}
