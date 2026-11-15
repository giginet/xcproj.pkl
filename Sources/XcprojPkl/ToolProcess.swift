import Foundation

/// File-backed streams avoid pipe buffer limits when rendering large workspaces.
func runTool(
    executable: URL, arguments: [String], workingDirectory: URL? = nil,
    input: Data? = nil, operation: String
) throws -> Data {
    let manager = FileManager.default
    let temporary = manager.temporaryDirectory.appendingPathComponent(
        "xcprojgen-tool-\(UUID().uuidString)")
    try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: temporary) }
    let out = temporary.appendingPathComponent("stdout")
    let err = temporary.appendingPathComponent("stderr")
    manager.createFile(atPath: out.path, contents: nil)
    manager.createFile(atPath: err.path, contents: nil)
    let output = try FileHandle(forWritingTo: out)
    let errors = try FileHandle(forWritingTo: err)
    var inputHandle: FileHandle?
    defer {
        try? inputHandle?.close()
        try? output.close()
        try? errors.close()
    }
    if let input {
        let source = temporary.appendingPathComponent("stdin")
        try input.write(to: source)
        inputHandle = try FileHandle(forReadingFrom: source)
    }
    let process = Process()
    process.executableURL = executable
    process.currentDirectoryURL = workingDirectory
    process.arguments = arguments
    process.standardInput = inputHandle ?? FileHandle.nullDevice
    process.standardOutput = output
    process.standardError = errors
    do { try process.run() } catch {
        throw ProjectError("Could not run \(operation): \(error.localizedDescription)")
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let diagnostic = String(decoding: try Data(contentsOf: err), as: UTF8.self)
        let standardOutput = String(decoding: try Data(contentsOf: out), as: UTF8.self)
        throw ProjectError(
            "\(operation) failed (exit \(process.terminationStatus)):\n\(diagnostic)\(standardOutput)"
        )
    }
    return try Data(contentsOf: out)
}
