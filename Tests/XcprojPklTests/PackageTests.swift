import CryptoKit
import Foundation
import Testing

@testable import XcprojPkl

@Suite(.enabled(if: hasPkl, "Set PKL_EXEC to test package creation and consumption"))
struct PklPackageTests {
    @Test func packageArtifactsAreVerifiedAndConsumedThroughDependencyNotation() throws {
        let f = try Fixture()
        let pkl = try #require(ProcessInfo.processInfo.environment["PKL_EXEC"])
        let output = f.root.appendingPathComponent("dist with spaces")
        let cache = f.root.appendingPathComponent("cache")
        func run(_ executable: String, _ arguments: [String]) throws -> String {
            let log = try f.file("log-\(UUID())")
            let handle = try FileHandle(forWritingTo: log)
            defer { try? handle.close() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = f.root
            process.standardOutput = handle
            process.standardError = handle
            try process.run()
            process.waitUntilExit()
            let text = try String(contentsOf: log, encoding: .utf8)
            try #require(process.terminationStatus == 0, "\(text)")
            return text
        }

        _ = try run(
            "/bin/bash",
            [
                repository.appendingPathComponent("Scripts/package-pkl.sh").path,
                "--pkl", pkl, "--output-path", output.path, "--skip-publish-check",
                "--install", "--cache-dir", cache.path,
            ])
        let artifacts = try FileManager.default.contentsOfDirectory(
            at: output, includingPropertiesForKeys: nil)
        #expect(artifacts.count == 4)
        let archive = try #require(artifacts.first { $0.pathExtension == "zip" })
        let metadata = archive.deletingPathExtension()
        func digest(_ file: URL) throws -> String {
            SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }
                .joined()
        }
        for file in [archive, metadata] {
            #expect(
                try digest(file)
                    == String(contentsOf: file.appendingPathExtension("sha256"), encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let json = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
        let uri = try #require(json["packageUri"] as? String)
        let checksums = try #require(json["packageZipChecksums"] as? [String: String])
        #expect(try checksums["sha256"] == digest(archive))

        let entries = try run("/usr/bin/unzip", ["-Z1", archive.path]).split(separator: "\n").map(
            String.init)
        #expect(entries.contains("Project.pkl") && entries.contains("Workspace.pkl"))
        #expect(entries.contains("Internal/Render.pkl") && entries.contains("README.md"))
        #expect(
            !entries.contains {
                $0.hasSuffix(".swift") || $0.hasPrefix("tests/") || $0 == "PklProject"
                    || $0 == "PklProject.deps.json"
            })

        // Resolve a remote-identity dependency from a fresh cache populated by --install.
        // No release or web server is required for this test.
        let consumer = f.root.appendingPathComponent("Consumer")
        try f.file(
            "Consumer/PklProject",
            """
            amends "pkl:Project"
            dependencies { ["xcproj"] { uri = \(quoted(uri)) } }
            """)
        _ = try run(pkl, ["project", "resolve", "--cache-dir", cache.path, consumer.path])
        let source = try f.file(
            "Consumer/Project.pkl",
            #"""
            amends "@xcproj/Project.pkl"
            name = "Packaged"
            targets { ["app"] { name = "App"; type = "tool"; platform = "macOS" } }
            """#)
        let workspace = try f.file(
            "Consumer/Workspace.pkl",
            #"""
            amends "@xcproj/Workspace.pkl"
            name = "PackagedWorkspace"
            projects { ["app"] = import("Project.pkl") }
            """#)
        let wrapper = try f.file(
            "cached-pkl",
            """
            #!/bin/sh
            subcommand="$1"
            shift
            exec \(shellQuoted(pkl)) "$subcommand" --cache-dir \(shellQuoted(cache.path)) "$@"
            """)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
        let evaluator = PklTool(executable: wrapper.path)
        let standalone = try GenerationPlan.compile(source: source, tool: evaluator)
        let plan = try GenerationPlan.compile(source: workspace, tool: evaluator)
        #expect(plan.projectCount == 1 && plan.targetCount == 1)
        #expect(plan.projects[0].data == standalone.projects[0].data)
        try plan.write()
        #expect(try WorkspaceValidator.validate(plan.destination).projectCount == 1)
    }
}
