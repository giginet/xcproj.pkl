import Foundation
import Testing

@testable import XCProjGenKit

let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

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
    func executable(_ path: String) throws -> URL {
        let url = try file(path, "#!/bin/sh\n")
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
}

func quoted(_ value: String) -> String {
    String(data: try! JSONEncoder().encode(value), encoding: .utf8)!.replacingOccurrences(
        of: "\\/", with: "/")
}

func expectFailure(containing expected: String, _ operation: () throws -> Void) {
    do {
        try operation()
        Issue.record("Expected an error containing '\(expected)'")
    } catch { #expect(String(describing: error).contains(expected)) }
}

/// A minimal valid project.xcproj with one tool target, standing in for rendered Pkl output.
let toolDocument = #"""
    {
      "configurations": ["Debug"], "default-configuration": "Debug",
      "files": [
        {"kind":"folder","path":"<PROJECT>/Sources","target-membership":["App"]},
        {"kind":"group","name":"Products","children":[{"path":"<PRODUCTS>/App","id":"BBBBBBBBBBBBBBBBBBBBBBBB","type":"compiled.mach-o.executable","index":false}]}
      ],
      "localizations": {"development":"en","supported":["Base"]},
      "targets": [{"name":"App","id":"AAAAAAAAAAAAAAAAAAAAAAAA","product-type":"tool","product":"Products/App","build-phases":["compile-sources"],"dependencies":[]}]
    }
    """#
let toolTargetID = "AAAAAAAAAAAAAAAAAAAAAAAA"

/// Hand-written counterparts of the two JSON documents Pkl produces: the Snapshot of the
/// authored modules, and the rendered plan. Tests use these instead of running Pkl.
struct Scenario {
    private(set) var kind = "project"
    private(set) var root = ""
    private var paths: [[String: Any]] = []
    private var artifacts: [[String: Any]] = []
    private var existingProjects: [[String: Any]] = []

    static func pathRequest(
        _ id: String, base: [String: String], _ path: String, expectedKind: String = "any",
        mustExist: Bool = false
    ) -> [String: Any] {
        [
            "id": id, "base": base, "path": path, "expectedKind": expectedKind,
            "mustExist": mustExist, "context": id,
        ]
    }

    private mutating func bundle(
        _ id: String, kind: String, directory: URL, name: String, file: String
    ) {
        paths.append(
            Self.pathRequest(
                "\(id):bundle", base: ["kind": "uri", "uri": directory.absoluteString], name))
        paths.append(
            Self.pathRequest(
                "\(id):file", base: ["kind": "request", "id": "\(id):bundle", "location": "self"],
                file))
        artifacts.append([
            "id": id, "kind": kind, "bundlePathId": "\(id):bundle", "filePathId": "\(id):file",
        ])
        if root.isEmpty || kind == "workspace" {
            root = id
            self.kind = kind
        }
    }

    /// A generated `<directory>/<name>.xcodeproj`.
    mutating func project(_ id: String, in directory: URL, name: String = "Example") {
        bundle(
            id, kind: "project", directory: directory, name: "\(name).xcodeproj",
            file: "project.xcproj")
    }

    /// A generated `<directory>/<name>.xcworkspace`, which becomes the root artifact.
    mutating func workspace(_ id: String, in directory: URL, name: String = "Modular") {
        bundle(
            id, kind: "workspace", directory: directory, name: "\(name).xcworkspace",
            file: "contents.xcworkspacedata")
    }

    /// A shared scheme stored inside the bundle of `owner`.
    mutating func scheme(_ id: String, in owner: String, file: String? = nil) {
        paths.append(
            Self.pathRequest(
                "\(id):file",
                base: ["kind": "request", "id": "\(owner):bundle", "location": "self"],
                file ?? "xcshareddata/xcschemes/\(id).xcscheme"))
        artifacts.append([
            "id": id, "kind": "scheme", "bundlePathId": "\(owner):bundle",
            "filePathId": "\(id):file",
        ])
    }

    /// A workspace member that is referenced but never generated.
    mutating func existingProject(_ key: String, at bundle: URL, mustExist: Bool = true) {
        paths.append(
            Self.pathRequest(
                "\(key):bundle",
                base: [
                    "kind": "uri", "uri": bundle.deletingLastPathComponent().absoluteString,
                ],
                bundle.lastPathComponent, expectedKind: "directory", mustExist: mustExist))
        existingProjects.append(["key": key, "bundlePathId": "\(key):bundle"])
    }

    /// The Snapshot JSON, as the first Pkl evaluation would print it.
    func snapshot() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "protocolVersion": 1, "schemaVersion": 2, "kind": kind, "rootArtifactId": root,
            "paths": paths, "artifacts": artifacts, "existingProjects": existingProjects,
        ])
    }

    func manifest() throws -> InputManifest {
        try JSONDecoder().decode(InputManifest.self, from: snapshot())
    }

    /// The rendered plan JSON, as the bundled renderer would print it for `facts`.
    /// `texts` overrides the content of individual artifacts.
    func rendered(_ facts: HostFacts, texts: [String: String] = [:]) throws -> Data {
        try Self.rendered(snapshot: snapshot(), facts: JSONEncoder().encode(facts), texts: texts)
    }

    /// The same, from the frozen files handed to the renderer.
    static func rendered(snapshot: Data, facts: Data, texts: [String: String] = [:]) throws
        -> Data
    {
        let snapshot = try #require(
            JSONSerialization.jsonObject(with: snapshot) as? [String: Any])
        let facts = try #require(JSONSerialization.jsonObject(with: facts) as? [String: Any])
        let paths = try #require(facts["paths"] as? [String: [String: Any]])
        let artifacts = try #require(snapshot["artifacts"] as? [[String: String]])
        let files = try artifacts.map { artifact -> [String: Any] in
            let id = try #require(artifact["id"])
            let kind = try #require(artifact["kind"])
            let pathID = try #require(artifact["filePathId"])
            let path = try #require(paths[pathID])
            let fallback =
                kind == "project"
                ? toolDocument
                : kind == "workspace" ? #"<?xml version="1.0"?><Workspace version="1.0"/>"# : ""
            return [
                "artifactId": id, "kind": kind,
                "destinationUri": try #require(path["canonicalUri"]),
                "text": texts[id] ?? fallback,
            ]
        }
        let projects = artifacts.filter { $0["kind"] == "project" }.count
        return try JSONSerialization.data(withJSONObject: [
            "protocolVersion": 1, "rootArtifactId": try #require(snapshot["rootArtifactId"]),
            "projectCount": projects, "targetCount": projects, "files": files,
        ])
    }

    /// Validate the rendered plan exactly as `GenerationPlan.compile` does after rendering.
    func plan(outputDirectory: URL? = nil, texts: [String: String] = [:]) throws
        -> GenerationPlan
    {
        let manifest = try manifest()
        let facts = try HostFacts.observe(manifest, outputDirectory: outputDirectory)
        return try GenerationPlan.accept(
            rendered(facts, texts: texts), manifest: manifest, facts: facts)
    }
}

/// Replaces the pkl process. Records every invocation and answers from `respond`, which
/// returns the process's standard output or throws the diagnostic of a failed run.
final class PklStub: @unchecked Sendable {
    struct Call: Sendable {
        let arguments: [String]
        let workingDirectory: URL?
        var command: String { arguments[0] }
        var source: String { arguments[arguments.count - 1] }
        var properties: [String] {
            arguments.indices.filter { arguments[$0] == "--property" }.map { arguments[$0 + 1] }
        }
        /// The file behind an internal `key=file-URL` property.
        func file(_ key: String) throws -> Data {
            let property = try #require(properties.first { $0.hasPrefix("\(key)=") })
            let url = try #require(URL(string: String(property.dropFirst(key.count + 1))))
            return try Data(contentsOf: url)
        }
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    private let respond: @Sendable (Call) throws -> Data

    init(_ respond: @escaping @Sendable (Call) throws -> Data) { self.respond = respond }

    var calls: [Call] { lock.withLock { recorded } }

    var tool: PklTool {
        PklTool(executable: "/stub/pkl", environment: [:]) { arguments, workingDirectory in
            let call = Call(arguments: arguments, workingDirectory: workingDirectory)
            self.lock.withLock { self.recorded.append(call) }
            return try self.respond(call)
        }
    }

    /// The error PklTool reports when pkl exits with a diagnostic.
    static func failure(_ diagnostic: String, operation: String = "evaluation") -> ProjectError {
        ProjectError("Pkl \(operation) failed (exit 1):\n\(diagnostic)")
    }

    /// Answers like a working pkl: the Snapshot for the entry, then the rendered plan.
    static func rendering(_ scenario: Scenario, texts: [String: String] = [:]) throws -> PklStub {
        let frozen = try scenario.snapshot()
        return PklStub { call in
            switch call.command {
            case "project": return Data()
            case "eval" where call.arguments.contains("renderPlanText"):
                return try Scenario.rendered(
                    snapshot: call.file("xcproj.internal.request"),
                    facts: call.file("xcproj.internal.hostFacts"), texts: texts)
            default: return frozen
            }
        }
    }
}
