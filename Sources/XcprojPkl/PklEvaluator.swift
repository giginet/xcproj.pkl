import Foundation

public struct PklEvaluator: Sendable {
  public let executable: String
  public init(executable: String? = nil) {
    self.executable = executable ?? ProcessInfo.processInfo.environment["PKL_EXEC"] ?? "pkl"
  }

  public func evaluate(_ source: URL, properties: [String] = [], expression: String? = nil) throws
    -> Data
  {
    try requirePath(source, directory: false, at: "Pkl input")
    let manager = FileManager.default
    let url: URL
    if executable.contains("/") {
      url = URL(fileURLWithPath: executable)
    } else {
      let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
      guard
        let found = paths.map({
          URL(fileURLWithPath: String($0)).appendingPathComponent(executable)
        })
        .first(where: { manager.isExecutableFile(atPath: $0.path) })
      else {
        throw ProjectError(
          "Pkl executable not found. Install Pkl 0.33+, set PKL_EXEC, or pass --pkl /path/to/pkl.")
      }
      url = found
    }
    let temporary = manager.temporaryDirectory.appendingPathComponent(
      "xcproj-pkl-\(UUID().uuidString)")
    try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: temporary) }
    let out = temporary.appendingPathComponent("stdout")
    let err = temporary.appendingPathComponent("stderr")
    manager.createFile(atPath: out.path, contents: nil)
    manager.createFile(atPath: err.path, contents: nil)
    let output = try FileHandle(forWritingTo: out)
    let errors = try FileHandle(forWritingTo: err)
    defer {
      try? output.close()
      try? errors.close()
    }
    let process = Process()
    process.executableURL = url
    process.currentDirectoryURL = source.deletingLastPathComponent()
    process.arguments =
      ["eval", "--format", "json", "--timeout", "60"]
      + properties.flatMap { ["--property", $0] }
      + (expression.map { ["--expression", $0] } ?? []) + [source.path]
    process.standardOutput = output
    process.standardError = errors
    do { try process.run() } catch {
      throw ProjectError("Could not run Pkl at \(url.path): \(error.localizedDescription)")
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      let diagnostic = String(decoding: try Data(contentsOf: err), as: UTF8.self)
      throw ProjectError(
        "Pkl evaluation failed (exit \(process.terminationStatus)):\n\(diagnostic)")
    }
    return try Data(contentsOf: out)
  }
}
