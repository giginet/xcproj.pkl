import Foundation
import Testing

@testable import XcprojPkl

let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  .deletingLastPathComponent().deletingLastPathComponent()
let schema = repository.appendingPathComponent("Pkl/xcproj/Project.pkl").path
let workspaceSchema = repository.appendingPathComponent("Pkl/xcproj/Workspace.pkl").path
let hasPkl = ProcessInfo.processInfo.environment["PKL_EXEC"] != nil

func quoted(_ value: String) -> String {
  String(data: try! JSONEncoder().encode(value), encoding: .utf8)!.replacingOccurrences(
    of: "\\/", with: "/")
}
func shellQuoted(_ value: String) -> String {
  "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

final class Fixture {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "xcproj-v2-test-\(UUID())")
  init() throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }
  deinit { try? FileManager.default.removeItem(at: root) }
  @discardableResult
  func file(_ path: String, _ text: String = "") throws -> URL {
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
    return url
  }
  func directory(_ path: String) throws {
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent(path), withIntermediateDirectories: true)
  }
  func symlink(_ path: String, to target: String) throws {
    try FileManager.default.createSymbolicLink(
      atPath: root.appendingPathComponent(path).path, withDestinationPath: target)
  }
  @discardableResult
  func project(_ body: String = "", at path: String = "Project.pkl") throws -> URL {
    let lines = body.components(separatedBy: "\n")
    let imports = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("import ") }
    let rest = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("import ") }
    return try file(
      path,
      "amends \(quoted(schema))\n" + imports.joined(separator: "\n")
        + "\nname = \"Example\"\nidNamespace = \"com.example\"\n" + rest.joined(separator: "\n"))
  }
  func compile(_ body: String, output: URL? = nil) throws -> GenerationPlan {
    try GenerationPlan.compile(source: project(body), output: output)
  }
  func tool(_ extra: String = "", output: URL? = nil) throws -> GenerationPlan {
    try compile(
      "targets { [\"app\"] { name = \"App\"; type = \"tool\"; platform = \"macOS\"; \(extra) } }",
      output: output)
  }
  func workspace(
    _ entries: String = #"["a"] = import("A/Project.pkl"); ["b"] = import("B/Project.pkl")"#
  ) throws -> URL {
    try file(
      "Workspace.pkl",
      "amends \(quoted(workspaceSchema))\nname = \"Modular\"\nprojects { \(entries) }\n")
  }
  func pair() throws -> URL {
    for key in ["A", "B"] {
      try project(
        "targets { [\"app\"] { name = \"\(key)\"; type = \"tool\"; platform = \"macOS\" } }",
        at: "\(key)/Project.pkl")
    }
    return try workspace()
  }
}

func expectFailure(containing expected: String, _ operation: () throws -> Void) {
  do {
    try operation()
    Issue.record("Expected an error containing '\(expected)'")
  } catch { #expect(String(describing: error).contains(expected)) }
}
