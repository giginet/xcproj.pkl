import Foundation
import PklRuntimeResources

public enum AgentSkills {
    public static let name = "xcprojgen"

    public enum ExportResult: String {
        case exported = "Exported"
        case updated = "Updated"
        case unchanged = "Unchanged"
    }

    /// Export bundled files under outputDirectory/xcprojgen, preserving unrelated files.
    public static func export(to outputDirectory: URL) throws -> ExportResult {
        let manager = FileManager.default
        let source = PklRuntimeResources.agentSkill
        let destination = outputDirectory.appendingPathComponent(name)
        let existed = manager.fileExists(atPath: destination.path)
        var files: [(url: URL, data: Data)] = []
        for path in try manager.subpathsOfDirectory(atPath: source.path).sorted() {
            let file = source.appendingPathComponent(path)
            if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                files.append((destination.appendingPathComponent(path), try Data(contentsOf: file)))
            }
        }
        for file in files { try validateOutputFile(file.url) }

        var changed = false
        for file in files {
            if try writeIfChanged(file.data, to: file.url) { changed = true }
        }
        return changed ? (existed ? .updated : .exported) : .unchanged
    }
}
