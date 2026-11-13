import ArgumentParser
import Foundation
import XcprojPkl

@main
struct XcprojPklCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "xcproj-pkl",
    abstract: "Generate and validate Xcode projects and workspaces from Pkl.",
    version: "0.1.0",
    subcommands: [Generate.self, Validate.self]
  )
}

struct EvaluationOptions: ParsableArguments {
  @Option(help: "Path to the Pkl executable (default: PKL_EXEC or PATH).")
  var pkl: String?

  @Option(
    name: [.customShort("p"), .long], help: "Pkl external property, key=value. May be repeated.")
  var property: [String] = []

  func evaluate(_ source: URL) throws -> Data {
    for value in property where !value.contains("=") {
      throw ValidationError("Expected --property key=value, got '\(value)'")
    }
    return try PklEvaluator(executable: pkl).evaluate(source, properties: property)
  }
}

struct Generate: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Evaluate Pkl, resolve templates, and generate a project or workspace.")
  @Argument(help: "Entry Project.pkl or Workspace.pkl module.") var input: String
  @Option(
    name: .shortAndLong,
    help:
      "Destination .xcodeproj or .xcworkspace directory. Workspace members keep their project output paths."
  ) var output: String?
  @OptionGroup var evaluation: EvaluationOptions

  mutating func run() throws {
    let source = URL(fileURLWithPath: input).standardizedFileURL
    let generated = try GenerationPlan.compile(
      json: evaluation.evaluate(source), specDirectory: source.deletingLastPathComponent(),
      output: output.map { URL(fileURLWithPath: $0) }
    )
    let changed = try generated.write()
    print(
      "\(changed ? "Generated" : "Unchanged") \(generated.destination.path) (\(generated.projectCount) projects, \(generated.targetCount) targets)"
    )
  }
}

struct Validate: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Validate Pkl or an existing Xcode project/workspace without writing files.")
  @Argument(help: "Pkl module, .xcworkspace, .xcodeproj, or project.xcproj.") var input: String
  @OptionGroup var evaluation: EvaluationOptions

  mutating func run() throws {
    let source = URL(fileURLWithPath: input).standardizedFileURL
    let count: Int
    let projectCount: Int
    if source.pathExtension != "pkl", evaluation.pkl != nil || !evaluation.property.isEmpty {
      throw ValidationError("--pkl and --property apply only to Pkl input")
    }
    switch source.pathExtension {
    case "pkl":
      let plan = try GenerationPlan.compile(
        json: evaluation.evaluate(source), specDirectory: source.deletingLastPathComponent()
      )
      count = plan.targetCount
      projectCount = plan.projectCount
    case "xcworkspace":
      let result = try WorkspaceValidator.validate(source)
      count = result.targetCount
      projectCount = result.projectCount
    case "xcodeproj", "xcproj":
      projectCount = 1
      let file =
        source.pathExtension == "xcodeproj"
        ? source.appendingPathComponent("project.xcproj") : source
      count = try ProjectValidator.validate(data: Data(contentsOf: file))
    default: throw ValidationError("Expected a .pkl, .xcworkspace, .xcodeproj, or .xcproj path")
    }
    print("Valid: \(source.path) (\(projectCount) projects, \(count) targets)")
  }
}
