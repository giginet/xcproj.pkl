import Foundation

public enum EntryModule {
    /// A directory selects its Project.pkl; a .pkl file selects itself.
    /// The entry's Pkl type determines whether a project or workspace is generated.
    public static func resolve(_ path: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory) else {
            throw ProjectError(
                "Input does not exist: \(path.path). Use 'xcprojgen init <dir>' to create a project."
            )
        }
        if isDirectory.boolValue {
            let module = path.appendingPathComponent("Project.pkl")
            var entryIsDirectory: ObjCBool = false
            guard
                FileManager.default.fileExists(atPath: module.path, isDirectory: &entryIsDirectory),
                !entryIsDirectory.boolValue
            else {
                throw ProjectError(
                    "Entry module not found: \(module.path). Pass a .pkl file path to select another entry."
                )
            }
            return module
        }
        guard path.pathExtension == "pkl" else {
            throw ProjectError(
                "Expected a project directory containing Project.pkl or a .pkl module")
        }
        return path
    }

    /// The nearest enclosing directory containing a PklProject, matching Pkl's upward discovery.
    public static func projectDirectory(for source: URL) -> URL? {
        var directory = source.resolvingSymlinksInPath().deletingLastPathComponent()
            .standardizedFileURL
        while true {
            if FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("PklProject").path)
            {
                return directory
            }
            // Deleting the last component of "/" yields "/..", so stop at the root explicitly.
            if directory.path == "/" { return nil }
            directory = directory.deletingLastPathComponent().standardizedFileURL
        }
    }
}
