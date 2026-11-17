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
            try f.text("New Workspace/Main.pkl").contains(
                type == .workspace ? "@xcproj/Workspace.pkl" : "@xcproj/Project.pkl"))
        // Dependencies are resolved by validate/generate, never by init.
        #expect(!f.exists("New Workspace/PklProject.deps.json"))
        #expect(f.exists("New Workspace/Projects/Core/Project.pkl") == (type == .workspace))
    }

    @Test func existingFilesAreNeverOverwrittenAndNothingIsCreatedOnConflict() throws {
        let f = try Fixture()
        try f.file("Conflict/Main.pkl", "keep me")
        expectFailure(containing: "Refusing to overwrite") {
            try ProjectInitializer.write(to: f.url("Conflict"), type: .workspace)
        }
        #expect(try f.text("Conflict/Main.pkl") == "keep me")
        #expect(!f.exists("Conflict/PklProject"))

        try f.file("Blocked/Projects", "a regular file")
        expectFailure(containing: "Expected a directory") {
            try ProjectInitializer.write(to: f.url("Blocked"), type: .workspace)
        }
        #expect(!f.exists("Blocked/PklProject"))
    }
}

struct EntryModuleTests {
    @Test func directoriesSelectMainAndModulesSelectThemselves() throws {
        let f = try Fixture()
        try f.file("App/Main.pkl")
        let module = try f.file("App/Projects/Core/Project.pkl")
        #expect(try EntryModule.resolve(f.url("App")).path == f.url("App/Main.pkl").path)
        #expect(try EntryModule.resolve(module).path == module.path)
    }

    @Test func otherPklFilesAreNotSelectedAutomatically() throws {
        let f = try Fixture()
        try f.file("Empty/Workspace.pkl")
        try f.directory("Folder/Main.pkl")
        for directory in ["Empty", "Folder"] {
            expectFailure(containing: "Main.pkl") {
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
        expectFailure(containing: "Main.pkl") { _ = try EntryModule.resolve(f.url(path)) }
    }

    @Test func pklProjectIsDiscoveredUpwardFromTheCanonicalModuleLocation() throws {
        let f = try Fixture()
        try f.file("Root/PklProject")
        let module = try f.file("Root/Projects/Core/Project.pkl")
        #expect(EntryModule.projectDirectory(for: module)?.path == f.url("Root").path)
        #expect(EntryModule.projectDirectory(for: try f.file("Outside/Main.pkl")) == nil)

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
        let option = try f.executable("option/pkl")
        let variable = try f.executable("variable/pkl")
        let onPath = try f.executable("bin/pkl")
        let version: PklTool.Runner = { _, _ in Data("Pkl 0.33.0".utf8) }
        let environment = ["PKL_EXEC": variable.path, "PATH": "/missing:\(f.url("bin").path)"]
        func located(_ executable: String?, _ environment: [String: String]) throws -> String {
            try PklTool(executable: executable, environment: environment, runner: version)
                .installation().executable.path
        }
        #expect(try located(option.path, environment) == option.path)
        #expect(try located(nil, environment) == variable.path)
        #expect(try located(nil, ["PATH": environment["PATH"]!]) == onPath.path)
        // A bare name is looked up on PATH, whichever way it was supplied.
        #expect(try located(nil, ["PKL_EXEC": "pkl", "PATH": f.url("bin").path]) == onPath.path)
    }

    @Test func missingOrNonExecutablePklExplainsHowToInstallIt() throws {
        let f = try Fixture()
        let plain = try f.file("plain/pkl")
        let never: PklTool.Runner = { _, _ in
            Issue.record("pkl must not run")
            return Data()
        }
        for (executable, environment) in [
            ("/missing/pkl", [:]), (plain.path, [:]), ("pkl", ["PATH": f.url("plain").path]),
        ] {
            let tool = PklTool(executable: executable, environment: environment, runner: never)
            expectFailure(containing: PklTool.installationGuide) { _ = try tool.installation() }
        }
    }

    @Test func evaluationRunsInTheModuleDirectoryWithJSONOutput() throws {
        let f = try Fixture()
        let source = try f.file("Config/Main.pkl")
        let pkl = PklStub { _ in Data("{}".utf8) }
        _ = try pkl.tool.evaluate(source, properties: ["a=b", "c=d"], expression: "value")
        let call = try #require(pkl.calls.first)
        #expect(call.command == "eval" && call.source == source.path)
        #expect(call.properties == ["a=b", "c=d"])
        #expect(call.workingDirectory?.path == f.url("Config").path)
        for flags in [["--format", "json"], ["--expression", "value"]] {
            let index = try #require(call.arguments.firstIndex(of: flags[0]))
            #expect(call.arguments[index + 1] == flags[1])
        }
    }
}

struct ToolchainTests {
    private func pkl(_ f: Fixture, version: String) throws -> PklTool {
        PklTool(executable: try f.executable("pkl").path, environment: [:]) { _, _ in
            Data(version.utf8)
        }
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
        let pkl = PklTool(executable: "/missing/pkl", environment: [:]) { _, _ in Data() }
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
