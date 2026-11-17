import ArgumentParser
import Foundation
import XCProjGenKit

struct Skills: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Export the bundled xcprojgen agent skill.",
        subcommands: [ExportSkills.self]
    )
}

struct ExportSkills: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Save the xcprojgen skill, overwriting changed bundled files."
    )

    @Argument(help: "Parent directory for the xcprojgen skill folder.")
    var outputDir: String

    mutating func run() throws {
        let directory = URL(fileURLWithPath: outputDir).standardizedFileURL
        let result = try AgentSkills.export(to: directory)
        print(
            "\(result.rawValue) agent skill: \(directory.appendingPathComponent(AgentSkills.name).path)"
        )
    }
}
