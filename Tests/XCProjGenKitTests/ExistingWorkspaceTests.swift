import Foundation
import Testing

@testable import XCProjGenKit

@Suite(.requiresPkl)
struct ExistingWorkspaceTests {
    @Test func mixedWorkspaceRebasesReferencesAndPreservesExistingProject() throws {
        let f = try Fixture()
        let existing = try f.file("Vendor/Existing.xcodeproj/project.pbxproj", "opaque project")
        try f.project(
            #"targets { ["tool"] { name = "Generated"; type = "tool" } }"#,
            at: "Generated/Project.pkl")
        let source = try f.file(
            "Config/Main.pkl",
            """
            amends \(quoted(workspaceSchema))
            name = "Mixed"
            workspaceDir = ".."
            projects {
              ["generated"] = import("../Generated/Project.pkl")
              ["existing"] = module.importXcodeproj("Vendor/Existing.xcodeproj")
            }
            """)
        let plan = try GenerationPlan.compile(
            source: source, outputDirectory: f.root.appendingPathComponent("Output"))
        #expect(plan.projectCount == 2 && plan.targetCount == 1)
        #expect(plan.projects.count == 1 && plan.files.count == 2)
        let workspace = try #require(plan.files.first { !$0.isProject })
        #expect(
            String(decoding: workspace.data, as: UTF8.self).contains("../Vendor/Existing.xcodeproj")
        )
        try plan.write()
        #expect(try String(contentsOf: existing, encoding: .utf8) == "opaque project")
    }

    @Test func workspaceCanContainOnlyExistingProjects() throws {
        let f = try Fixture()
        try f.directory("Existing.xcodeproj")
        let source = try f.workspace(
            #"["existing"] = module.importXcodeproj("Existing.xcodeproj")"#)
        let plan = try GenerationPlan.compile(source: source)
        #expect(plan.projectCount == 1 && plan.targetCount == 0)
        #expect(plan.projects.isEmpty && plan.files.count == 1)
        try plan.write()
    }

    @Test(arguments: ["Missing.xcodeproj", "Regular.xcodeproj", "Wrong.txt"])
    func invalidExistingProjectPathIsRejected(_ path: String) throws {
        let f = try Fixture()
        try f.file("Regular.xcodeproj", "not a directory")
        try f.directory("Wrong.txt")
        let source = try f.workspace(#"["existing"] = module.importXcodeproj("\#(path)")"#)
        #expect(throws: (any Error).self) { try GenerationPlan.compile(source: source) }
    }

    @Test func generatedProjectCannotOverwriteAnImportedProject() throws {
        let f = try Fixture()
        try f.directory("Generated/Example.xcodeproj")
        try f.project(
            #"targets { ["tool"] { name = "Generated"; type = "tool" } }"#,
            at: "Generated/Project.pkl")
        let source = try f.workspace(
            #"["generated"] = import("Generated/Project.pkl"); ["existing"] = module.importXcodeproj("Generated/Example.xcodeproj")"#
        )
        expectFailure(containing: "Existing project overlaps") {
            _ = try GenerationPlan.compile(source: source)
        }
    }
}
