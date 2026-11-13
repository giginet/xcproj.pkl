import Foundation
import Testing
import XcodeProjectFormat

@testable import XcprojPkl

private let workspaceRepositoryRoot = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func workspaceEntry(_ f: Fixture, directory: String, name: String) throws -> [String: Any] {
  try f.file("\(directory)/Project.pkl")
  try f.file("\(directory)/Sources/Source.swift")
  try f.file("\(directory)/Tests/Tests.swift")
  return [
    "key": name,
    "source": f.root.appendingPathComponent("\(directory)/Project.pkl").absoluteString,
    "project": [
      "schemaVersion": 1, "name": name, "idNamespace": "example.\(name)",
      "targets": [
        "framework": [
          "name": name, "type": "framework", "platform": "macOS",
          "sources": [["path": "Sources"]],
        ],
        "tests": [
          "name": name + "Tests", "type": "bundle.unit-test", "platform": "macOS",
          "sources": [["path": "Tests"]], "dependencies": [["target": "framework"]],
        ],
      ],
    ],
  ]
}

private func workspaceSpec(_ entries: [[String: Any]]) -> [String: Any] {
  ["kind": "workspace", "schemaVersion": 1, "name": "Modular", "projects": entries]
}

@Test func workspacePreservesModuleRootsAndStandaloneProjectOutput() throws {
  let f = try Fixture()
  let a = try workspaceEntry(f, directory: "Modules/A & B", name: "Alpha")
  let b = try workspaceEntry(f, directory: "Modules/Beta", name: "Beta")
  let output = f.root.appendingPathComponent("Generated/Modular.xcworkspace")
  let generated = try WorkspaceGenerator().compile(
    json: f.data(workspaceSpec([b, a])), specDirectory: f.root, output: output)
  #expect(generated.projects.count == 2)
  #expect(generated.targetCount == 4)
  #expect(!FileManager.default.fileExists(atPath: output.path))
  let standalone = try ProjectGenerator().compile(
    json: f.data(a["project"] as! [String: Any]),
    specDirectory: f.root.appendingPathComponent("Modules/A & B"))
  #expect(generated.projects[0].data == standalone.data)
  #expect(generated.projects[0].destination == standalone.destination)
  let xml = String(decoding: generated.data, as: UTF8.self)
  #expect(xml.contains("group:../Modules/A &amp; B/Alpha.xcodeproj"))
  #expect(
    try WorkspaceValidator.projectURLs(data: generated.data, workspace: output).map(\.path)
      == generated.projects.map { $0.destination.path })
  let project = try XCSchema.Project(jsonRepresentation: generated.projects[0].data)
  guard case .folder(let source) = project.topLevelReferences.first else {
    Issue.record("Expected source folder")
    return
  }
  #expect(source.path.path == "Sources")
}

@Test func workspaceOrderingIsDeterministicAndPreservesBundleContents() throws {
  let f = try Fixture()
  let a = try workspaceEntry(f, directory: "Alpha", name: "Alpha")
  let b = try workspaceEntry(f, directory: "Beta", name: "Beta")
  let first = try WorkspaceGenerator().compile(
    json: f.data(workspaceSpec([b, a])), specDirectory: f.root)
  let second = try WorkspaceGenerator().compile(
    json: f.data(workspaceSpec([a, b])), specDirectory: f.root)
  #expect(first.data == second.data)
  #expect(try first.write())
  try f.file("Modular.xcworkspace/xcshareddata/keep.txt", "workspace scheme")
  try f.file("Alpha/Alpha.xcodeproj/xcshareddata/keep.txt", "project scheme")
  #expect(try !second.write())
  #expect(
    try String(
      contentsOf: f.root.appendingPathComponent("Modular.xcworkspace/xcshareddata/keep.txt"),
      encoding: .utf8) == "workspace scheme")
  #expect(
    try String(
      contentsOf: f.root.appendingPathComponent("Alpha/Alpha.xcodeproj/xcshareddata/keep.txt"),
      encoding: .utf8) == "project scheme")
  let result = try WorkspaceValidator.validate(first.destination)
  #expect(result.projectCount == 2)
  #expect(result.targetCount == 4)
}

@Test func invalidWorkspaceMemberDoesNotModifyPreviouslyGeneratedProjects() throws {
  let f = try Fixture()
  let a = try workspaceEntry(f, directory: "Alpha", name: "Alpha")
  let b = try workspaceEntry(f, directory: "Beta", name: "Beta")
  let original = try WorkspaceGenerator().compile(
    json: f.data(workspaceSpec([a])), specDirectory: f.root)
  try original.write()
  try FileManager.default.removeItem(at: f.root.appendingPathComponent("Beta/Sources"))
  expectFailure(containing: "Workspace project 'Beta'") {
    try WorkspaceGenerator().compile(json: f.data(workspaceSpec([a, b])), specDirectory: f.root)
      .write()
  }
  #expect(
    try Data(contentsOf: original.destination.appendingPathComponent("contents.xcworkspacedata"))
      == original.data)
  #expect(
    try Data(contentsOf: original.projects[0].destination.appendingPathComponent("project.xcproj"))
      == original.projects[0].data)
  #expect(
    !FileManager.default.fileExists(
      atPath: f.root.appendingPathComponent("Beta/Beta.xcodeproj").path))
}

@Test(arguments: ["legacy", "directory"])
func workspacePreflightsEveryOutputBeforeWriting(_ conflict: String) throws {
  let f = try Fixture()
  let a = try workspaceEntry(f, directory: "Alpha", name: "Alpha")
  let b = try workspaceEntry(f, directory: "Beta", name: "Beta")
  let generated = try WorkspaceGenerator().compile(
    json: f.data(workspaceSpec([a, b])), specDirectory: f.root)
  if conflict == "legacy" {
    try f.file("Beta/Beta.xcodeproj/project.pbxproj", "existing legacy file")
  } else {
    try f.file("Beta/Beta.xcodeproj", "existing regular file")
  }
  #expect(throws: ProjectError.self) { try generated.write() }
  #expect(!FileManager.default.fileExists(atPath: generated.projects[0].destination.path))
  #expect(!FileManager.default.fileExists(atPath: generated.destination.path))
}

@Test func workspaceRejectsDuplicateModulesKeysAndOutputPaths() throws {
  let f = try Fixture()
  let a = try workspaceEntry(f, directory: "Alpha", name: "Alpha")
  var duplicate = a
  duplicate["key"] = "other"
  expectFailure(containing: "Duplicate project module") {
    _ = try WorkspaceGenerator().compile(
      json: f.data(workspaceSpec([a, duplicate])), specDirectory: f.root)
  }
  expectFailure(containing: "duplicate workspace project key") {
    _ = try WorkspaceGenerator().compile(
      json: f.data(workspaceSpec([a, a])), specDirectory: f.root)
  }
  try f.file("Alpha/Other.pkl")
  duplicate["source"] = f.root.appendingPathComponent("Alpha/Other.pkl").absoluteString
  expectFailure(containing: "Duplicate workspace/project output paths") {
    _ = try WorkspaceGenerator().compile(
      json: f.data(workspaceSpec([a, duplicate])), specDirectory: f.root)
  }
  var nested = workspaceSpec([a])
  nested["workspaceDir"] = "Alpha/Alpha.xcodeproj"
  expectFailure(containing: "Nested workspace/project output paths") {
    _ = try WorkspaceGenerator().compile(json: f.data(nested), specDirectory: f.root)
  }
}

@Test func workspaceRejectsEmptyUnknownAndRemoteInputs() throws {
  let f = try Fixture()
  expectFailure(containing: "at least one project") {
    _ = try GenerationPlan.compile(json: f.data(workspaceSpec([])), specDirectory: f.root)
  }
  var spec = workspaceSpec([])
  spec["kind"] = "unknown"
  expectFailure(containing: "Unknown Pkl document kind") {
    _ = try GenerationPlan.compile(json: f.data(spec), specDirectory: f.root)
  }
  spec = workspaceSpec([])
  spec["project"] = "typo"
  expectFailure(containing: "unknown fields: project") {
    _ = try GenerationPlan.compile(json: f.data(spec), specDirectory: f.root)
  }
  var entry = try workspaceEntry(f, directory: "Alpha", name: "Alpha")
  entry["source"] = "https://example.com/Project.pkl"
  expectFailure(containing: "local file URI") {
    _ = try GenerationPlan.compile(json: f.data(workspaceSpec([entry])), specDirectory: f.root)
  }
}

@Test func existingWorkspaceValidationChecksEveryReferencedProject() throws {
  let f = try Fixture()
  let a = try workspaceEntry(f, directory: "Alpha", name: "Alpha")
  let b = try workspaceEntry(f, directory: "Beta", name: "Beta")
  let generated = try WorkspaceGenerator().compile(
    json: f.data(workspaceSpec([a, b])), specDirectory: f.root)
  try generated.write()
  try Data("{}".utf8).write(
    to: generated.projects[1].destination.appendingPathComponent("project.xcproj"))
  expectFailure(containing: "Beta.xcodeproj") {
    _ = try WorkspaceValidator.validate(generated.destination)
  }
}

@Test func workspaceXMLResolvesNestedGroupsAndContainerLocations() throws {
  let f = try Fixture()
  let xml = #"""
    <Workspace version="1.0">
      <Group location="group:Modules">
        <Group location="group:Alpha"><FileRef location="group:Alpha.xcodeproj"/></Group>
        <FileRef location="container:Beta/Beta.xcodeproj"/>
      </Group>
    </Workspace>
    """#
  let urls = try WorkspaceValidator.projectURLs(
    data: Data(xml.utf8), workspace: f.root.appendingPathComponent("Modular.xcworkspace"))
  #expect(
    urls.map(\.path) == [
      f.root.appendingPathComponent("Modules/Alpha/Alpha.xcodeproj").path,
      f.root.appendingPathComponent("Beta/Beta.xcodeproj").path,
    ])
}

@Test func workspaceXMLRejectsDanglingDuplicateAndUnsupportedReferences() throws {
  let f = try Fixture()
  let duplicate =
    #"<Workspace version="1.0"><FileRef location="group:A.xcodeproj"/><FileRef location="container:A.xcodeproj"/></Workspace>"#
  let bundle = f.root.appendingPathComponent("Modular.xcworkspace")
  expectFailure(containing: "Duplicate workspace project reference") {
    _ = try WorkspaceValidator.projectURLs(data: Data(duplicate.utf8), workspace: bundle)
  }
  let unsupported = #"<Workspace version="1.0"><FileRef location="group:README.md"/></Workspace>"#
  expectFailure(containing: "Only .xcodeproj") {
    _ = try WorkspaceValidator.projectURLs(data: Data(unsupported.utf8), workspace: bundle)
  }
  try f.file(
    "Modular.xcworkspace/contents.xcworkspacedata",
    #"<Workspace version="1.0"><FileRef location="group:Missing.xcodeproj"/></Workspace>"#)
  expectFailure(containing: "Missing.xcodeproj") { _ = try WorkspaceValidator.validate(bundle) }
  #expect(throws: ProjectError.self) {
    try WorkspaceValidator.projectURLs(data: Data("<Workspace>".utf8), workspace: bundle)
  }
}

@Test(
  .enabled(
    if: ProcessInfo.processInfo.environment["PKL_EXEC"] != nil, "Set PKL_EXEC for Pkl integration"))
func workspaceGlobImportsOneHundredProjectModulesWithInheritedTargets() throws {
  let f = try Fixture()
  let workspaceSchema = workspaceRepositoryRoot.appendingPathComponent("Pkl/Workspace.pkl")
    .absoluteString
  let projectTemplate = workspaceRepositoryRoot.appendingPathComponent(
    "Examples/Workspace/Shared/FrameworkProject.pkl"
  ).absoluteString
  for index in 0..<100 {
    let name = String(format: "Feature%03d", index)
    try f.file("Modules/\(name)/Project.pkl", "amends \"\(projectTemplate)\"\nname = \"\(name)\"\n")
    try f.file("Modules/\(name)/Sources/Source.swift")
    try f.file("Modules/\(name)/Tests/Tests.swift")
  }
  try f.file(
    "Workspace.pkl",
    """
    amends "\(workspaceSchema)"
    name = "Large"
    projects = import*("Modules/*/Project.pkl")
    """)
  let data = try PklEvaluator().evaluate(f.root.appendingPathComponent("Workspace.pkl"))
  let plan = try GenerationPlan.compile(json: data, specDirectory: f.root)
  #expect(plan.projectCount == 100)
  #expect(plan.targetCount == 200)
  guard case .workspace(let workspace) = plan else {
    Issue.record("Expected workspace")
    return
  }
  var ids = Set<String>()
  for generated in workspace.projects {
    let project = try XCSchema.Project(jsonRepresentation: generated.data)
    #expect(project.targets.count == 2)
    for target in project.targets {
      #expect(ids.insert(target.commonProperties.objectID.rawValue).inserted)
    }
  }
  #expect(try plan.write())
  let validated = try WorkspaceValidator.validate(plan.destination)
  #expect(validated.projectCount == 100)
  #expect(validated.targetCount == 200)
  #expect(try !plan.write())
}

@Test(
  .enabled(
    if: ProcessInfo.processInfo.environment["PKL_EXEC"] != nil, "Set PKL_EXEC for Pkl integration"))
func workspaceProjectAmendmentRetainsItsSourceModule() throws {
  let f = try Fixture()
  let schema = workspaceRepositoryRoot.appendingPathComponent("Pkl/Workspace.pkl").absoluteString
  let project = workspaceRepositoryRoot.appendingPathComponent(
    "Examples/Workspace/Modules/Catalog/Project.pkl")
  try f.file(
    "Workspace.pkl",
    """
    amends "\(schema)"
    name = "Custom"
    projects {
      ["catalog"] = (import("\(project.absoluteString)")) { name = "CustomCatalog" }
    }
    """)
  let data = try PklEvaluator().evaluate(f.root.appendingPathComponent("Workspace.pkl"))
  let result = try WorkspaceGenerator().compile(json: data, specDirectory: f.root)
  #expect(
    result.projects[0].destination.deletingLastPathComponent().path
      == project.deletingLastPathComponent().path)
  #expect(result.projects[0].destination.lastPathComponent == "CustomCatalog.xcodeproj")
  #expect(result.targetCount == 2)
}
