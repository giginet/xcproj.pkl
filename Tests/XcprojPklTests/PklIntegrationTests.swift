import Foundation
import Testing

@testable import XcprojPkl

private let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  .deletingLastPathComponent().deletingLastPathComponent()

@Test(
  .enabled(
    if: ProcessInfo.processInfo.environment["PKL_EXEC"] != nil,
    "Set PKL_EXEC to run the real Pkl integration test"))
func evaluatesImportedSettingsAndTemplatesFromRealPkl() throws {
  let source = repositoryRoot.appendingPathComponent("Examples/Tool/Project.pkl")
  let json = try PklEvaluator().evaluate(source)
  let project = try JSONDecoder().decode(ProjectSpec.self, from: json)
  let resolved = try Resolver(project: project, specDirectory: source.deletingLastPathComponent())
    .resolve()
  #expect(resolved.targets[0].name == "Hello")
  #expect(resolved.targets[0].settings["SWIFT_TREAT_WARNINGS_AS_ERRORS"] == .string("YES"))
  #expect(resolved.targets[0].settings["OTHER_SWIFT_FLAGS"] == .array(["$(inherited)", "-DTEAM"]))
  #expect(resolved.settings["OTHER_SWIFT_FLAGS"] == .array(["-DPROJECT"]))
  #expect(
    try ProjectGenerator().compile(json: json, specDirectory: source.deletingLastPathComponent())
      .targetCount == 1)
}

@Test(
  .enabled(
    if: ProcessInfo.processInfo.environment["PKL_EXEC"] != nil,
    "Set PKL_EXEC to run the real Pkl integration test"))
func pklTypeErrorsKeepSourceDiagnostics() throws {
  let f = try Fixture()
  let schema = repositoryRoot.appendingPathComponent("Pkl/Project.pkl").absoluteString
  try f.file(
    "Invalid.pkl",
    """
    amends "\(schema)"
    name = "Invalid"
    settings { base { ["SWIFT_VERSION"] = 6 } }
    """)
  expectFailure(containing: "Invalid.pkl") {
    _ = try PklEvaluator().evaluate(f.root.appendingPathComponent("Invalid.pkl"))
  }
}
