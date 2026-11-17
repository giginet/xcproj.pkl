import Foundation
import Testing

@testable import XCProjGenKit

struct ProjectInitializerTests {
    @Test(arguments: InitializationType.allCases)
    func scaffoldDependsOnThePublishedPackageAndStaysUnresolved(_ type: InitializationType)
        throws
    {
        let f = try Fixture()
        try ProjectInitializer.write(to: f.url("New Workspace"), type: type)
        #expect(try f.text("New Workspace/PklProject").contains(ToolDefaults.packageURI))
        #expect(
            try f.text("New Workspace/Project.pkl").contains(
                type == .workspace ? "@xcproj/Workspace.pkl" : "@xcproj/Project.pkl"))
        // init only writes the two configuration files; it never resolves dependencies or adds sources.
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: f.url("New Workspace").path)
                .sorted()
                == ["PklProject", "Project.pkl"])
    }

    @Test func existingFilesAreNeverOverwrittenAndNothingIsCreatedOnConflict() throws {
        let f = try Fixture()
        try f.file("Conflict/Project.pkl", "keep me")
        expectFailure(containing: "Refusing to overwrite") {
            try ProjectInitializer.write(to: f.url("Conflict"), type: .workspace)
        }
        #expect(try f.text("Conflict/Project.pkl") == "keep me")
        #expect(!f.exists("Conflict/PklProject"))

        try f.file("Blocked", "a regular file")
        expectFailure(containing: "Expected a directory") {
            try ProjectInitializer.write(to: f.url("Blocked"), type: .workspace)
        }
        #expect(!f.exists("Blocked/PklProject"))
    }
}

struct EntryModuleTests {
    @Test func directoriesSelectProjectAndModulesSelectThemselves() throws {
        let f = try Fixture()
        try f.file("App/Project.pkl")
        let module = try f.file("App/Custom.pkl")
        #expect(try EntryModule.resolve(f.url("App")).path == f.url("App/Project.pkl").path)
        #expect(try EntryModule.resolve(module).path == module.path)
    }

    @Test func otherPklFilesAreNotSelectedAutomatically() throws {
        let f = try Fixture()
        try f.file("Empty/Main.pkl")
        try f.directory("Folder/Project.pkl")
        for directory in ["Empty", "Folder"] {
            expectFailure(containing: "Project.pkl") {
                _ = try EntryModule.resolve(f.url(directory))
            }
        }
        expectFailure(containing: "Input does not exist") {
            _ = try EntryModule.resolve(f.url("Missing"))
        }
    }

    @Test(arguments: ["App.xcodeproj", "App.xcworkspace", "project.xcproj"])
    func generatedArtifactsAreNotAcceptedAsInput(_ path: String) throws {
        let f = try Fixture()
        if path.hasSuffix(".xcproj") { try f.file(path, "{}") } else { try f.directory(path) }
        expectFailure(containing: "Project.pkl") { _ = try EntryModule.resolve(f.url(path)) }
    }

    @Test func pklProjectIsDiscoveredUpwardFromTheCanonicalModuleLocation() throws {
        let f = try Fixture()
        try f.file("Root/PklProject")
        let module = try f.file("Root/Projects/Core/Project.pkl")
        #expect(EntryModule.projectDirectory(for: module)?.path == f.url("Root").path)
        #expect(EntryModule.projectDirectory(for: try f.file("Outside/Project.pkl")) == nil)

        // A symlinked module belongs to the Pkl project of its real location.
        try f.symlink("Outside/Linked.pkl", to: module.path)
        #expect(
            EntryModule.projectDirectory(for: f.url("Outside/Linked.pkl"))?.path
                == f.url("Root").path)
    }
}

struct PklToolTests {
    @Test(arguments: [
        ("Pkl 0.33.0 (macOS 27.2, native)", "0.33.0"), ("Pkl 0.33.1", "0.33.1"),
        ("Pkl 0.34.0-dev+abc123 (Linux)", "0.34.0-dev+abc123"), ("Pkl 1.0.0\n", "1.0.0"),
    ])
    func supportedVersionsAreParsed(_ output: String, _ version: String) throws {
        let parsed = try PklTool.parseVersion(output)
        #expect(parsed.version == version && parsed.isSupported)
    }

    @Test(arguments: ["0.9.0", "0.32.2", "0.33.0-dev"])
    func olderAndPreReleaseMinimumVersionsAreUnsupported(_ version: String) throws {
        let parsed = try PklTool.parseVersion("Pkl \(version) (test)")
        #expect(parsed.version == version && !parsed.isSupported)
    }

    @Test(arguments: ["not-a-version", "Pkl 0.33", "pkl 0.33.0", ""])
    func malformedVersionOutputIsRejected(_ output: String) {
        expectFailure(containing: "Could not parse Pkl version") {
            _ = try PklTool.parseVersion(output)
        }
    }

    @Test func explicitExecutableWinsOverEnvironmentAndPath() throws {
        let f = try Fixture()
        // Stand-ins for pkl that only answer `--version`, each with its own version.
        let option = try f.executable("option/pkl", script: "echo 'Pkl 1.0.1'")
        let variable = try f.executable("variable/pkl", script: "echo 'Pkl 1.0.2'")
        try f.executable("bin/pkl", script: "echo 'Pkl 1.0.3'")
        let environment = ["PKL_EXEC": variable.path, "PATH": "/missing:\(f.url("bin").path)"]
        func version(_ executable: String?, _ environment: [String: String]) throws -> String {
            try PklTool(executable: executable, environment: environment).installation().version
        }
        #expect(try version(option.path, environment) == "1.0.1")
        #expect(try version(nil, environment) == "1.0.2")
        #expect(try version(nil, ["PATH": environment["PATH"]!]) == "1.0.3")
        // A bare name is looked up on PATH, whichever way it was supplied.
        #expect(try version(nil, ["PKL_EXEC": "pkl", "PATH": f.url("bin").path]) == "1.0.3")
    }

    @Test func missingOrNonExecutablePklExplainsHowToInstallIt() throws {
        let f = try Fixture()
        let plain = try f.file("plain/pkl")
        for (executable, environment) in [
            ("/missing/pkl", [:]), (plain.path, [:]), ("pkl", ["PATH": f.url("plain").path]),
        ] {
            let tool = PklTool(executable: executable, environment: environment)
            expectFailure(containing: PklTool.installationGuide) { _ = try tool.installation() }
        }
    }
}

@Suite(.requiresPkl)
struct DependencyResolutionTests {
    private let target = #"targets { ["app"] { name = "App"; type = "tool"; platform = "macOS" } }"#

    @Test func enclosingPklProjectIsResolvedBeforeCompiling() throws {
        let f = try Fixture()
        let package = repository.appendingPathComponent("Pkl/xcproj/PklProject").path
        try f.file(
            "PklProject",
            "amends \"pkl:Project\"\ndependencies { [\"xcproj\"] = import(\(quoted(package))) }\n")
        let source = try f.file(
            "Projects/Core/Project.pkl",
            "amends \"@xcproj/Project.pkl\"\nname = \"Core\"\n\(target)\n")
        // Dependency notation only works once the enclosing project is resolved.
        expectFailure(containing: "xcproj") { _ = try GenerationPlan.compile(source: source) }

        let plan = try GenerationPlan.resolveAndCompile(source: source)
        #expect(plan.projectCount == 1 && plan.targetCount == 1)
        #expect(f.exists("PklProject.deps.json"))
        #expect(plan.destination.path == f.url("Projects/Core/Core.xcodeproj").path)
    }

    @Test func modulesOutsideAPklProjectCompileWithoutResolution() throws {
        let f = try Fixture()
        let plan = try GenerationPlan.resolveAndCompile(source: f.project(target))
        #expect(plan.targetCount == 1)
        #expect(!f.exists("PklProject.deps.json"))
    }

    @Test func invalidPropertiesAreRejectedBeforeResolution() throws {
        let f = try Fixture()
        try f.file("PklProject", "this is not valid Pkl")
        let source = try f.project(target)
        for (property, message) in [
            ("=oops", "Expected --property key=value"),
            ("xcproj.internal.request=bad", "reserved"),
        ] {
            expectFailure(containing: message) {
                _ = try GenerationPlan.resolveAndCompile(source: source, properties: [property])
            }
        }
    }
}

struct ToolchainTests {
    /// A stand-in for pkl that only answers `--version`.
    private func pkl(_ f: Fixture, version: String) throws -> PklTool {
        PklTool(
            executable: try f.executable("pkl", script: "echo \(shellQuoted(version))").path,
            environment: [:])
    }

    @Test func readyToolchainListsEveryExecutable() throws {
        let f = try Fixture()
        let report = Toolchain.check(pkl: try pkl(f, version: "Pkl 0.33.0 (test)")) {
            URL(fileURLWithPath: "/Xcode/usr/bin/\($0.rawValue)")
        }
        #expect(report.isReady)
        let text = report.lines.joined(separator: "\n")
        #expect(text.contains("Pkl executable: \(f.url("pkl").path)"))
        #expect(text.contains("Pkl version: 0.33.0"))
        #expect(text.contains("xcodeproj executable: /Xcode/usr/bin/xcodeproj (ready)"))
        #expect(text.contains("xcprojformatter executable: /Xcode/usr/bin/xcprojformatter (ready)"))
        #expect(report.lines.last == "All tools are ready.")
    }

    @Test(arguments: ["Pkl 0.9.0", "Pkl 0.32.2", "Pkl 0.33.0-dev", "not-a-version"])
    func unsupportedOrMalformedPklVersionFails(_ output: String) throws {
        let f = try Fixture()
        let report = Toolchain.check(pkl: try pkl(f, version: output)) { _ in
            URL(fileURLWithPath: "/tool")
        }
        #expect(!report.isReady)
        #expect(report.lines.joined(separator: "\n").contains(output.replacing("Pkl ", with: "")))
        #expect(!report.lines.contains("All tools are ready."))
    }

    @Test func everyMissingToolIsReportedTogether() {
        let pkl = PklTool(executable: "/missing/pkl", environment: [:])
        let report = Toolchain.check(pkl: pkl) { tool in
            throw ProjectError("xcrun \(tool.rawValue) failed\nInstall Xcode 27.2 or later")
        }
        #expect(!report.isReady)
        let text = report.lines.joined(separator: "\n")
        #expect(text.contains(PklTool.installationGuide))
        #expect(text.contains("xcrun xcodeproj") && text.contains("xcrun xcprojformatter"))
        #expect(text.contains("Install Xcode 27.2 or later"))
    }
}

struct AgentSkillsTests {
    @Test func exportReportsContentChangesAndPreservesOtherFiles() throws {
        let f = try Fixture()
        let output = f.url("Agent Skills")
        let source = repository.appendingPathComponent("Pkl/Skills/xcprojgen").path
        let destination = f.url("Agent Skills/xcprojgen").path

        #expect(try AgentSkills.export(to: output) == .exported)
        #expect(FileManager.default.contentsEqual(atPath: source, andPath: destination))
        #expect(try AgentSkills.export(to: output) == .unchanged)

        try f.file("Agent Skills/xcprojgen/SKILL.md", "outdated skill")
        try f.file("Agent Skills/xcprojgen/notes.md", "mine")
        try f.file("Agent Skills/other/SKILL.md", "another skill")
        #expect(try AgentSkills.export(to: output) == .updated)
        #expect(
            try f.text("Agent Skills/xcprojgen/SKILL.md")
                == String(contentsOfFile: "\(source)/SKILL.md", encoding: .utf8))
        #expect(try f.text("Agent Skills/xcprojgen/notes.md") == "mine")
        #expect(try f.text("Agent Skills/other/SKILL.md") == "another skill")
    }
}
