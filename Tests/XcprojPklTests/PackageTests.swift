import CryptoKit
import Foundation
import Testing

@testable import XcprojPkl

private func packageCommand(
    _ executable: String, _ arguments: [String], fixture: Fixture, expectedStatus: Int32 = 0
) throws -> String {
    let log = try fixture.file("log-\(UUID())")
    let handle = try FileHandle(forWritingTo: log)
    defer { try? handle.close() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = fixture.root
    process.standardOutput = handle
    process.standardError = handle
    try process.run()
    process.waitUntilExit()
    let text = try String(contentsOf: log, encoding: .utf8)
    try #require(process.terminationStatus == expectedStatus, "\(text)")
    return text
}

private func digest(_ file: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
}

@Suite(.enabled(if: hasPkl, "Set PKL_EXEC to test package creation and consumption"))
struct PklPackageTests {
    @Test func packageArtifactsAreVerifiedAndConsumedThroughDependencyNotation() throws {
        let f = try Fixture()
        let pkl = try #require(ProcessInfo.processInfo.environment["PKL_EXEC"])
        let output = f.root.appendingPathComponent("dist with spaces")
        let cache = f.root.appendingPathComponent("cache")
        func run(_ executable: String, _ arguments: [String]) throws -> String {
            try packageCommand(executable, arguments, fixture: f)
        }

        _ = try run(
            "/bin/bash",
            [
                repository.appendingPathComponent("Scripts/package-pkl.sh").path,
                "--pkl", pkl, "--version", "1.2.3", "--output-path", output.path,
                "--skip-publish-check",
                "--install", "--cache-dir", cache.path,
            ])
        let artifacts = try FileManager.default.contentsOfDirectory(
            at: output, includingPropertiesForKeys: nil)
        #expect(artifacts.count == 4)
        let archive = try #require(artifacts.first { $0.pathExtension == "zip" })
        let metadata = archive.deletingPathExtension()
        for file in [archive, metadata] {
            #expect(
                try digest(file)
                    == String(contentsOf: file.appendingPathExtension("sha256"), encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let json = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
        let uri = try #require(json["packageUri"] as? String)
        #expect(json["version"] as? String == "1.2.3")
        // Pkl normalizes percent-encoded slashes in package identities.
        #expect(
            uri
                == "package://github.com/giginet/xcproj.pkl/releases/download/pkl/1.2.3/xcproj@1.2.3"
        )
        #expect(
            json["packageZipUrl"] as? String
                == "https://github.com/giginet/xcproj.pkl/releases/download/pkl%2F1.2.3/package.zip"
        )
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
            dependencies { ["xcproj"] { uri = \(quoted(uri.replacingOccurrences(of: "/pkl/", with: "/pkl%2F"))) } }
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

    @Test func releaseAssetsUseTheTagVersionAndMatchTheirMetadata() throws {
        let f = try Fixture()
        let pkl = try #require(ProcessInfo.processInfo.environment["PKL_EXEC"])
        let output = f.root.appendingPathComponent("release assets")
        let script = repository.appendingPathComponent("Scripts/prepare-pkl-release.sh").path
        let manifest = repository.appendingPathComponent("Pkl/xcproj/PklProject")
        let originalManifest = try Data(contentsOf: manifest)
        let arguments = [script, "pkl/2.4.6", "--pkl", pkl, "--output-path", output.path]
        _ = try packageCommand("/bin/bash", arguments, fixture: f)

        let files = try FileManager.default.contentsOfDirectory(atPath: output.path)
        #expect(
            Set(files) == [
                "package.zip", "package.zip.sha256", "xcproj@2.4.6", "xcproj@2.4.6.sha256",
            ])
        let archive = output.appendingPathComponent("package.zip")
        let metadata = output.appendingPathComponent("xcproj@2.4.6")
        for file in [archive, metadata] {
            #expect(
                try digest(file)
                    == String(contentsOf: file.appendingPathExtension("sha256"), encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let json = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
        #expect(json["version"] as? String == "2.4.6")
        #expect(
            json["packageUri"] as? String
                == "package://github.com/giginet/xcproj.pkl/releases/download/pkl/2.4.6/xcproj@2.4.6"
        )
        #expect(
            json["packageZipUrl"] as? String
                == "https://github.com/giginet/xcproj.pkl/releases/download/pkl%2F2.4.6/package.zip"
        )
        #expect(
            json["sourceCodeUrlScheme"] as? String
                == "https://github.com/giginet/xcproj.pkl/blob/pkl%2F2.4.6/Pkl/xcproj%{path}#L%{line}-L%{endLine}"
        )
        let checksums = try #require(json["packageZipChecksums"] as? [String: String])
        #expect(try checksums["sha256"] == digest(archive))
        #expect(try Data(contentsOf: manifest) == originalManifest)

        // A retry must use a fresh staging directory, never mix stale releases.
        let originalArchive = try Data(contentsOf: archive)
        let again = try packageCommand("/bin/bash", arguments, fixture: f, expectedStatus: 2)
        #expect(again.contains("Refusing to reuse"))
        #expect(try Data(contentsOf: archive) == originalArchive)
    }

    @Test(arguments: [
        "v1.2.3", "pkl/1.2", "pkl/01.2.3", "pkl/1.02.3", "pkl/1.2.03", "pkl/1.2.3-rc.1",
        "pkl/1.2.3/other",
    ])
    func invalidReleaseTagsFailBeforeRunningPkl(_ tag: String) throws {
        let f = try Fixture()
        let output = f.root.appendingPathComponent("release assets")
        let text = try packageCommand(
            "/bin/bash",
            [
                repository.appendingPathComponent("Scripts/prepare-pkl-release.sh").path,
                tag, "--pkl", "/missing/pkl", "-o", output.path,
            ],
            fixture: f, expectedStatus: 2)
        #expect(text.contains("Invalid release tag"))
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
}
