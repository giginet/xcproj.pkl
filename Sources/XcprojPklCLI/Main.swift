import ArgumentParser
import Foundation
import XcprojPkl

@main
struct XcprojPklCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "xcproj-pkl",
    abstract: "Generate and validate Xcode JSON projects from Pkl.",
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
    abstract: "Evaluate Pkl, resolve templates, validate, and write project.xcproj.")
  @Argument(help: "Entry Pkl module.") var input: String
  @Option(
    name: .shortAndLong,
    help: "Destination .xcodeproj directory (default: projectDir/name.xcodeproj).") var output:
    String?
  @OptionGroup var evaluation: EvaluationOptions

  mutating func run() throws {
    let source = URL(fileURLWithPath: input).standardizedFileURL
    let generated = try ProjectGenerator().compile(
      json: evaluation.evaluate(source), specDirectory: source.deletingLastPathComponent(),
      output: output.map { URL(fileURLWithPath: $0) }
    )
    let changed = try generated.write()
    print(
      "\(changed ? "Generated" : "Unchanged") \(generated.destination.path) (\(generated.targetCount) targets)"
    )
  }
}

struct Validate: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Validate a Pkl module or an existing .xcodeproj/.xcproj without writing files.")
  @Argument(help: "Pkl module, .xcodeproj directory, or project.xcproj file.") var input: String
  @OptionGroup var evaluation: EvaluationOptions

  mutating func run() throws {
    let source = URL(fileURLWithPath: input).standardizedFileURL
    let count: Int
    switch source.pathExtension {
    case "pkl":
      count = try ProjectGenerator().compile(
        json: evaluation.evaluate(source), specDirectory: source.deletingLastPathComponent()
      ).targetCount
    case "xcodeproj", "xcproj":
      guard evaluation.pkl == nil, evaluation.property.isEmpty else {
        throw ValidationError("--pkl and --property apply only to Pkl input")
      }
      let file =
        source.pathExtension == "xcodeproj"
        ? source.appendingPathComponent("project.xcproj") : source
      count = try ProjectValidator.validate(data: Data(contentsOf: file))
    default: throw ValidationError("Expected a .pkl, .xcodeproj, or .xcproj path")
    }
    print("Valid: \(source.path) (\(count) targets)")
  }
}
