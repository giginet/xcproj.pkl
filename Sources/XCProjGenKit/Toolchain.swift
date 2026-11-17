import Foundation

/// The checks behind `xcprojgen doctor`.
public enum Toolchain {
    public struct Report: Sendable {
        public let lines: [String]
        public let isReady: Bool
    }

    public static func check(
        pkl: PklTool, xcodeTool: (XcodeTool) throws -> URL = { try $0.check() }
    ) -> Report {
        var lines: [String] = []
        var failed = false
        do {
            let installation = try pkl.installation()
            lines.append("Pkl executable: \(installation.executable.path)")
            lines.append("Pkl version: \(installation.version)")
            lines.append("Required: >= \(PklTool.minimumVersion)")
            guard installation.isSupported else {
                throw ProjectError(
                    "Unsupported Pkl version. Update Pkl: \(PklTool.installationGuide)")
            }
        } catch {
            lines.append("Pkl: \(error.localizedDescription)")
            failed = true
        }
        for tool in XcodeTool.allCases {
            do {
                let executable = try xcodeTool(tool)
                lines.append("\(tool.rawValue) executable: \(executable.path) (ready)")
            } catch {
                lines.append("\(tool.rawValue): \(error.localizedDescription)")
                failed = true
            }
        }
        if !failed { lines.append("All tools are ready.") }
        return Report(lines: lines, isReady: !failed)
    }
}
