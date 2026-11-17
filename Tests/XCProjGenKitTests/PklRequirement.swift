import Foundation
import Testing

@testable import XCProjGenKit

/// Fails, rather than skips, every test in scope when a supported Pkl is not installed.
/// Pkl is looked up exactly as xcprojgen does: PKL_EXEC, then `pkl` on PATH.
struct PklRequirement: TestTrait, SuiteTrait, TestScoping {
    static let installation = Result<PklTool.Installation, any Error> {
        let installation = try PklTool().installation()
        guard installation.isSupported else {
            throw ProjectError(
                "Pkl \(installation.version) at \(installation.executable.path) is unsupported; "
                    + "these tests require \(PklTool.minimumVersion) or later")
        }
        return installation
    }

    var isRecursive: Bool { true }

    func provideScope(
        for test: Test, testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        if case .failure(let error) = Self.installation {
            Issue.record("This test runs the real Pkl evaluator. \(error)")
            return
        }
        try await function()
    }
}

extension Trait where Self == PklRequirement {
    /// The test evaluates real Pkl modules and fails when Pkl is unavailable.
    static var requiresPkl: Self { Self() }
}
