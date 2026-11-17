import Foundation

public enum PklRuntimeResources {
    public static let version = try! String(
        contentsOf: Bundle.module.url(
            forResource: "Version", withExtension: "txt", subdirectory: "Internal")!,
        encoding: .utf8
    ).trimmingCharacters(in: .whitespacesAndNewlines)

    public static var renderer: URL {
        Bundle.module.url(forResource: "Render", withExtension: "pkl", subdirectory: "Internal")!
    }

    public static var agentSkill: URL {
        Bundle.module.url(forResource: "xcprojgen", withExtension: nil, subdirectory: "Skills")!
    }
}
