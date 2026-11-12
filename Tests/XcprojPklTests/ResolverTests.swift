import Foundation
import Testing
import XcodeProjectFormat

@testable import XcprojPkl

final class Fixture {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "xcproj-pkl-test-\(UUID().uuidString)")
  init() throws {
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true)
  }
  deinit { try? FileManager.default.removeItem(at: root) }
  func file(_ path: String, _ text: String = "") throws {
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
  }
  func spec(targets: [String: Any] = ["App": ["type": "tool", "platform": "macOS"]]) -> [String:
    Any]
  {
    ["schemaVersion": 1, "name": "Example", "idNamespace": "com.example", "targets": targets]
  }
  func data(_ spec: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: spec)
  }
  func resolve(_ spec: [String: Any]) throws -> ResolvedProject {
    try Resolver(
      project: JSONDecoder().decode(ProjectSpec.self, from: data(spec)), specDirectory: root
    ).resolve()
  }
  func compile(_ spec: [String: Any], output: URL? = nil) throws -> GeneratedProject {
    try ProjectGenerator().compile(json: data(spec), specDirectory: root, output: output)
  }
}

func expectFailure(containing expected: String, _ operation: () throws -> Void) {
  do {
    try operation()
    Issue.record("Expected an error containing '\(expected)'")
  } catch { #expect(String(describing: error).contains(expected)) }
}

@Test func templatesComposeInOrderAndTargetsOverrideThem() throws {
  let f = try Fixture()
  var spec = f.spec(targets: [
    "App": ["templates": ["Child", "Second"], "settings": ["base": ["WINNER": "target"]]]
  ])
  spec["targetTemplates"] = [
    "Base": [
      "type": "tool", "platform": "macOS", "settings": ["base": ["BASE": "yes", "WINNER": "base"]],
    ],
    "Child": ["templates": ["Base"], "settings": ["base": ["CHILD": "yes", "WINNER": "child"]]],
    "Second": ["settings": ["base": ["SECOND": "yes", "WINNER": "second"]]],
  ]
  let target = try #require(f.resolve(spec).targets.first)
  #expect(target.settings["BASE"] == .string("yes"))
  #expect(target.settings["CHILD"] == .string("yes"))
  #expect(target.settings["SECOND"] == .string("yes"))
  #expect(target.settings["WINNER"] == .string("target"))
}

@Test func settingsGroupsBaseAndConfigsHaveExplicitPrecedence() throws {
  let f = try Fixture()
  var spec = f.spec(targets: [
    "App": [
      "type": "tool", "platform": "macOS",
      "settings": [
        "groups": ["one", "two"], "base": ["VALUE": "base"],
        "configs": ["Debug": ["groups": ["debug"], "base": ["VALUE": "debug-base"]]],
      ],
    ]
  ])
  spec["settingGroups"] = [
    "one": ["base": ["VALUE": "one", "FLAGS": ["a"], "KEEP": "yes"]],
    "two": ["groups": ["one"], "base": ["VALUE": "two", "FLAGS": ["b"]]],
    "debug": ["base": ["VALUE": "debug-group", "DEBUG_ONLY": "yes"]],
  ]
  let values = try f.resolve(spec).targets[0].settings
  #expect(values["VALUE"] == .string("base"))
  #expect(values["VALUE[config=Debug]"] == .string("debug-base"))
  #expect(values["FLAGS"] == .array(["b"]))
  #expect(values["KEEP"] == .string("yes"))
  #expect(values["DEBUG_ONLY[config=Debug]"] == .string("yes"))
  #expect(values["DEBUG_ONLY[config=Release]"] == nil)
}

@Test func userBaseSettingsOverrideConfigurationPresets() throws {
  let f = try Fixture()
  let spec = f.spec(targets: [
    "App": [
      "type": "tool", "platform": "macOS",
      "settings": ["base": ["SWIFT_OPTIMIZATION_LEVEL": "-Osize"]],
    ]
  ])
  let settings = try f.resolve(spec).targets[0].settings
  #expect(settings["SWIFT_OPTIMIZATION_LEVEL"] == .string("-Osize"))
  #expect(settings["SWIFT_OPTIMIZATION_LEVEL[config=Debug]"] == nil)
}

@Test func templateAttributesExpandAfterCompositionWithoutChangingXcodeMacros() throws {
  let f = try Fixture()
  try f.file("Sources/Renamed/main.swift")
  var spec = f.spec(targets: [
    "stable-key": [
      "name": "Renamed", "templates": ["Base"], "templateAttributes": ["suffix": "demo"],
    ]
  ])
  spec["targetTemplates"] = [
    "Base": [
      "type": "tool", "platform": "macOS", "sources": [["path": "Sources/${target_name}"]],
      "settings": [
        "base": ["VALUE": "${suffix}.${target_name}", "FLAGS": ["$(inherited)", "${suffix}"]]
      ],
    ]
  ]
  let target = try f.resolve(spec).targets[0]
  #expect(target.settings["VALUE"] == .string("demo.Renamed"))
  #expect(target.settings["FLAGS"] == .array(["$(inherited)", "demo"]))
  #expect(target.spec.sources[0].path == "Sources/Renamed")
}

@Test func targetAndProductIDsSurviveRenamingAndAreDistinct() throws {
  let f = try Fixture()
  let first = try f.resolve(f.spec()).targets[0]
  let second = try f.resolve(
    f.spec(targets: ["App": ["name": "NewName", "platform": "macOS", "type": "tool"]])
  ).targets[0]
  #expect(first.id == second.id)
  #expect(first.productId == second.productId)
  #expect(first.id != first.productId)
}

@Test func explicitlySuppliedIDsArePreservedExactly() throws {
  let f = try Fixture()
  let explicit = "abcdef012345abcdef012345"
  let target = try f.resolve(
    f.spec(targets: ["App": ["type": "tool", "platform": "macOS", "id": explicit]])
  ).targets[0]
  #expect(target.id == explicit)
}

@Test func templateCyclesAndUnknownReferencesFailEvenWhenUnused() throws {
  let f = try Fixture()
  var cyclic = f.spec()
  cyclic["targetTemplates"] = ["A": ["templates": ["B"]], "B": ["templates": ["A"]]]
  expectFailure(containing: "A → B → A") { _ = try f.resolve(cyclic) }
  let missing = f.spec(targets: ["App": ["templates": ["Missing"]]])
  expectFailure(containing: "Unknown target template: Missing") { _ = try f.resolve(missing) }
  var unused = f.spec()
  unused["targetTemplates"] = ["Unused": ["settings": ["groups": ["Missing"]]]]
  expectFailure(containing: "Unknown setting group: Missing") { _ = try f.resolve(unused) }
}

@Test func settingGroupCyclesAreReportedWithTheirChain() throws {
  let f = try Fixture()
  var spec = f.spec()
  spec["settingGroups"] = ["A": ["groups": ["B"]], "B": ["configs": ["Debug": ["groups": ["A"]]]]]
  expectFailure(containing: "A → B → A") { _ = try f.resolve(spec) }
}

@Test func configurationTyposAreRejected() throws {
  let f = try Fixture()
  var spec = f.spec()
  spec["settings"] = ["configs": ["debug": ["base": ["X": "Y"]]]]
  expectFailure(containing: "Unknown build configuration") { _ = try f.resolve(spec) }
}

@Test func invalidSettingTypesAndUnknownFieldsAreRejected() throws {
  let f = try Fixture()
  var spec = f.spec()
  spec["settings"] = ["base": ["SWIFT_VERSION": 6]]
  #expect(throws: (any Error).self) { try f.resolve(spec) }
  spec = f.spec()
  spec["targetTemplate"] = [:] as [String: String]
  expectFailure(containing: "unknown fields: targetTemplate") { _ = try f.resolve(spec) }
}

@Test func unknownAttributesMissingSourcesAndOverlappingRootsFail() throws {
  let f = try Fixture()
  let badAttribute = f.spec(targets: [
    "App": ["type": "tool", "platform": "macOS", "settings": ["base": ["X": "${missing}"]]]
  ])
  expectFailure(containing: "unknown template attribute") { _ = try f.resolve(badAttribute) }
  let missing = f.spec(targets: [
    "App": ["type": "tool", "platform": "macOS", "sources": [["path": "Missing"]]]
  ])
  expectFailure(containing: "directory does not exist") { _ = try f.resolve(missing) }
  try f.file("Sources/Nested/main.swift")
  let overlap = f.spec(targets: [
    "App": [
      "type": "tool", "platform": "macOS",
      "sources": [["path": "Sources"], ["path": "Sources/Nested"]],
    ]
  ])
  expectFailure(containing: "overlapping source roots") { _ = try f.resolve(overlap) }
}

@Test func duplicateTargetNamesAndIDsFail() throws {
  let f = try Fixture()
  let names = f.spec(targets: [
    "A": ["type": "tool", "platform": "macOS", "name": "Same"],
    "B": ["type": "tool", "platform": "macOS", "name": "Same"],
  ])
  expectFailure(containing: "Duplicate target name") { _ = try f.resolve(names) }
  let ids = f.spec(targets: [
    "App": [
      "type": "tool", "platform": "macOS", "id": String(repeating: "A", count: 24),
      "productId": String(repeating: "A", count: 24),
    ]
  ])
  expectFailure(containing: "Duplicate object ID") { _ = try f.resolve(ids) }
}

@Test func dependenciesAreValidatedAndCyclesFail() throws {
  let f = try Fixture()
  let missing = f.spec(targets: [
    "A": [
      "type": "tool", "platform": "macOS", "dependencies": [["target": "Missing", "link": false]],
    ]
  ])
  expectFailure(containing: "unknown dependency 'Missing'") { _ = try f.resolve(missing) }
  let cyclic = f.spec(targets: [
    "A": ["type": "tool", "platform": "macOS", "dependencies": [["target": "B", "link": false]]],
    "B": ["type": "tool", "platform": "macOS", "dependencies": [["target": "A", "link": false]]],
  ])
  expectFailure(containing: "Target dependency cycle") { _ = try f.resolve(cyclic) }
}
