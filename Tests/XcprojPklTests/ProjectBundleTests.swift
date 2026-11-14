import Foundation
import Testing

@testable import XcprojPkl

private let bundleJSON = #"""
    {
      "configurations": ["Debug"], "default-configuration": "Debug", "files": [], "products-group": null,
      "localizations": {"development": "en", "supported": ["Base"]},
      "targets": [{"name": "Tool", "id": "AAAAAAAAAAAAAAAAAAAAAAAA", "product-type": "tool"}]
    }
    """#

private let bundlePBX = """
    // !$*UTF8*$!
    {
        archiveVersion = 1;
        objectVersion = 77;
        objects = {
            PROJECT = { isa = PBXProject; targets = (NATIVE, AGGREGATE, LEGACY); };
            NATIVE = { isa = PBXNativeTarget; name = Tool; };
            AGGREGATE = { isa = PBXAggregateTarget; name = All; };
            LEGACY = { isa = PBXLegacyTarget; name = Make; };
        };
        rootObject = PROJECT;
    }
    """

struct ProjectBundleTests {
    @Test func validatesJSONAndLegacyBundlesWithoutChangingTheirFiles() throws {
        let f = try Fixture()
        let json = try f.file("JSON.xcodeproj/project.xcproj", bundleJSON)
        let pbx = try f.file("Legacy.xcodeproj/project.pbxproj", bundlePBX)
        try f.file("Legacy.xcodeproj/xcshareddata/keep.txt", "keep")
        #expect(try ProjectBundleValidator.validate(json.deletingLastPathComponent()) == 1)
        #expect(try ProjectBundleValidator.validate(pbx.deletingLastPathComponent()) == 3)
        #expect(try String(contentsOf: json, encoding: .utf8) == bundleJSON)
        #expect(try String(contentsOf: pbx, encoding: .utf8) == bundlePBX)
        #expect(
            try FileManager.default.contentsOfDirectory(
                atPath: pbx.deletingLastPathComponent().path
            )
            .sorted() == ["project.pbxproj", "xcshareddata"])
    }

    @Test func validatesMixedWorkspaceAndLegacyBundleFromCLIWithoutPkl() throws {
        let f = try Fixture()
        try f.file("JSON.xcodeproj/project.xcproj", bundleJSON)
        try f.file("Legacy.xcodeproj/project.pbxproj", bundlePBX)
        let workspace = try f.file(
            "Mixed.xcworkspace/contents.xcworkspacedata",
            #"<Workspace version="1.0"><FileRef location="group:JSON.xcodeproj"/><FileRef location="group:Legacy.xcodeproj"/></Workspace>"#
        ).deletingLastPathComponent()
        let validation = try WorkspaceValidator.validate(workspace)
        #expect(validation.projectCount == 2 && validation.targetCount == 4)
        let output = try f.file("cli.log")
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = repository.appendingPathComponent(".build/debug/xcprojgen")
            .resolvingSymlinksInPath()
        process.arguments = ["validate", f.root.appendingPathComponent("Legacy.xcodeproj").path]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "PKL_EXEC": "/missing/pkl"
        ]) {
            _, new in new
        }
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        process.waitUntilExit()
        let message = try String(contentsOf: output, encoding: .utf8)
        #expect(process.terminationStatus == 0, "\(message)")
        #expect(message.contains("1 projects, 3 targets"))
    }

    @Test func requiresAnUnambiguousProjectDocumentInAnExistingBundleDirectory() throws {
        let f = try Fixture()
        let bundle = f.root.appendingPathComponent("Example.xcodeproj")
        expectFailure(containing: "existing .xcodeproj directory") {
            _ = try ProjectBundleValidator.validate(bundle)
        }
        try f.file("Example.xcodeproj")
        expectFailure(containing: "existing .xcodeproj directory") {
            _ = try ProjectBundleValidator.validate(bundle)
        }
        try FileManager.default.removeItem(at: bundle)
        try f.directory("Example.xcodeproj")
        expectFailure(containing: "exactly one") { _ = try ProjectBundleValidator.validate(bundle) }
        try f.directory("Example.xcodeproj/project.pbxproj")
        expectFailure(containing: "document is a directory") {
            _ = try ProjectBundleValidator.validate(bundle)
        }
        try FileManager.default.removeItem(at: bundle.appendingPathComponent("project.pbxproj"))
        try f.file("Example.xcodeproj/project.xcproj", bundleJSON)
        try f.file("Example.xcodeproj/project.pbxproj", bundlePBX)
        expectFailure(containing: "exactly one") { _ = try ProjectBundleValidator.validate(bundle) }
        try f.file("Wrong.bundle/project.xcproj", bundleJSON)
        expectFailure(containing: "existing .xcodeproj directory") {
            _ = try ProjectBundleValidator.validate(f.root.appendingPathComponent("Wrong.bundle"))
        }
    }

    @Test func malformedJSONStillUsesFullProjectValidation() throws {
        let f = try Fixture()
        let file = try f.file("Invalid.xcodeproj/project.xcproj", "{")
        #expect(throws: (any Error).self) {
            try ProjectBundleValidator.validate(file.deletingLastPathComponent())
        }
        try f.file(
            "Invalid.xcodeproj/project.xcproj",
            bundleJSON.replacingOccurrences(
                of: "\"default-configuration\": \"Debug\"",
                with: "\"default-configuration\": \"Missing\""))
        expectFailure(containing: "Unknown default build configuration") {
            _ = try ProjectBundleValidator.validate(file.deletingLastPathComponent())
        }
    }

    @Test(arguments: [
        "{ objects = (",  // Malformed OpenStep syntax.
        "{ objects = {}; rootObject = MISSING; }",
        "{ objects = { P = { isa = PBXGroup; targets = (); }; }; rootObject = P; }",
        "{ objects = { P = { isa = PBXProject; }; }; rootObject = P; }",
        "{ objects = { P = { isa = PBXProject; targets = (MISSING); }; }; rootObject = P; }",
        "{ objects = { P = { isa = PBXProject; targets = (T); }; T = { isa = PBXGroup; }; }; rootObject = P; }",
        "{ objects = { P = { isa = PBXProject; targets = (T,T); }; T = { isa = PBXNativeTarget; }; }; rootObject = P; }",
    ])
    func rejectsMalformedLegacyStructure(_ document: String) throws {
        let f = try Fixture()
        let file = try f.file("Invalid.xcodeproj/project.pbxproj", document)
        expectFailure(containing: "project.pbxproj") {
            _ = try ProjectBundleValidator.validate(file.deletingLastPathComponent())
        }
    }
}
