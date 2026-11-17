import Foundation
import PklRuntimeResources
import Testing

@testable import XCProjGenKit

/// GenerationPlan.compile against a stubbed pkl process.
struct CompileTests {
    private func project(_ f: Fixture) throws -> (scenario: Scenario, source: URL) {
        var scenario = Scenario()
        scenario.project("root", in: f.root)
        return (scenario, try f.file("Main.pkl"))
    }

    @Test func entryIsFrozenThenRenderedByTheBundledRenderer() throws {
        let f = try Fixture()
        let (scenario, source) = try project(f)
        let frozen = try scenario.snapshot()
        let pkl = PklStub { call in
            guard call.arguments.contains("renderPlanText") else { return frozen }
            // The renderer reads the frozen Snapshot, never the user's module.
            #expect(try call.file("xcproj.internal.request") == frozen)
            return try Scenario.rendered(
                snapshot: frozen, facts: call.file("xcproj.internal.hostFacts"))
        }
        let plan = try GenerationPlan.compile(
            source: source, tool: pkl.tool, properties: ["team=ABC"])

        #expect(plan.projectCount == 1 && plan.targetCount == 1)
        #expect(plan.destination.path == f.url("Example.xcodeproj").path)
        #expect(plan.projects[0].destination.path == f.url("Example.xcodeproj/project.xcproj").path)
        #expect(!f.exists("Example.xcodeproj"), "compile must not write")

        let calls = pkl.calls
        try #require(calls.count == 2)
        #expect(calls[0].source == source.path && calls[0].properties == ["team=ABC"])
        #expect(calls[0].workingDirectory?.path == f.root.path)
        #expect(calls[1].source == PklRuntimeResources.renderer.path)
        // External properties are evaluated once; the renderer receives only internal ones.
        #expect(calls[1].properties.allSatisfy { $0.hasPrefix("xcproj.internal.") })
    }

    @Test func outputDirectoryRelocatesTheRootBundle() throws {
        let f = try Fixture()
        let (scenario, source) = try project(f)
        let plan = try GenerationPlan.compile(
            source: source, tool: try PklStub.rendering(scenario).tool,
            outputDirectory: f.url("Out"))
        #expect(plan.destination.path == f.url("Out/Example.xcodeproj").path)
    }

    @Test(arguments: [
        "Type constraint `!isEmpty` violated.\nValue: \"\"",
        "Unknown dependency target 'missing' in target 'app'",
        "Target dependency cycle: a → b → a",
    ])
    func evaluationDiagnosticsAreReportedAndRenderingIsSkipped(_ diagnostic: String) throws {
        let f = try Fixture()
        let source = try f.file("Main.pkl")
        let pkl = PklStub { _ in throw PklStub.failure(diagnostic) }
        expectFailure(containing: diagnostic) {
            _ = try GenerationPlan.compile(source: source, tool: pkl.tool)
        }
        #expect(pkl.calls.count == 1)
    }

    @Test(arguments: [
        "Scheme 'App' references unknown target 'missing'",
        "app: only frameworks can be linked",
        "Duplicate workspace/project output paths",
    ])
    func rendererDiagnosticsAreReported(_ diagnostic: String) throws {
        let f = try Fixture()
        let (scenario, source) = try project(f)
        let frozen = try scenario.snapshot()
        let pkl = PklStub { call in
            if call.arguments.contains("renderPlanText") { throw PklStub.failure(diagnostic) }
            return frozen
        }
        expectFailure(containing: diagnostic) {
            _ = try GenerationPlan.compile(source: source, tool: pkl.tool)
        }
        #expect(pkl.calls.count == 2)
        #expect(!f.exists("Example.xcodeproj"))
    }

    @Test func unexpectedPklOutputIsRejected() throws {
        let f = try Fixture()
        let (scenario, source) = try project(f)
        let notJSON = PklStub { _ in Data("not json".utf8) }
        #expect(throws: (any Error).self) {
            _ = try GenerationPlan.compile(source: source, tool: notJSON.tool)
        }
        #expect(notJSON.calls.count == 1)

        // A rendered plan for a different Snapshot must not be accepted.
        var other = Scenario()
        other.project("other", in: f.root, name: "Other")
        let frozen = try scenario.snapshot()
        let otherPlan = try Scenario.rendered(
            snapshot: other.snapshot(),
            facts: JSONEncoder().encode(HostFacts.observe(other.manifest())))
        let mismatched = PklStub { call in
            call.arguments.contains("renderPlanText") ? otherPlan : frozen
        }
        expectFailure(containing: "does not match Snapshot artifacts") {
            _ = try GenerationPlan.compile(source: source, tool: mismatched.tool)
        }
    }

    @Test func invalidInputsDoNotInvokePkl() throws {
        let f = try Fixture()
        let source = try f.file("Main.pkl")
        let pkl = PklStub { _ in Data() }
        expectFailure(containing: "Expected --property key=value") {
            _ = try GenerationPlan.resolveAndCompile(
                source: source, tool: pkl.tool, properties: ["=oops"])
        }
        expectFailure(containing: "Expected --property key=value") {
            _ = try GenerationPlan.compile(source: source, tool: pkl.tool, properties: ["oops"])
        }
        expectFailure(containing: "reserved") {
            _ = try GenerationPlan.resolveAndCompile(
                source: source, tool: pkl.tool, properties: ["xcproj.internal.request=bad"])
        }
        expectFailure(containing: "file does not exist") {
            _ = try GenerationPlan.compile(source: f.url("Missing.pkl"), tool: pkl.tool)
        }
        try f.directory("Directory.pkl")
        expectFailure(containing: "file does not exist") {
            _ = try GenerationPlan.compile(source: f.url("Directory.pkl"), tool: pkl.tool)
        }
        #expect(pkl.calls.isEmpty)
    }

    @Test func dependenciesAreResolvedForTheEnclosingPklProjectFirst() throws {
        let f = try Fixture()
        try f.file("PklProject")
        var scenario = Scenario()
        scenario.project("root", in: f.url("Projects/Core"), name: "Core")
        let source = try f.file("Projects/Core/Project.pkl")
        let pkl = try PklStub.rendering(scenario)
        _ = try GenerationPlan.resolveAndCompile(
            source: source, tool: pkl.tool, properties: ["team=ABC"])

        let calls = pkl.calls
        #expect(calls.map(\.command) == ["project", "eval", "eval"])
        #expect(calls[0].arguments.starts(with: ["project", "resolve"]))
        #expect(calls[0].source == f.root.path && calls[0].properties == ["team=ABC"])
    }

    @Test func modulesOutsideAPklProjectSkipDependencyResolution() throws {
        let f = try Fixture()
        let (scenario, source) = try project(f)
        let pkl = try PklStub.rendering(scenario)
        _ = try GenerationPlan.resolveAndCompile(source: source, tool: pkl.tool)
        #expect(pkl.calls.map(\.command) == ["eval", "eval"])
    }

    @Test func dependencyResolutionFailureStopsBeforeEvaluation() throws {
        let f = try Fixture()
        try f.file("PklProject")
        let source = try f.file("Main.pkl")
        let diagnostic = "Cannot download package `package://example.com/xcproj@0.1.0`"
        let pkl = PklStub { _ in
            throw PklStub.failure(diagnostic, operation: "dependency resolution")
        }
        expectFailure(containing: diagnostic) {
            _ = try GenerationPlan.resolveAndCompile(source: source, tool: pkl.tool)
        }
        #expect(pkl.calls.map(\.command) == ["project"])
    }
}
