import Foundation

/// Validates a JSON or legacy Xcode project bundle without modifying it.
/// JSON projects receive schema and local reference validation. Legacy projects
/// receive structural checks only, not a full semantic validation of PBX objects.
public enum ProjectBundleValidator {
    public static func validate(_ bundle: URL) throws -> Int {
        var isDirectory: ObjCBool = false
        guard bundle.pathExtension == "xcodeproj",
            FileManager.default.fileExists(atPath: bundle.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { throw ProjectError("Expected an existing .xcodeproj directory: \(bundle.path)") }

        let candidates = ["project.xcproj", "project.pbxproj"].map {
            bundle.appendingPathComponent($0)
        }
        let files = candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard files.count == 1, let file = files.first else {
            throw ProjectError(
                "Expected exactly one project.xcproj or project.pbxproj: \(bundle.path)")
        }
        _ = FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory)
        guard !isDirectory.boolValue else {
            throw ProjectError("Project document is a directory: \(file.path)")
        }
        let data = try Data(contentsOf: file)
        if file.pathExtension == "xcproj" { return try ProjectValidator.validate(data: data) }
        return try validateLegacy(data: data)
    }

    private static func validateLegacy(data: Data) throws -> Int {
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw ProjectError("Invalid project.pbxproj syntax: \(error.localizedDescription)")
        }
        guard let document = plist as? [String: Any],
            let objects = document["objects"] as? [String: [String: Any]],
            let rootID = document["rootObject"] as? String,
            let root = objects[rootID], root["isa"] as? String == "PBXProject",
            let targets = root["targets"] as? [String]
        else {
            throw ProjectError("Invalid project.pbxproj objects, rootObject, or PBXProject targets")
        }
        guard Set(targets).count == targets.count else {
            throw ProjectError("Duplicate project.pbxproj target references")
        }
        let targetKinds: Set<String> = ["PBXNativeTarget", "PBXAggregateTarget", "PBXLegacyTarget"]
        for targetID in targets {
            guard let target = objects[targetID], let kind = target["isa"] as? String,
                targetKinds.contains(kind)
            else { throw ProjectError("Invalid project.pbxproj target reference: \(targetID)") }
        }
        return targets.count
    }
}
