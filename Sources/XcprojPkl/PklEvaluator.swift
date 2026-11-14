import Foundation

public struct PklEvaluator: Sendable {
    public let executable: String
    public init(executable: String? = nil) {
        self.executable = PklTool(executable: executable).executable
    }

    public func evaluate(_ source: URL, properties: [String] = [], expression: String? = nil) throws
        -> Data
    {
        try requirePath(source, directory: false, at: "Pkl input")
        return try PklTool(executable: executable).run(
            [
                "eval", "--format", "json", "--timeout", "60",
                "--working-dir", source.deletingLastPathComponent().path,
            ]
                + properties.flatMap { ["--property", $0] }
                + (expression.map { ["--expression", $0] } ?? []) + [source.path],
            workingDirectory: source.deletingLastPathComponent(), operation: "evaluation")
    }
}
