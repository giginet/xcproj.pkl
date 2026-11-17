import Foundation

public enum PklRuntimeResources {
    public static var renderer: URL {
        Bundle.module.url(forResource: "Render", withExtension: "pkl", subdirectory: "Internal")!
    }

    public static var agentSkill: URL {
        Bundle.module.url(forResource: "xcprojgen", withExtension: nil, subdirectory: "Skills")!
    }
}
