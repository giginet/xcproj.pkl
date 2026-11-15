import Foundation
import Testing

@testable import XcprojPkl

@Suite(.enabled(if: hasPkl, "Set PKL_EXEC to test existing workspace project references"))
struct ExistingWorkspaceTests {
    private func legacy(_ fixture: Fixture, at path: String = "Vendor/Legacy.xcodeproj") throws
        -> URL
    {
        try fixture.file(
            "\(path)/project.pbxproj",
            """
            // !$*UTF8*$!
            {
                archiveVersion = 1;
                objectVersion = 56;
                classes = {};
                objects = {
                    AAAAAAAAAAAAAAAAAAAAAAAA = { isa = PBXProject; targets = (BBBBBBBBBBBBBBBBBBBBBBBB,); };
                    BBBBBBBBBBBBBBBBBBBBBBBB = { isa = PBXAggregateTarget; name = Legacy; };
                };
                rootObject = AAAAAAAAAAAAAAAAAAAAAAAA;
            }
            """)
        return fixture.root.appendingPathComponent(path)
    }

    @Test func mixedWorkspaceRebasesReferencesAndPreservesExistingBundles() throws {
        let fixture = try Fixture()
        let legacyBundle = try legacy(fixture, at: "Vendor/A & B <日本>.xcodeproj")
        let scheme = try fixture.file(
            "Vendor/A & B <日本>.xcodeproj/xcshareddata/xcschemes/Keep.xcscheme", "keep this scheme")
        let existingSource = try fixture.project(
            #"targets { ["tool"] { name = "Existing"; type = "tool" } }"#,
            at: "Existing/Project.pkl")
        let existing = try GenerationPlan.compile(source: existingSource)
        try existing.write()
        try fixture.project(
            #"targets { ["tool"] { name = "Generated"; type = "tool" } }"#,
            at: "Generated/Project.pkl")
        let source = try fixture.file(
            "Config/Main.pkl",
            """
            amends \(quoted(workspaceSchema))
            name = "Mixed"
            workspaceDir = ".."
            projects {
              ["z-generated"] = import("../Generated/Project.pkl")
              ["m-json"] = module.importXcodeproj(\(quoted(existing.destination.path)))
              ["a-legacy"] = module.importXcodeproj("Vendor/A & B <日本>.xcodeproj/")
            }
            """)
        let inputs = [
            legacyBundle.appendingPathComponent("project.pbxproj"), scheme,
            existing.destination.appendingPathComponent("project.xcproj"),
        ]
        let original = try inputs.map { try Data(contentsOf: $0) }
        let modified = try inputs.map {
            try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        let output = fixture.root.appendingPathComponent("Relocated")
        let plan = try GenerationPlan.compile(source: source, outputDirectory: output)
        #expect(plan.projectCount == 3 && plan.targetCount == 1)
        #expect(plan.projects.count == 1 && plan.files.count == 2)
        #expect(!FileManager.default.fileExists(atPath: plan.destination.path))
        let workspace = try #require(plan.files.first { !$0.isProject && !$0.isScheme })
        let references = try WorkspaceValidator.projectURLs(
            data: workspace.data, workspace: workspace.bundle)
        #expect(
            references.map(\.path) == [
                legacyBundle.path, existing.destination.path,
                fixture.root.appendingPathComponent("Generated/Example.xcodeproj").path,
            ])
        #expect(
            String(decoding: workspace.data, as: UTF8.self).contains(
                "../Vendor/A &amp; B &lt;日本&gt;.xcodeproj"))
        #expect(try plan.write())
        let validation = try WorkspaceValidator.validate(plan.destination)
        #expect(validation.projectCount == 3)
        let next = try GenerationPlan.compile(source: source, outputDirectory: output)
        #expect(next.files.map(\.data) == plan.files.map(\.data))
        #expect(try !next.write())
        #expect(try inputs.map { try Data(contentsOf: $0) } == original)
        #expect(
            try inputs.map {
                try $0.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate
            } == modified)
    }

    @Test func workspaceCanContainOnlyExistingProjectsAndUseAnAmendedReference() throws {
        let fixture = try Fixture()
        let existing = try legacy(fixture)
        let source = try fixture.file(
            "Main.pkl",
            """
            amends \(quoted(workspaceSchema))
            local base = module.importXcodeproj("Unused.xcodeproj")
            name = "ExistingOnly"
            projects { ["legacy"] = (base) { path = "Vendor/Legacy.xcodeproj" } }
            """)
        let plan = try GenerationPlan.compile(source: source)
        #expect(plan.projectCount == 1 && plan.targetCount == 0)
        #expect(plan.projects.isEmpty && plan.files.count == 1)
        #expect(
            try WorkspaceValidator.projectURLs(
                data: plan.files[0].data, workspace: plan.destination) == [existing])
        try plan.write()
        #expect(try WorkspaceValidator.validate(plan.destination).projectCount == 1)
    }

    @Test func duplicateCanonicalExistingProjectsAreRejected() throws {
        let fixture = try Fixture()
        _ = try legacy(fixture)
        try fixture.symlink("Alias.xcodeproj", to: "Vendor/Legacy.xcodeproj")
        let source = try fixture.workspace(
            #"["a"] = module.importXcodeproj("Vendor/Legacy.xcodeproj"); ["b"] = module.importXcodeproj("Alias.xcodeproj")"#
        )
        expectFailure(containing: "Duplicate") {
            _ = try GenerationPlan.compile(source: source)
        }
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.root.appendingPathComponent("Modular.xcworkspace").path))
    }

    @Test(arguments: ["Missing.xcodeproj", "Regular.xcodeproj", "Wrong.txt"])
    func invalidExistingProjectPathsFailBeforeWriting(_ path: String) throws {
        let fixture = try Fixture()
        try fixture.file("Regular.xcodeproj", "not a directory")
        try fixture.directory("Wrong.txt")
        let source = try fixture.workspace(#"["external"] = module.importXcodeproj("\#(path)")"#)
        #expect(throws: (any Error).self) { _ = try GenerationPlan.compile(source: source) }
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.root.appendingPathComponent("Modular.xcworkspace").path))
    }

    @Test func generatedProjectCannotOverwriteAnImportedProject() throws {
        let fixture = try Fixture()
        let project = try fixture.project(
            #"targets { ["tool"] { name = "Existing"; type = "tool" } }"#,
            at: "Existing/Project.pkl")
        let original = try GenerationPlan.compile(source: project)
        try original.write()
        let before = try Data(contentsOf: original.projects[0].destination)
        let source = try fixture.workspace(
            #"["generated"] = import("Existing/Project.pkl"); ["existing"] = module.importXcodeproj("Existing/Example.xcodeproj")"#
        )
        #expect(throws: (any Error).self) { try GenerationPlan.compile(source: source).write() }
        #expect(try Data(contentsOf: original.projects[0].destination) == before)
    }

    @Test func workspaceOutputCannotBeInsideAnImportedBundle() throws {
        let fixture = try Fixture()
        let existing = try legacy(fixture)
        let source = try fixture.workspace(
            #"["existing"] = module.importXcodeproj("Vendor/Legacy.xcodeproj")"#)
        #expect(throws: (any Error).self) {
            try GenerationPlan.compile(
                source: source, outputDirectory: existing.appendingPathComponent("Output")
            ).write()
        }
        #expect(
            !FileManager.default.fileExists(atPath: existing.appendingPathComponent("Output").path))
    }

    @Test func writeProtectsExistingBundlesAfterAnOutputSymlinkChanges() throws {
        let fixture = try Fixture()
        let existing = try legacy(fixture)
        let source = try fixture.workspace(
            #"["existing"] = module.importXcodeproj("Vendor/Legacy.xcodeproj")"#)
        let output = fixture.root.appendingPathComponent("Output")
        let plan = try GenerationPlan.compile(source: source, outputDirectory: output)
        try fixture.symlink("Output", to: "Vendor/Legacy.xcodeproj")
        #expect(throws: (any Error).self) { try plan.write() }
        #expect(
            !FileManager.default.fileExists(
                atPath: existing.appendingPathComponent("Modular.xcworkspace").path))
    }

    @Test(arguments: [
        [], ["project.xcproj"], ["project.pbxproj"], ["project.xcproj", "project.pbxproj"],
    ])
    func existingProjectContentsAreOpaque(_ documents: [String]) throws {
        let fixture = try Fixture()
        try fixture.project(
            #"targets { ["tool"] { name = "Generated"; type = "tool" } }"#,
            at: "Generated/Project.pkl")
        try fixture.directory("Existing.xcodeproj")
        for document in documents {
            try fixture.file("Existing.xcodeproj/\(document)", "opaque project contents")
        }
        let source = try fixture.workspace(
            #"["generated"] = import("Generated/Project.pkl"); ["existing"] = module.importXcodeproj("Existing.xcodeproj")"#
        )
        let plan = try GenerationPlan.compile(source: source)
        #expect(plan.projectCount == 2 && plan.targetCount == 1)
        try plan.write()
        #expect(try WorkspaceValidator.validate(plan.destination).projectCount == 2)
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.root.appendingPathComponent("Generated/Example.xcodeproj").path))
        for document in documents {
            #expect(
                try String(
                    contentsOf: fixture.root.appendingPathComponent(
                        "Existing.xcodeproj/\(document)"),
                    encoding: .utf8) == "opaque project contents")
        }
    }
}
