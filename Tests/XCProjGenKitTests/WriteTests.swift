import Foundation
import Testing

@testable import XCProjGenKit

/// Validation and writing of rendered plans, from hand-written fixtures.
struct WriteTests {
    private func scheme(
        container: String = "container:Example.xcodeproj", id: String = toolTargetID
    )
        -> String
    {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <Scheme version="1.7"><BuildAction><BuildActionEntries><BuildActionEntry>
        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="\(id)" \
        BuildableName="App" BlueprintName="App" ReferencedContainer="\(container)"/>
        </BuildActionEntry></BuildActionEntries></BuildAction></Scheme>
        """
    }

    @Test func onlyChangedFilesAreWrittenAndOtherBundleContentsArePreserved() throws {
        let f = try Fixture()
        var scenario = Scenario()
        scenario.project("root", in: f.root)
        let plan = try scenario.plan()
        let output = "Example.xcodeproj/project.xcproj"

        #expect(try plan.write { $0 })
        #expect(try f.text(output) == toolDocument)
        try f.file("Example.xcodeproj/xcshareddata/keep.txt", "keep")
        let date = try f.url(output).resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate

        #expect(try !scenario.plan().write { $0 })
        #expect(
            try f.url(output).resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate == date)
        #expect(try f.text("Example.xcodeproj/xcshareddata/keep.txt") == "keep")

        // The formatted bytes are what is compared and saved.
        #expect(try plan.write { _ in Data("formatted".utf8) })
        #expect(try f.text(output) == "formatted")
        #expect(try !plan.write { _ in Data("formatted".utf8) })
    }

    @Test func formatterFailureLeavesEveryOutputUntouched() throws {
        let f = try Fixture()
        var scenario = Scenario()
        scenario.workspace("workspace", in: f.root)
        scenario.project("a", in: f.url("A"))
        scenario.project("b", in: f.url("B"))
        let plan = try scenario.plan()
        #expect(plan.projectCount == 2 && plan.targetCount == 2 && plan.files.count == 3)
        try f.file("A/Example.xcodeproj/project.xcproj", "keep project")
        try f.file("Modular.xcworkspace/contents.xcworkspacedata", "keep workspace")

        expectFailure(containing: "xcrun xcprojformatter failed") {
            try plan.write { _ in throw ProjectError("xcrun xcprojformatter failed") }
        }
        #expect(try f.text("A/Example.xcodeproj/project.xcproj") == "keep project")
        #expect(try f.text("Modular.xcworkspace/contents.xcworkspacedata") == "keep workspace")
        #expect(!f.exists("B/Example.xcodeproj"))
    }

    @Test func legacyProjectsAndStructuralConflictsAreRejectedBeforeWriting() throws {
        let f = try Fixture()
        var scenario = Scenario()
        scenario.workspace("workspace", in: f.root)
        scenario.project("a", in: f.url("A"))
        scenario.project("b", in: f.url("B"))
        let plan = try scenario.plan()
        try f.file("B/Example.xcodeproj/project.pbxproj", "legacy")
        expectFailure(containing: "legacy project") { try plan.write { $0 } }
        #expect(!f.exists("A/Example.xcodeproj") && !f.exists("Modular.xcworkspace"))

        try FileManager.default.removeItem(at: f.url("B/Example.xcodeproj"))
        try f.file("A/Example.xcodeproj", "regular file")
        expectFailure(containing: "Output directory is a file") { try plan.write { $0 } }
        #expect(!f.exists("B/Example.xcodeproj") && !f.exists("Modular.xcworkspace"))
    }

    @Test func duplicateAndNestedBundlesAreRejected() throws {
        let f = try Fixture()
        var duplicate = Scenario()
        duplicate.workspace("workspace", in: f.root)
        duplicate.project("a", in: f.url("Shared"))
        duplicate.project("b", in: f.url("Shared"))
        expectFailure(containing: "Duplicate output") { _ = try duplicate.plan() }

        // The same bundle reached through a symlink is still a duplicate.
        try f.directory("Dest")
        try f.symlink("DestAlias", to: "Dest")
        var aliased = Scenario()
        aliased.workspace("workspace", in: f.root)
        aliased.project("a", in: f.url("Dest"))
        aliased.project("b", in: f.url("DestAlias"))
        expectFailure(containing: "Duplicate output") { _ = try aliased.plan() }

        var nested = Scenario()
        nested.workspace("workspace", in: f.root)
        nested.project("a", in: f.root, name: "Outer")
        nested.project("b", in: f.url("Outer.xcodeproj"), name: "Inner")
        expectFailure(containing: "Nested output paths") { _ = try nested.plan() }
    }

    @Test func existingProjectsAreCountedButNeverWritten() throws {
        let f = try Fixture()
        let existing = try f.file("Vendor/Existing.xcodeproj/project.pbxproj", "opaque project")
        var scenario = Scenario()
        scenario.workspace("workspace", in: f.root, name: "Mixed")
        scenario.project("generated", in: f.url("Generated"))
        scenario.existingProject("existing", at: f.url("Vendor/Existing.xcodeproj"))
        let plan = try scenario.plan(outputDirectory: f.url("Output"))
        #expect(plan.projectCount == 2 && plan.targetCount == 1)
        #expect(plan.projects.count == 1 && plan.files.count == 2)
        #expect(plan.destination.path == f.url("Output/Mixed.xcworkspace").path)

        try plan.write { $0 }
        #expect(try String(contentsOf: existing, encoding: .utf8) == "opaque project")
        #expect(f.exists("Output/Mixed.xcworkspace/contents.xcworkspacedata"))

        var only = Scenario()
        only.workspace("workspace", in: f.root)
        only.existingProject("existing", at: f.url("Vendor/Existing.xcodeproj"))
        let existingOnly = try only.plan()
        #expect(existingOnly.projectCount == 1 && existingOnly.targetCount == 0)
    }

    @Test(arguments: ["Missing.xcodeproj", "Regular.xcodeproj"])
    func existingProjectMustBeAnExistingDirectory(_ name: String) throws {
        let f = try Fixture()
        try f.file("Regular.xcodeproj", "not a bundle")
        var scenario = Scenario()
        scenario.workspace("workspace", in: f.root)
        scenario.existingProject("existing", at: f.url(name))
        expectFailure(containing: "existing:bundle") { _ = try scenario.plan() }
    }

    @Test func generatedProjectsCannotOverlapAnExistingProject() throws {
        let f = try Fixture()
        try f.directory("Vendor/Example.xcodeproj")
        var overwrite = Scenario()
        overwrite.workspace("workspace", in: f.root)
        overwrite.project("generated", in: f.url("Vendor"))
        overwrite.existingProject("existing", at: f.url("Vendor/Example.xcodeproj"))
        expectFailure(containing: "Existing project overlaps an output path") {
            _ = try overwrite.plan()
        }

        var twice = Scenario()
        twice.workspace("workspace", in: f.root)
        twice.existingProject("a", at: f.url("Vendor/Example.xcodeproj"))
        try f.symlink("Alias", to: "Vendor")
        twice.existingProject("b", at: f.url("Alias/Example.xcodeproj"))
        expectFailure(containing: "Duplicate existing project paths") { _ = try twice.plan() }
    }

    @Test func schemesAreWrittenIntoTheirOwnerAndMustReferenceRenderedTargets() throws {
        let f = try Fixture()
        var scenario = Scenario()
        scenario.project("root", in: f.root)
        scenario.scheme("App", in: "root")
        let plan = try scenario.plan(texts: ["App": scheme()])
        #expect(plan.files.filter(\.isScheme).count == 1 && plan.projectCount == 1)
        try plan.write { $0 }
        #expect(f.exists("Example.xcodeproj/xcshareddata/xcschemes/App.xcscheme"))

        expectFailure(containing: "unknown project or target") {
            _ = try scenario.plan(texts: ["App": scheme(id: "FFFFFFFFFFFFFFFFFFFFFFFF")])
        }
        expectFailure(containing: "unknown project or target") {
            _ = try scenario.plan(texts: ["App": scheme(container: "container:Other.xcodeproj")])
        }
        expectFailure(containing: "Invalid scheme buildable reference") {
            _ = try scenario.plan(texts: ["App": scheme(container: "absolute:/Example.xcodeproj")])
        }
    }

    @Test(arguments: [
        "<Workspace/>", "not xml",
        #"<!DOCTYPE Scheme [<!ENTITY x "y">]><Scheme>&x;</Scheme>"#,
    ])
    func malformedSchemeXMLIsRejected(_ text: String) throws {
        let f = try Fixture()
        var scenario = Scenario()
        scenario.project("root", in: f.root)
        scenario.scheme("App", in: "root")
        expectFailure(containing: "Invalid scheme XML") {
            _ = try scenario.plan(texts: ["App": text])
        }
    }

    @Test(arguments: ["App.xcscheme", "xcshareddata/xcschemes/App.txt"])
    func schemesOutsideTheSharedSchemesDirectoryAreRejected(_ file: String) throws {
        let f = try Fixture()
        var scenario = Scenario()
        scenario.project("root", in: f.root)
        scenario.scheme("App", in: "root", file: file)
        expectFailure(containing: "Invalid scheme filename") {
            _ = try scenario.plan(texts: ["App": scheme()])
        }
    }
}
