import Foundation
import Testing

@testable import XCProjGenKit

private struct CLIResult {
    let status: Int32
    let text: String
}

private func cli(
    _ arguments: [String], fixture: Fixture, environment: [String: String] = [:]
) throws -> CLIResult {
    let log = try fixture.file("cli-\(UUID()).log")
    let handle = try FileHandle(forWritingTo: log)
    defer { try? handle.close() }
    let process = Process()
    process.executableURL = repository.appendingPathComponent(".build/debug/xcprojgen")
        .resolvingSymlinksInPath()
    process.arguments = arguments
    process.currentDirectoryURL = fixture.root
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
    process.standardOutput = handle
    process.standardError = handle
    try process.run()
    process.waitUntilExit()
    return CLIResult(
        status: process.terminationStatus, text: try String(contentsOf: log, encoding: .utf8))
}

private func executable(_ path: URL) throws {
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
}

struct CLITests {
    @Test(arguments: ["App.xcodeproj", "App.xcworkspace", "project.xcproj"])
    func validateRequiresPklInput(_ path: String) throws {
        let f = try Fixture()
        if path.hasSuffix(".xcproj") {
            try f.file(path, "{}")
        } else {
            try f.directory(path)
        }
        let result = try cli(
            ["validate", path], fixture: f, environment: ["PKL_EXEC": "/missing/pkl"])
        #expect(result.status != 0 && result.text.contains("Main.pkl"), "\(result.text)")
    }

    @Test func initIsOfflineAndRefusesOverwriteBeforeCreatingFiles() throws {
        let f = try Fixture()
        let created = try cli(
            ["init", "New Workspace"], fixture: f, environment: ["PKL_EXEC": "/missing/pkl"])
        #expect(created.status == 0, "\(created.text)")
        let root = f.root.appendingPathComponent("New Workspace")
        let manifest = try String(
            contentsOf: root.appendingPathComponent("PklProject"), encoding: .utf8)
        #expect(
            manifest.contains(
                "package://github.com/giginet/xcproj.pkl/releases/download/0.1.0/xcproj@0.1.0"
            ))
        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent("PklProject.deps.json").path))
        try Data("keep me".utf8).write(to: root.appendingPathComponent("Main.pkl"))
        let again = try cli(["init", root.path], fixture: f)
        #expect(again.status != 0 && again.text.contains("Refusing to overwrite"))
        #expect(
            try String(contentsOf: root.appendingPathComponent("Main.pkl"), encoding: .utf8)
                == "keep me")

        try f.file("Conflict/Main.pkl", "existing")
        let collision = try cli(["init", "Conflict"], fixture: f)
        #expect(collision.status != 0)
        #expect(
            !FileManager.default.fileExists(
                atPath: f.root.appendingPathComponent("Conflict/PklProject").path))
    }

    @Test func doctorExplainsMissingPklAndHonorsExecutablePrecedence() throws {
        let f = try Fixture()
        let missing = try cli(
            ["doctor"], fixture: f,
            environment: [
                "PKL_EXEC": "/missing/pkl",
                "DEVELOPER_DIR": f.root.appendingPathComponent("MissingXcode.app").path,
            ])
        #expect(missing.status != 0)
        #expect(missing.text.contains(PklTool.installationGuide))
        #expect(missing.text.contains("xcrun xcodeproj"))
        #expect(missing.text.contains("xcrun xcprojformatter"))
        #expect(missing.text.contains("Install Xcode 27.2 or later"))
        #expect(missing.text.contains("DEVELOPER_DIR"))
        let fake = try f.file("fake-pkl", "#!/bin/sh\nprintf 'Pkl 0.33.0 (test)\\n'\n")
        try executable(fake)
        let installed = try cli(
            ["doctor", "--pkl", fake.path], fixture: f, environment: ["PKL_EXEC": "/missing/pkl"])
        #expect(installed.status == 0, "\(installed.text)")
        #expect(installed.text.contains(fake.path) && installed.text.contains("0.33.0"))
        #expect(installed.text.contains("xcodeproj executable:"))
        #expect(installed.text.contains("xcprojformatter executable:"))
        let fromPath = try cli(
            ["doctor"], fixture: f,
            environment: ["PKL_EXEC": "fake-pkl", "PATH": "\(f.root.path):/usr/bin:/bin"])
        #expect(fromPath.status == 0, "\(fromPath.text)")
    }

    @Test(arguments: ["0.9.0", "0.32.2", "0.33.0-dev", "not-a-version"])
    func doctorRejectsUnsupportedOrMalformedVersion(_ version: String) throws {
        let f = try Fixture()
        let fake = try f.file("fake-pkl", "#!/bin/sh\nprintf 'Pkl \(version) (test)\\n'\n")
        try executable(fake)
        let result = try cli(["doctor", "--pkl", fake.path], fixture: f)
        #expect(result.status != 0)
        #expect(result.text.contains(version))
    }

    @Test func invalidInputsAndPropertiesDoNotInvokePkl() throws {
        let f = try Fixture()
        try f.directory("Empty")
        try f.file("Empty/Workspace.pkl", "This file must not be selected automatically")
        let missing = try cli(["generate", "Empty"], fixture: f)
        #expect(missing.status != 0 && missing.text.contains("Main.pkl"))
        let property = try cli(
            ["generate", "Empty", "--property", "=oops"], fixture: f)
        #expect(property.status != 0 && property.text.contains("Expected --property key=value"))
        let reserved = try cli(
            ["generate", "Empty", "--property", "xcproj.internal.request=bad"], fixture: f)
        #expect(reserved.status != 0 && reserved.text.contains("reserved"))
        let absolute = try cli(
            ["generate", "Empty", "--entry", "/tmp/Project.pkl"], fixture: f)
        #expect(absolute.status != 0 && absolute.text.contains("relative .pkl"))
        let doubleEntry = try cli(
            ["generate", "Empty/Workspace.pkl", "--entry", "Main.pkl"], fixture: f)
        #expect(doubleEntry.status != 0 && doubleEntry.text.contains("requires a directory"))
        let invalidType = try cli(["init", "Bad", "--type", "unknown"], fixture: f)
        #expect(invalidType.status != 0)
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("Bad").path))
    }
}

@Suite(.enabled(if: hasPkl, "Set PKL_EXEC for scaffold and CLI package integration"))
struct NativeCLITests {
    @Test func formatterFailurePreservesOutputAndDoesNotPreventPklValidation() throws {
        let f = try Fixture()
        let entry = try f.pair()
        let workspace = try f.file("Modular.xcworkspace/contents.xcworkspacedata", "keep workspace")
        let project = try f.file("A/Example.xcodeproj/project.xcproj", "keep project")
        let environment = [
            "DEVELOPER_DIR": f.root.appendingPathComponent("MissingXcode.app").path
        ]
        let validated = try cli(["validate", entry.path], fixture: f, environment: environment)
        #expect(validated.status == 0, "\(validated.text)")
        let generated = try cli(["generate", entry.path], fixture: f, environment: environment)
        #expect(generated.status != 0 && generated.text.contains("xcrun xcprojformatter"))
        #expect(generated.text.contains("Install Xcode 27.2 or later"))
        #expect(try String(contentsOf: workspace, encoding: .utf8) == "keep workspace")
        #expect(try String(contentsOf: project, encoding: .utf8) == "keep project")
        #expect(
            !FileManager.default.fileExists(
                atPath: f.root.appendingPathComponent("B/Example.xcodeproj").path))
    }

    @Test(arguments: ["workspace", "project"])
    func mainEntryResolvesPackageAndGeneratesSelectedArtifact(_ type: String) throws {
        let f = try Fixture()
        let pkl = try #require(ProcessInfo.processInfo.environment["PKL_EXEC"])
        let cache = f.root.appendingPathComponent("cache")
        let packageLog = try f.file("package.log")
        let handle = try FileHandle(forWritingTo: packageLog)
        defer { try? handle.close() }
        let package = Process()
        package.executableURL = URL(fileURLWithPath: "/bin/bash")
        package.arguments = [
            repository.appendingPathComponent("Scripts/package-pkl.sh").path,
            "--pkl", pkl, "--skip-publish-check", "--install", "--cache-dir", cache.path,
            "--output-path", f.root.appendingPathComponent("dist").path,
        ]
        package.standardOutput = handle
        package.standardError = handle
        try package.run()
        package.waitUntilExit()
        let packageOutput = try String(contentsOf: packageLog, encoding: .utf8)
        try #require(package.terminationStatus == 0, "\(packageOutput)")

        let calls = f.root.appendingPathComponent("calls")
        let wrapper = try f.file(
            "cached-pkl",
            """
            #!/bin/sh
            printf '%s\\n' "$1" >> \(shellQuoted(calls.path))
            if [ "$1" = --version ]; then exec \(shellQuoted(pkl)) "$@"; fi
            exec \(shellQuoted(pkl)) "$@" --cache-dir \(shellQuoted(cache.path))
            """)
        try executable(wrapper)
        let environment = ["PKL_EXEC": wrapper.path]
        let initialized = try cli(
            ["init", "My Workspace", "--type", type], fixture: f, environment: environment)
        try #require(initialized.status == 0, "\(initialized.text)")
        let root = f.root.appendingPathComponent("My Workspace")
        let main = try String(contentsOf: root.appendingPathComponent("Main.pkl"), encoding: .utf8)
        #expect(
            main.contains(type == "workspace" ? "@xcproj/Workspace.pkl" : "@xcproj/Project.pkl"))
        let bundleName = type == "workspace" ? "Chosen Workspace" : "Chosen Project"
        let oldName = type == "workspace" ? "Workspace" : "Core"
        try Data(
            main.replacingOccurrences(
                of: "\nname = \"\(oldName)\"\n", with: "\nname = \"\(bundleName)\"\n"
            ).utf8
        )
        .write(to: root.appendingPathComponent("Main.pkl"))
        let relativeOutput = "Output With Spaces"
        let destination = f.root.appendingPathComponent(relativeOutput).appendingPathComponent(
            "\(bundleName).\(type == "workspace" ? "xcworkspace" : "xcodeproj")")
        let arguments = [root.path, "--output-dir", relativeOutput]
        let validated = try cli(["validate"] + arguments, fixture: f, environment: environment)
        try #require(validated.status == 0, "\(validated.text)")
        #expect(validated.text.contains("1 projects, 2 generated targets"))
        #expect(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("PklProject.deps.json").path))
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let project =
            type == "workspace"
            ? root.appendingPathComponent("Projects/Core/Core.xcodeproj") : destination
        #expect(!FileManager.default.fileExists(atPath: project.path))
        let generated = try cli(["generate"] + arguments, fixture: f, environment: environment)
        try #require(generated.status == 0, "\(generated.text)")
        #expect(FileManager.default.fileExists(atPath: destination.path))
        #expect(FileManager.default.fileExists(atPath: project.path))
        let unchanged = try cli(["generate"] + arguments, fixture: f, environment: environment)
        #expect(unchanged.status == 0 && unchanged.text.contains("Unchanged"))
        if type == "workspace" {
            let standalone = try cli(
                [
                    "generate", root.path, "--entry", "Projects/Core/Project.pkl",
                    "--output-dir", "Standalone Outputs",
                ], fixture: f, environment: environment)
            #expect(standalone.status == 0, "\(standalone.text)")
            #expect(
                FileManager.default.fileExists(
                    atPath: f.root.appendingPathComponent(
                        "Standalone Outputs/Core.xcodeproj/project.xcproj"
                    ).path))
        }
        let invoked = try String(contentsOf: calls, encoding: .utf8).split(separator: "\n")
        #expect(invoked.filter { $0 == "project" }.count == (type == "workspace" ? 4 : 3))
    }
}
