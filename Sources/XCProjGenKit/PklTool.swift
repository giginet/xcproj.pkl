import Foundation

/// Shared process boundary for evaluation, dependency resolution, and diagnostics.
public struct PklTool: Sendable {
    public static let minimumVersion = "0.33.0"
    public static let installationGuide =
        "https://pkl-lang.org/main/current/pkl-cli/index.html#installation"

    private let executable: String

    public init(executable: String? = nil) {
        self.executable = executable ?? ProcessInfo.processInfo.environment["PKL_EXEC"] ?? "pkl"
    }

    public func evaluate(_ source: URL, properties: [String] = [], expression: String? = nil) throws
        -> Data
    {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory),
            !isDirectory.boolValue
        else { throw ProjectError("Pkl input: file does not exist: \(source.path)") }
        return try run(
            [
                "eval", "--format", "json", "--timeout", "60",
                "--working-dir", source.deletingLastPathComponent().path,
            ]
                + properties.flatMap { ["--property", $0] }
                + (expression.map { ["--expression", $0] } ?? []) + [source.path],
            workingDirectory: source.deletingLastPathComponent(), operation: "evaluation")
    }

    public struct Installation: Sendable {
        public let executable: URL
        public let version: String
        public let isSupported: Bool
    }

    public func installation() throws -> Installation {
        let url = try executableURL()
        let data = try run(["--version"], operation: "version check")
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(
            in: .whitespacesAndNewlines)
        let regex = try NSRegularExpression(
            pattern:
                #"^Pkl (([0-9]+)\.([0-9]+)\.([0-9]+)(-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?)(?:\s|$)"#
        )
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let versionRange = Range(match.range(at: 1), in: text),
            let majorRange = Range(match.range(at: 2), in: text),
            let minorRange = Range(match.range(at: 3), in: text),
            let patchRange = Range(match.range(at: 4), in: text),
            let major = Int(text[majorRange]), let minor = Int(text[minorRange]),
            let patch = Int(text[patchRange])
        else { throw ProjectError("Could not parse Pkl version: \(text)") }
        let supported =
            major > 0 || minor > 33
            || (minor == 33 && (patch > 0 || match.range(at: 5).location == NSNotFound))
        return Installation(
            executable: url, version: String(text[versionRange]), isSupported: supported)
    }

    public func resolveProject(at directory: URL, properties: [String] = []) throws {
        _ = try run(
            ["project", "resolve", "--working-dir", directory.path]
                + properties.flatMap { ["--property", $0] } + [directory.path],
            workingDirectory: directory, operation: "dependency resolution")
    }

    private func executableURL() throws -> URL {
        let manager = FileManager.default
        if executable.contains("/") {
            let url = URL(fileURLWithPath: executable).standardizedFileURL
            guard manager.isExecutableFile(atPath: url.path) else { throw unavailable() }
            return url
        }
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":")
        guard
            let url = paths.map({ URL(fileURLWithPath: $0).appendingPathComponent(executable) })
                .first(where: { manager.isExecutableFile(atPath: $0.path) })
        else { throw unavailable() }
        return url
    }

    private func unavailable() -> ProjectError {
        ProjectError(
            "Pkl executable not found or not executable: \(executable).\n"
                + "Install Pkl \(Self.minimumVersion)+, set PKL_EXEC, or pass --pkl /path/to/pkl.\n"
                + "Installation: \(Self.installationGuide)")
    }

    private func run(_ arguments: [String], workingDirectory: URL? = nil, operation: String) throws
        -> Data
    {
        try runTool(
            executable: executableURL(), arguments: arguments, workingDirectory: workingDirectory,
            operation: "Pkl \(operation)")
    }
}
