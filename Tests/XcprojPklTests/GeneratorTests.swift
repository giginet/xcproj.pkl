import Foundation
import Testing
import XcodeProjectFormat

@testable import XcprojPkl

private let validDocument = #"""
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

@Test func existingProjectValidationDoesNotRequirePkl() throws {
    #expect(try ProjectValidator.validate(data: Data(validDocument.utf8)) == 1)
}
@Test func rawValidatorCatchesDanglingMembershipAndMissingProduct() throws {
    let bad = validDocument.replacingOccurrences(
        of: #""target-membership":["App"]"#, with: #""target-membership":["Missing"]"#)
    expectFailure(containing: "unknown or ambiguous target 'Missing'") {
        _ = try ProjectValidator.validate(data: Data(bad.utf8))
    }
    var project = try XCSchema.Project(jsonRepresentation: Data(validDocument.utf8))
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
    let bad = validDocument.replacingOccurrences(
        of: #""build-phases":["compile-sources"]"#,
        with: #""specialized-configurations":["Debug","Debug"]"#)
    expectFailure(containing: "duplicate specialized configuration names") {
        _ = try ProjectValidator.validate(data: Data(bad.utf8))
    }
}
@Test func workspaceXMLResolvesGroupsAndRejectsEntitiesAndDuplicateReferences() throws {
    let f = try Fixture()
    let workspace = f.root.appendingPathComponent("Demo.xcworkspace")
    let xml =
        #"<Workspace version="1.0"><Group location="group:Modules"><FileRef location="group:A.xcodeproj"/></Group><FileRef location="container:B.xcodeproj"/></Workspace>"#
    let urls = try WorkspaceValidator.projectURLs(data: Data(xml.utf8), workspace: workspace)
    #expect(
        urls.map(\.path) == [
            f.root.appendingPathComponent("Modules/A.xcodeproj").path,
            f.root.appendingPathComponent("B.xcodeproj").path,
        ])
    let duplicate =
        #"<Workspace version="1.0"><FileRef location="group:A.xcodeproj"/><FileRef location="container:A.xcodeproj"/></Workspace>"#
    expectFailure(containing: "Duplicate") {
        _ = try WorkspaceValidator.projectURLs(data: Data(duplicate.utf8), workspace: workspace)
    }
    let entity =
        #"<!DOCTYPE Workspace [<!ENTITY x "A.xcodeproj">]><Workspace version="1.0"><FileRef location="group:&x;"/></Workspace>"#
    expectFailure(containing: "entity") {
        _ = try WorkspaceValidator.projectURLs(data: Data(entity.utf8), workspace: workspace)
    }
    try f.file("Demo.xcworkspace/contents.xcworkspacedata", xml)
    expectFailure(containing: "A.xcodeproj") { _ = try WorkspaceValidator.validate(workspace) }
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
            "bundle", ["kind": "uri", "uri": f.root.absoluteString], "Alias/Example.xcodeproj"),
        request("file", ["kind": "request", "id": "bundle", "location": "self"], "project.xcproj"),
    ]
    let m = try manifest(f, paths: requests)
    let facts = try HostFacts.observe(m)
    #expect(
        facts.paths["bundle"]?.absolutePath
            == f.root.appendingPathComponent("Actual/Example.xcodeproj").path)
    let moved = try HostFacts.observe(m, output: f.root.appendingPathComponent("Moved.xcodeproj"))
    #expect(
        moved.paths["file"]?.absolutePath
            == f.root.appendingPathComponent("Moved.xcodeproj/project.xcproj").path)
    #expect(
        !FileManager.default.fileExists(
            atPath: f.root.appendingPathComponent("Moved.xcodeproj").path))
    expectFailure(containing: ".xcodeproj") {
        _ = try HostFacts.observe(m, output: f.root.appendingPathComponent("Bad.txt"))
    }
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
        "text": validDocument,
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
