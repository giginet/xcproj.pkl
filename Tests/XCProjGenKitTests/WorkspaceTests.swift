import Foundation
import Testing
import XcodeProjectFormat

@testable import XCProjGenKit

@Suite(.requiresPkl)
struct NativeWorkspaceTests {
    @Test func inlineProjectsUseTheWorkspaceDirectoryAndImportedProjectsKeepTheirOwn() throws {
        let f = try Fixture()
        try f.directory("Sources")
        try f.project(
            #"targets { ["app"] { name = "App"; type = "tool"; platform = "macOS" } }"#,
            at: "Imported/Project.pkl")
        let entry = try f.workspace(
            #"""
            ["first"] {
              name = "First"
              targets { ["lib"] { name = "First"; type = "framework"; platform = "iOS"; sources { new { path = "Sources" } } } }
            }
            ["second"] {
              name = "Second"
              targets { ["lib"] { name = "Second"; type = "framework"; platform = "iOS" } }
            }
            ["imported"] = import("Imported/Project.pkl")
            """#)
        let plan = try GenerationPlan.compile(source: entry, outputDirectory: f.url("Output"))
        #expect(plan.projectCount == 3 && plan.targetCount == 3)
        #expect(
            Set(plan.projects.map { $0.bundle.path })
                == Set([
                    f.url("First.xcodeproj").path, f.url("Second.xcodeproj").path,
                    f.url("Imported/Example.xcodeproj").path,
                ]))
        #expect(plan.destination.path == f.url("Output/Modular.xcworkspace").path)
    }

    @Test func standaloneAndWorkspaceMatchAndXMLRebasesAndEscapes() throws {
        let f = try Fixture()
        let body =
            #"targets { ["app"] { name = "App"; type = "tool"; platform = "macOS"; sources { new { path = "Sources" } } } }"#
        let source = try f.project(body, at: "A & B/Project.pkl")
        try f.directory("A & B/Sources")
        try f.project(body, at: "Other/Project.pkl")
        try f.directory("Other/Sources")
        let entry = try f.workspace(
            #"["a"] = import("A & B/Project.pkl"); ["b"] = import("Other/Project.pkl")"#)
        let standalone = try GenerationPlan.compile(source: source)
        let plan = try GenerationPlan.compile(
            source: entry, outputDirectory: f.root.appendingPathComponent("Output"))
        #expect(plan.projectCount == 2 && plan.targetCount == 2)
        #expect(plan.projects[0].data == standalone.projects[0].data)
        #expect(plan.projects[0].destination == standalone.projects[0].destination)
        let xml = try #require(plan.files.first { !$0.isProject })
        #expect(
            String(decoding: xml.data, as: UTF8.self).contains("../A &amp; B/Example.xcodeproj"))
        #expect(!FileManager.default.fileExists(atPath: plan.destination.path))
        try plan.write()
        for file in plan.projects {
            let canonical = try XCSchema.Project(jsonRepresentation: file.data).jsonRepresentation()
            #expect(try Data(contentsOf: file.destination) == canonical)
        }
        #expect(
            try !GenerationPlan.compile(
                source: entry, outputDirectory: plan.destination.deletingLastPathComponent()
            ).write())
    }

    @Test func projectAmendmentRetainsOriginalModuleRoot() throws {
        let f = try Fixture()
        try f.project(
            #"targets { ["app"] { name = module.name; type = "tool"; platform = "macOS"; sources { new { path = "Sources" } } } }"#,
            at: "A/Project.pkl")
        try f.directory("A/Sources")
        let entry = try f.workspace(#"["a"] = (import("A/Project.pkl")) { name = "Custom" }"#)
        let plan = try GenerationPlan.compile(source: entry)
        #expect(plan.projects[0].bundle.lastPathComponent == "Custom.xcodeproj")
        let project = try XCSchema.Project(jsonRepresentation: plan.projects[0].data)
        #expect(project.targets[0].name == "Custom")
        guard case .folder(let folder) = project.topLevelReferences[0] else {
            Issue.record("Expected folder")
            return
        }
        #expect(folder.path.path == "Sources")
    }

    @Test func projectModuleSymlinkUsesCanonicalParentInBothEntryModes() throws {
        let f = try Fixture()
        try f.project(
            #"targets { ["a"] { name = "A"; type = "tool"; platform = "macOS"; sources { new { path = "Sources" } } } }"#,
            at: "Actual/Project.pkl")
        try f.directory("Actual/Sources")
        try f.directory("Elsewhere")
        try f.symlink("Elsewhere/Project.pkl", to: "../Actual/Project.pkl")
        let standalone = try GenerationPlan.compile(
            source: f.root.appendingPathComponent("Elsewhere/Project.pkl"))
        let entry = try f.workspace(#"["a"] = import("Elsewhere/Project.pkl")"#)
        let workspace = try GenerationPlan.compile(source: entry)
        #expect(standalone.projects[0].data == workspace.projects[0].data)
        #expect(
            standalone.destination.path
                == f.root.appendingPathComponent("Actual/Example.xcodeproj").path)
    }

    @Test func entryModuleSymlinkResolvesRelativeImportsFromItsCanonicalDirectory() throws {
        let f = try Fixture()
        try f.directory("Links")
        try f.file(
            "Actual/Base.pkl", "open module Base\nextends \(quoted(schema))\nname = \"Canonical\"\n"
        )
        let source = try f.file(
            "Actual/Project.pkl",
            #"""
            amends "Base.pkl"
            targets { ["app"] { name = "App"; type = "tool"; platform = "macOS" } }
            """#)
        try f.symlink("Links/Project.pkl", to: "../Actual/Project.pkl")
        let direct = try GenerationPlan.compile(source: source)
        let linked = try GenerationPlan.compile(
            source: f.root.appendingPathComponent("Links/Project.pkl"))
        #expect(direct.projects[0].data == linked.projects[0].data)
        #expect(direct.destination == linked.destination)
    }

    @Test func workspaceSchemaVersionIsForcedDespiteLazyEvaluation() throws {
        let f = try Fixture()
        _ = try f.pair()
        let source = try f.file(
            "OldWorkspace.pkl",
            """
            amends \(quoted(workspaceSchema))
            schemaVersion = 1
            name = "Old"
            projects { ["a"] = import("A/Project.pkl") }
            """)
        expectFailure(containing: "schemaVersion") {
            _ = try GenerationPlan.compile(source: source)
        }
    }

    @Test func duplicateModuleAliasesAreRejected() throws {
        let f = try Fixture()
        _ = try f.pair()
        try f.symlink("Alias.pkl", to: "A/Project.pkl")
        let entry = try f.workspace(
            #"["a"] = import("A/Project.pkl"); ["b"] = import("Alias.pkl")"#)
        expectFailure(containing: "Duplicate project module") {
            _ = try GenerationPlan.compile(source: entry)
        }
    }

    @Test func duplicateAndNestedOutputsAreRejected() throws {
        let f = try Fixture()
        try f.directory("Shared")
        let body =
            #"projectDir = "../Shared"; targets { ["a"] { name = "A"; type = "tool"; platform = "macOS" } }"#
        try f.project(body, at: "A/Project.pkl")
        try f.project(body, at: "B/Project.pkl")
        expectFailure(containing: "Duplicate workspace/project output paths") {
            _ = try GenerationPlan.compile(source: f.workspace())
        }
        let entry = try f.workspace(#"["a"] = import("A/Project.pkl")"#)
        try f.directory("Shared/Example.xcodeproj")
        expectFailure(containing: "Nested workspace/project output paths") {
            _ = try GenerationPlan.compile(
                source: entry,
                outputDirectory: f.root.appendingPathComponent("Shared/Example.xcodeproj")
            )
        }
        try f.directory("Dest")
        try f.symlink("DestAlias", to: "Dest")
        let source = try f.project(
            #"projectDir = "../Dest"; targets { ["a"] { name = "A"; type = "tool"; platform = "macOS" } }"#,
            at: "A/Project.pkl")
        _ = source
        try f.project(
            #"projectDir = "../DestAlias"; targets { ["b"] { name = "B"; type = "tool"; platform = "macOS" } }"#,
            at: "B/Project.pkl")
        expectFailure(containing: "Duplicate workspace/project output paths") {
            _ = try GenerationPlan.compile(source: f.workspace())
        }
    }

    @Test func invalidLastMemberAndPreflightLeaveAllOutputsUntouched() throws {
        let f = try Fixture()
        let entry = try f.pair()
        let plan = try GenerationPlan.compile(source: entry)
        try f.file("B/Example.xcodeproj/project.pbxproj", "legacy")
        expectFailure(containing: "legacy project") { try plan.write() }
        #expect(!FileManager.default.fileExists(atPath: plan.projects[0].destination.path))
        try FileManager.default.removeItem(at: f.root.appendingPathComponent("B/Example.xcodeproj"))
        try plan.write()
        let original = try Data(contentsOf: plan.projects[0].destination)
        try f.project(#"defaultConfiguration = "Missing""#, at: "B/Project.pkl")
        expectFailure(containing: "defaultConfiguration") {
            try GenerationPlan.compile(source: entry).write()
        }
        #expect(try Data(contentsOf: plan.projects[0].destination) == original)
    }

    @Test func removedMembersAreNotDeleted() throws {
        let f = try Fixture()
        let entry = try f.pair()
        let first = try GenerationPlan.compile(source: entry)
        try first.write()
        _ = try f.workspace(#"["a"] = import("A/Project.pkl")"#)
        let second = try GenerationPlan.compile(source: entry)
        try second.write()
        #expect(FileManager.default.fileExists(atPath: first.projects[1].destination.path))
    }
}
