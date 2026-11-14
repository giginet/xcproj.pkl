import ArgumentParser
import Foundation
import XcprojPkl

@main
struct Xcprojgen: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xcprojgen",
        abstract: "Create, validate, and generate Pkl-based Xcode projects and workspaces.",
        version: ToolDefaults.version,
        subcommands: [Initialize.self, Validate.self, Generate.self, Doctor.self]
    )
}

enum ToolDefaults {
    static let version = "0.1.0"
    static let packageURI =
        "package://github.com/giginet/xcproj.pkl/releases/download/v\(version)/xcproj@\(version)"
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
        // Match Pkl's upward project discovery, including for direct module input.
        var directory = source.resolvingSymlinksInPath().deletingLastPathComponent()
        while true {
            if FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("PklProject").path)
            {
                try runtime.tool.resolveProject(at: directory, properties: property)
                break
            }
            let parent = directory.deletingLastPathComponent()
            if parent == directory { break }
            directory = parent
        }
        return try GenerationPlan.compile(
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

struct EntryOptions: ParsableArguments {
    @Option(help: "Entry .pkl file relative to <dir> (default: Main.pkl).")
    var entry: String?
}

/// The entry's Pkl type determines whether a project or workspace is generated.
func entryModule(_ path: URL, entry: String?) throws -> URL {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory) else {
        throw ValidationError(
            "Input does not exist: \(path.path). Use 'xcprojgen init <dir>' to create a project.")
    }
    if isDirectory.boolValue {
        let name = entry ?? "Main.pkl"
        guard !name.isEmpty, !NSString(string: name).isAbsolutePath else {
            throw ValidationError("--entry must be a relative .pkl file path")
        }
        let module = path.appendingPathComponent(name).standardizedFileURL
        guard module.pathExtension == "pkl" else {
            throw ValidationError("Entry must be a .pkl file: \(name)")
        }
        var entryIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: module.path, isDirectory: &entryIsDirectory),
            !entryIsDirectory.boolValue
        else {
            throw ValidationError(
                "Entry module not found: \(module.path). Use --entry <file.pkl> to select another entry."
            )
        }
        return module
    }
    guard entry == nil else {
        throw ValidationError("--entry requires a directory input")
    }
    guard path.pathExtension == "pkl" else {
        throw ValidationError("Expected a project directory containing Main.pkl or a .pkl module")
    }
    return path
}

struct Initialize: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init", abstract: "Create a Pkl project with an xcproj package dependency.")
    @Argument(help: "Directory to initialize. Existing files are never overwritten.") var dir:
        String
    @Option(name: .customLong("type"), help: "Scaffold type: workspace (default) or project.")
    var projectType: InitializationType = .workspace

    mutating func run() throws {
        let destination = URL(fileURLWithPath: dir).standardizedFileURL
        try ProjectInitializer.write(to: destination, type: projectType)
        print("Initialized \(destination.path)")
        print("Package dependency: \(ToolDefaults.packageURI)")
        print("Next: run 'xcprojgen doctor', then 'xcprojgen generate <dir>'.")
        print(
            "validate/generate resolve package dependencies; the configured GitHub Release must be accessible."
        )
    }
}

struct Generate: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Resolve dependencies and generate the project or workspace defined by Main.pkl.")
    @Argument(help: "Project directory containing Main.pkl, or a .pkl module.") var dir: String
    @OptionGroup var entry: EntryOptions
    @OptionGroup var output: OutputOptions
    @OptionGroup var evaluation: EvaluationOptions

    mutating func run() throws {
        let source = try entryModule(
            URL(fileURLWithPath: dir).standardizedFileURL, entry: entry.entry)
        let generated = try evaluation.plan(source, outputDirectory: output.url)
        let changed = try generated.write()
        print(
            "\(changed ? "Generated" : "Unchanged") \(generated.destination.path) (\(generated.projectCount) projects, \(generated.targetCount) targets)"
        )
    }
}

struct Validate: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract:
            "Resolve dependencies and validate a project or workspace without writing generated artifacts."
    )
    @Argument(help: "Project directory, .pkl module, .xcworkspace, .xcodeproj, or project.xcproj.")
    var dir: String
    @OptionGroup var entry: EntryOptions
    @OptionGroup var output: OutputOptions
    @OptionGroup var evaluation: EvaluationOptions

    mutating func run() throws {
        let input = URL(fileURLWithPath: dir).standardizedFileURL
        let generatedInput = ["xcworkspace", "xcodeproj", "xcproj"].contains(input.pathExtension)
        if generatedInput,
            evaluation.runtime.pkl != nil || !evaluation.property.isEmpty
                || output.outputDir != nil
                || entry.entry != nil
        {
            throw ValidationError(
                "--pkl, --property, --entry, and --output-dir apply only to Pkl input")
        }
        let count: Int
        let projectCount: Int
        switch input.pathExtension {
        case "xcworkspace":
            let result = try WorkspaceValidator.validate(input)
            count = result.targetCount
            projectCount = result.projectCount
        case "xcodeproj", "xcproj":
            projectCount = 1
            let file =
                input.pathExtension == "xcodeproj"
                ? input.appendingPathComponent("project.xcproj") : input
            count = try ProjectValidator.validate(data: Data(contentsOf: file))
        default:
            let plan = try evaluation.plan(
                entryModule(input, entry: entry.entry), outputDirectory: output.url)
            count = plan.targetCount
            projectCount = plan.projectCount
        }
        print("Valid: \(input.path) (\(projectCount) projects, \(count) targets)")
    }
}

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check Pkl CLI installation and supported version.")
    @OptionGroup var runtime: PklOptions

    mutating func run() throws {
        let installation = try runtime.tool.installation()
        print("Pkl executable: \(installation.executable.path)")
        print("Pkl version: \(installation.version)")
        print("Required: >= \(PklTool.minimumVersion)")
        guard installation.isSupported else {
            throw ValidationError(
                "Unsupported Pkl version. Update Pkl: \(PklTool.installationGuide)")
        }
        print("Pkl CLI is ready.")
    }
}
