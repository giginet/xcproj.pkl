import Foundation
import Testing

@testable import XCProjGenKit

let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let schema = repository.appendingPathComponent("Pkl/xcproj/Project.pkl").path
let workspaceSchema = repository.appendingPathComponent("Pkl/xcproj/Workspace.pkl").path

final class Fixture {
    let root: URL
    init() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xcproj-v2-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Generated paths are canonical, so compare against the canonical root.
        root = directory.resolvingSymlinksInPath()
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    func url(_ path: String) -> URL { root.appendingPathComponent(path) }
    func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: url(path).path) }
    func text(_ path: String) throws -> String {
        try String(contentsOf: url(path), encoding: .utf8)
    }
    @discardableResult
    func file(_ path: String, _ text: String = "") throws -> URL {
        let url = url(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }
    @discardableResult
    func executable(_ path: String, script: String = "") throws -> URL {
        let url = try file(path, "#!/bin/sh\n\(script)\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
    func directory(_ path: String) throws {
        try FileManager.default.createDirectory(at: url(path), withIntermediateDirectories: true)
    }
    func symlink(_ path: String, to target: String) throws {
        try FileManager.default.createSymbolicLink(
            atPath: url(path).path, withDestinationPath: target)
    }

    // Authoring helpers for suites that evaluate real Pkl modules.
    @discardableResult
    func project(_ body: String = "", at path: String = "Project.pkl") throws -> URL {
        let lines = body.components(separatedBy: "\n")
        let imports = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("import ") }
        let rest = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("import ") }
        return try file(
            path,
            "amends \(quoted(schema))\n" + imports.joined(separator: "\n")
                + "\nname = \"Example\"\nbundleIdPrefix = \"com.example\"\n"
                + rest.joined(separator: "\n"))
    }
    func compile(_ body: String, outputDirectory: URL? = nil) throws -> GenerationPlan {
        try GenerationPlan.compile(source: project(body), outputDirectory: outputDirectory)
    }
    func tool(_ extra: String = "", outputDirectory: URL? = nil) throws -> GenerationPlan {
        try compile(
            "targets { [\"app\"] { name = \"App\"; type = \"tool\"; platform = \"macOS\"; \(extra) } }",
            outputDirectory: outputDirectory)
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

func quoted(_ value: String) -> String {
    String(data: try! JSONEncoder().encode(value), encoding: .utf8)!.replacingOccurrences(
        of: "\\/", with: "/")
}

func shellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

func expectFailure(containing expected: String, _ operation: () throws -> Void) {
    do {
        try operation()
        Issue.record("Expected an error containing '\(expected)'")
    } catch { #expect(String(describing: error).contains(expected)) }
}
