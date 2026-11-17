import ArgumentParser
import Foundation
import XCProjGenKit

@main
struct Xcprojgen: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xcprojgen",
        abstract: "Create, validate, and generate Pkl-based Xcode projects and workspaces.",
        version: ToolDefaults.version,
        subcommands: [Initialize.self, Validate.self, Generate.self, Doctor.self, Skills.self]
    )
}

struct PklOptions: ParsableArguments {
    @Option(help: "Path to the Pkl executable (default: PKL_EXEC or PATH).")
    var pkl: String?

    var tool: PklTool { PklTool(executable: pkl) }
}

struct EvaluationOptions: ParsableArguments {
    @OptionGroup var runtime: PklOptions

    @Option(
        name: [.customShort("p"), .long], help: "Pkl external property, key=value. May be repeated."
    )
    var property: [String] = []

    mutating func validate() throws {
        try GenerationPlan.validateProperties(property)
    }

    func plan(_ source: URL, outputDirectory: URL? = nil) throws -> GenerationPlan {
        try GenerationPlan.resolveAndCompile(
            source: source, tool: runtime.tool, properties: property,
            outputDirectory: outputDirectory)
    }
}

struct OutputOptions: ParsableArguments {
    @Option(
        name: [.customShort("o"), .customLong("output-dir")],
        help:
            "Destination directory. The bundle name and extension come from the Pkl entry. Relative to the current directory. Workspace members keep their project output paths."
    ) var outputDir: String?

    var url: URL? { outputDir.map { URL(fileURLWithPath: $0).standardizedFileURL } }
}

extension InitializationType: ExpressibleByArgument {}

/// Report input mistakes as usage errors.
func entryModule(_ path: URL) throws -> URL {
    do { return try EntryModule.resolve(path) } catch let error as ProjectError {
        throw ValidationError(error.description)
    }
}

struct Initialize: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init", abstract: "Create a Pkl project with an xcproj package dependency.")
    @Argument(
        help:
            "Directory to initialize. Defaults to the current directory. Existing files are never overwritten."
    )
    var dir: String = "."
    @Option(name: .customLong("type"), help: "Scaffold type: project (default) or workspace.")
    var projectType: InitializationType = .project

    mutating func run() throws {
        let destination = URL(fileURLWithPath: dir).standardizedFileURL
        try ProjectInitializer.write(to: destination, type: projectType)
        print("Initialized \(destination.path)")
        print("Package dependency: \(ToolDefaults.packageURI)")
        print(
            "Next: edit Project.pkl, then run 'xcprojgen validate' and 'xcprojgen generate' in the initialized directory."
        )
        print(
            "validate/generate resolve package dependencies; the configured GitHub Release must be accessible."
        )
    }
}

struct Generate: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract:
            "Resolve dependencies and generate the project or workspace defined by a Pkl entry.")
    @Argument(
        help: "Directory containing Project.pkl, or a .pkl file. Defaults to the current directory."
    )
    var path: String = "."
    @OptionGroup var output: OutputOptions
    @OptionGroup var evaluation: EvaluationOptions

    mutating func run() throws {
        let source = try entryModule(URL(fileURLWithPath: path).standardizedFileURL)
        let generated = try evaluation.plan(source, outputDirectory: output.url)
        let changed = try generated.write()
        print(
            "\(changed ? "Generated" : "Unchanged") \(generated.destination.path) (\(generated.projectCount) projects, \(generated.targetCount) generated targets)"
        )
    }
}

struct Validate: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract:
            "Resolve dependencies and validate a Pkl project without writing generated artifacts."
    )
    @Argument(
        help: "Directory containing Project.pkl, or a .pkl file. Defaults to the current directory."
    )
    var path: String = "."
    @OptionGroup var output: OutputOptions
    @OptionGroup var evaluation: EvaluationOptions

    mutating func run() throws {
        let input = URL(fileURLWithPath: path).standardizedFileURL
        let source = try entryModule(input)
        let plan = try evaluation.plan(source, outputDirectory: output.url)
        print(
            "Valid: \(input.path) (\(plan.projectCount) projects, \(plan.targetCount) generated targets)"
        )
    }
}

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check Pkl CLI version and availability of Xcode project tools.")
    @OptionGroup var runtime: PklOptions

    mutating func run() throws {
        let report = Toolchain.check(pkl: runtime.tool)
        for line in report.lines { print(line) }
        if !report.isReady { throw ExitCode.failure }
    }
}
