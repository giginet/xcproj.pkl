import Foundation

/// Preflight structural conflicts without creating or modifying files.
func validateOutputFile(_ file: URL) throws {
    let manager = FileManager.default
    var directory: ObjCBool = false
    if manager.fileExists(atPath: file.path, isDirectory: &directory), directory.boolValue {
        throw ProjectError("Output file is a directory: \(file.path)")
    }
    var parent = file.deletingLastPathComponent()
    while parent.path != "/" {
        if manager.fileExists(atPath: parent.path, isDirectory: &directory), !directory.boolValue {
            throw ProjectError("Output directory is a file: \(parent.path)")
        }
        parent.deleteLastPathComponent()
    }
}

@discardableResult
func writeIfChanged(_ data: Data, to file: URL) throws -> Bool {
    if let existing = try? Data(contentsOf: file), existing == data { return false }
    try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: file, options: .atomic)
    return true
}
