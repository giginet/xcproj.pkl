import Foundation
import Testing
import XcodeProjectFormat

@testable import XCProjGenKit

@Test func rawValidatorCatchesDanglingMembershipAndMissingProduct() throws {
    let bad = toolDocument.replacingOccurrences(
        of: #""target-membership":["App"]"#, with: #""target-membership":["Missing"]"#)
    expectFailure(containing: "unknown or ambiguous target 'Missing'") {
        _ = try ProjectValidator.validate(data: Data(bad.utf8))
    }
    var project = try XCSchema.Project(jsonRepresentation: Data(toolDocument.utf8))
    project.topLevelReferences.removeLast()
    expectFailure(containing: "Product of App") {
        _ = try ProjectValidator.validate(data: project.jsonRepresentation())
    }
}
@Test func rawValidatorRejectsTargetCyclesAndDuplicateConfigurations() throws {
    let raw = #"""
        {"configurations":["Debug"],"default-configuration":"Debug","files":[],"localizations":{"development":"en","supported":["Base"]},
        "targets":[{"name":"A","id":"AAAAAAAAAAAAAAAAAAAAAAAA","product-type":"tool","dependencies":["B"]},{"name":"B","id":"BBBBBBBBBBBBBBBBBBBBBBBB","product-type":"tool","dependencies":["A"]}]}
        """#
    expectFailure(containing: "cycle") { _ = try ProjectValidator.validate(data: Data(raw.utf8)) }
    let bad = toolDocument.replacingOccurrences(
        of: #""build-phases":["compile-sources"]"#,
        with: #""specialized-configurations":["Debug","Debug"]"#)
    expectFailure(containing: "duplicate specialized configuration names") {
        _ = try ProjectValidator.validate(data: Data(bad.utf8))
    }
}
private func manifest(_ f: Fixture, paths: [[String: Any]]) throws -> InputManifest {
    let object: [String: Any] = [
        "protocolVersion": 1, "schemaVersion": 2, "kind": "project",
        "rootArtifactId": "root", "paths": paths,
        "artifacts": [
            ["id": "root", "kind": "project", "bundlePathId": "bundle", "filePathId": "file"]
        ],
    ]
    return try JSONDecoder().decode(
        InputManifest.self, from: JSONSerialization.data(withJSONObject: object))
}
private func request(_ id: String, _ base: [String: String], _ path: String) -> [String: Any] {
    [
        "id": id, "base": base, "path": path, "expectedKind": "any", "mustExist": false,
        "context": id,
    ]
}
@Test func hostFactsResolveCanonicalPathsAndRootOverride() throws {
    let f = try Fixture()
    try f.directory("Actual")
    try f.symlink("Alias", to: "Actual")
    let requests = [
        request(
            "bundle",
            ["kind": "uri", "uri": f.root.appendingPathComponent("Alias").absoluteString],
            "Example.xcodeproj"),
        request("file", ["kind": "request", "id": "bundle", "location": "self"], "project.xcproj"),
    ]
    let m = try manifest(f, paths: requests)
    let facts = try HostFacts.observe(m)
    #expect(
        facts.paths["bundle"]?.absolutePath
            == f.root.appendingPathComponent("Actual/Example.xcodeproj").path)
    let moved = try HostFacts.observe(
        m, outputDirectory: f.root.appendingPathComponent("Moved.output"))
    #expect(
        moved.paths["file"]?.absolutePath
            == f.root.appendingPathComponent("Moved.output/Example.xcodeproj/project.xcproj").path)
    #expect(
        !FileManager.default.fileExists(
            atPath: f.root.appendingPathComponent("Moved.output").path))
}
@Test func malformedPathGraphFailsBeforeRendering() throws {
    let f = try Fixture()
    let circular = [
        request("bundle", ["kind": "request", "id": "file", "location": "parent"], ""),
        request("file", ["kind": "request", "id": "bundle", "location": "self"], ""),
    ]
    expectFailure(containing: "cycle") { _ = try HostFacts.observe(manifest(f, paths: circular)) }
    let remote = [
        request("bundle", ["kind": "uri", "uri": "https://example.com/Project.pkl"], ""),
        request("file", ["kind": "request", "id": "bundle", "location": "self"], "project.xcproj"),
    ]
    expectFailure(containing: "local file URI") {
        _ = try HostFacts.observe(manifest(f, paths: remote))
    }
    expectFailure(containing: "duplicate") {
        _ = try HostFacts.observe(manifest(f, paths: circular + [circular[0]]))
    }
}
@Test func outputPreflightRejectsFileDirectoryConflicts() throws {
    let f = try Fixture()
    try f.file("Parent", "regular file")
    expectFailure(containing: "Output directory is a file") {
        try validateOutputFile(f.root.appendingPathComponent("Parent/project.xcproj"))
    }
    try f.directory("Folder/project.xcproj")
    expectFailure(containing: "Output file is a directory") {
        try validateOutputFile(f.root.appendingPathComponent("Folder/project.xcproj"))
    }
}

@Test func renderedPlanMustExactlyMatchTheObservedArtifactManifest() throws {
    let f = try Fixture()
    let m = try manifest(
        f,
        paths: [
            request("bundle", ["kind": "uri", "uri": f.root.absoluteString], "Example.xcodeproj"),
            request(
                "file", ["kind": "request", "id": "bundle", "location": "self"], "project.xcproj"),
        ])
    let facts = try HostFacts.observe(m)
    let file: [String: Any] = [
        "artifactId": "root", "kind": "project",
        "destinationUri": facts.paths["file"]!.canonicalUri,
        "text": toolDocument,
    ]
    func data(files: [[String: Any]], targets: Int = 1) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "protocolVersion": 1, "rootArtifactId": "root", "projectCount": 1,
            "targetCount": targets,
            "files": files,
        ])
    }
    let accepted = try GenerationPlan.accept(data(files: [file]), manifest: m, facts: facts)
    #expect(accepted.targetCount == 1)
    expectFailure(containing: "artifacts") {
        _ = try GenerationPlan.accept(data(files: []), manifest: m, facts: facts)
    }
    expectFailure(containing: "artifacts") {
        _ = try GenerationPlan.accept(data(files: [file, file]), manifest: m, facts: facts)
    }
    var wrong = file
    wrong["destinationUri"] = f.root.appendingPathComponent("Other/project.xcproj").absoluteString
    expectFailure(containing: "destination or kind mismatch") {
        _ = try GenerationPlan.accept(data(files: [wrong]), manifest: m, facts: facts)
    }
    expectFailure(containing: "counts") {
        _ = try GenerationPlan.accept(data(files: [file], targets: 99), manifest: m, facts: facts)
    }
    try f.directory("Example.xcodeproj/project.xcproj")
    expectFailure(containing: "Output file is a directory") { try accepted.write() }
}
