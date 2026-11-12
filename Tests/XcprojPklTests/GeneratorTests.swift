import Foundation
import Testing
import XcodeProjectFormat

@testable import XcprojPkl

@Test(arguments: ["bundle.unit-test", "unit-test-bundle"])
func unitTestProductTypeUsesXcodesIdentifier(_ type: String) throws {
  let f = try Fixture()
  let spec = f.spec(targets: ["Tests": ["type": type, "platform": "iOS"]])
  let project = try XCSchema.Project(jsonRepresentation: f.compile(spec).data)
  #expect(
    project.targets[0].commonProperties.productTypeID?.rawValue
      == "com.apple.product-type.bundle.unit-test")
}

@Test func generationIsDeterministicAndWritesOnlyWhenChanged() throws {
  let f = try Fixture()
  let first = try f.compile(f.spec())
  let second = try f.compile(f.spec())
  #expect(first.data == second.data)
  #expect(!FileManager.default.fileExists(atPath: first.destination.path))
  #expect(try first.write())
  try f.file("Example.xcodeproj/xcshareddata/keep.txt", "preserve me")
  #expect(try !second.write())
  #expect(
    try String(
      contentsOf: first.destination.appendingPathComponent("xcshareddata/keep.txt"), encoding: .utf8
    ) == "preserve me")
}

@Test func validationFailureLeavesExistingProjectUntouched() throws {
  let f = try Fixture()
  let generated = try f.compile(f.spec())
  try generated.write()
  var invalid = f.spec()
  invalid["defaultConfiguration"] = "Missing"
  expectFailure(containing: "defaultConfiguration") { try f.compile(invalid).write() }
  #expect(
    try Data(contentsOf: generated.destination.appendingPathComponent("project.xcproj"))
      == generated.data)
}

@Test func legacyProjectsAreNotOverwritten() throws {
  let f = try Fixture()
  try f.file("Example.xcodeproj/project.pbxproj", "existing")
  let generated = try f.compile(f.spec())
  expectFailure(containing: "legacy project") { try generated.write() }
  #expect(
    !FileManager.default.fileExists(
      atPath: generated.destination.appendingPathComponent("project.xcproj").path))
}

@Test func sourcePathsAreRebasedWhenOutputMoves() throws {
  let f = try Fixture()
  let spec = f.spec(targets: [
    "App": ["type": "tool", "platform": "macOS", "sources": [["path": "Sources"]]]
  ])
  let result = try f.compile(spec, output: f.root.appendingPathComponent("Build/Example.xcodeproj"))
  let project = try XCSchema.Project(jsonRepresentation: result.data)
  guard case .folder(let folder) = project.topLevelReferences[0] else {
    Issue.record("Expected synchronized folder")
    return
  }
  #expect(folder.path.base == .project)
  #expect(folder.path.path == "../Sources")
}

@Test func sharedSourcesHaveOneReferenceAndTargetSpecificExclusions() throws {
  let f = try Fixture()
  try f.file("Sources/excluded.swift")
  let spec = f.spec(targets: [
    "A": [
      "type": "tool", "platform": "macOS",
      "sources": [["path": "Sources", "excludes": ["excluded.swift"]]],
    ],
    "B": ["type": "tool", "platform": "macOS", "sources": [["path": "Sources"]]],
  ])
  let project = try XCSchema.Project(jsonRepresentation: f.compile(spec).data)
  guard case .folder(let folder) = project.topLevelReferences[0] else {
    Issue.record("Expected folder")
    return
  }
  #expect(folder.targets.map(\.targetName).sorted() == ["A", "B"])
  #expect(folder.membershipExceptions.count == 1)
  guard case .target(let exception) = folder.membershipExceptions[0] else {
    Issue.record("Expected target exception")
    return
  }
  #expect(exception.target.targetName == "A")
  #expect(exception.commonProperties.sense == .exclusions)
}

@Test func frameworkDependencyProducesLinkAndEmbedMemberships() throws {
  let f = try Fixture()
  let spec = f.spec(targets: [
    "App": [
      "type": "application", "platform": "iOS",
      "dependencies": [["target": "Core", "embed": true]],
    ],
    "Core": ["type": "framework", "platform": "iOS"],
  ])
  let project = try XCSchema.Project(jsonRepresentation: f.compile(spec).data)
  let app = try #require(project.targets.first { $0.name == "App" })
  #expect(app.commonProperties.dependencies.count == 1)
  #expect(app.commonProperties.buildPhases.contains { $0.kind == .copy })
  guard case .group(let products) = project.topLevelReferences.last else {
    Issue.record("Expected Products")
    return
  }
  let core = try #require(
    products.children.compactMap { reference -> XCSchema.FileReference? in
      if case .fileReference(let file) = reference, file.path.path == "Core.framework" {
        return file
      }
      return nil
    }.first)
  #expect(core.buildFiles.count == 2)
  #expect(core.buildFiles.contains { $0.properties.attributes.codeSignOnCopy })
}

@Test func xcconfigReferencesUseStableIDsAndAreValidated() throws {
  let f = try Fixture()
  try f.file("Config/Debug.xcconfig")
  var spec = f.spec()
  spec["configFiles"] = ["Debug": "Config/Debug.xcconfig"]
  let result = try f.compile(spec)
  let project = try XCSchema.Project(jsonRepresentation: result.data)
  let config = try #require(project.configurations.first { $0.name.rawValue == "Debug" })
  guard case .objectID = config.file?.anchor else {
    Issue.record("Expected ID anchor")
    return
  }
  #expect(try ProjectValidator.validate(data: result.data) == 1)
  spec["configFiles"] = ["Debug": "Missing.xcconfig"]
  expectFailure(containing: "file does not exist") { _ = try f.compile(spec) }
}

@Test func rawProjectValidatorCatchesDanglingMembershipThatFormatterAccepts() throws {
  let f = try Fixture()
  let spec = f.spec(targets: [
    "App": ["type": "tool", "platform": "macOS", "sources": [["path": "Sources"]]]
  ])
  var project = try XCSchema.Project(jsonRepresentation: f.compile(spec).data)
  guard case .folder(var folder) = project.topLevelReferences[0] else {
    Issue.record("Expected folder")
    return
  }
  folder.targets.insert(.init(targetName: "Missing"))
  project.topLevelReferences[0] = .folder(folder)
  let malformed = try project.jsonRepresentation()
  expectFailure(containing: "unknown or ambiguous target 'Missing'") {
    _ = try ProjectValidator.validate(data: malformed)
  }
}

@Test func rawProjectValidatorCatchesMissingProductsAndPhases() throws {
  let f = try Fixture()
  try f.file("main.swift")
  let spec = f.spec(targets: [
    "App": [
      "type": "tool", "platform": "macOS", "sources": [["kind": "file", "path": "main.swift"]],
    ]
  ])
  var project = try XCSchema.Project(jsonRepresentation: f.compile(spec).data)
  var properties = project.targets[0].commonProperties
  properties.buildPhases.removeAll { $0.kind == .sources }
  project.targets[0] = .native(properties)
  expectFailure(containing: "Unknown or ambiguous build phase") {
    _ = try ProjectValidator.validate(data: project.jsonRepresentation())
  }
  project.topLevelReferences.removeLast()
  expectFailure(containing: "Product of App") {
    _ = try ProjectValidator.validate(data: project.jsonRepresentation())
  }
}

@Test func rawProjectValidatorRejectsDuplicateNamesWithoutReferences() throws {
  let json = #"""
    {
      "configurations": ["Debug"], "default-configuration": "Debug",
      "files": [], "localizations": { "development": "en", "supported": ["Base"] },
      "targets": [
        { "name": "A", "id": "AAAAAAAAAAAAAAAAAAAAAAAA", "product-type": "tool" },
        { "name": "A", "id": "BBBBBBBBBBBBBBBBBBBBBBBB", "product-type": "tool" }
      ]
    }
    """#
  expectFailure(containing: "Target names must be unique") {
    _ = try ProjectValidator.validate(data: Data(json.utf8))
  }
}

@Test func rawProjectValidatorRejectsDuplicateTargetConfigurations() throws {
  let json = #"""
    {
      "configurations": ["Debug"], "default-configuration": "Debug",
      "files": [], "localizations": { "development": "en", "supported": ["Base"] },
      "targets": [{
        "name": "App", "id": "AAAAAAAAAAAAAAAAAAAAAAAA", "product-type": "tool",
        "specialized-configurations": ["Debug", "Debug"]
      }]
    }
    """#
  expectFailure(containing: "duplicate specialized configuration names") {
    _ = try ProjectValidator.validate(data: Data(json.utf8))
  }
}
