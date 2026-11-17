import ArgumentParser
import Foundation
import XCProjGenKit

struct UpdatePackage: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update-package",
        abstract: "Update the xcproj dependency in PklProject and resolve the lockfile."
    )

    @Argument(help: "Directory containing PklProject. Defaults to the current directory.")
    var dir: String = "."

    @Option(help: "Package release version. Defaults to the running CLI version.")
    var to: String?

    @OptionGroup var runtime: PklOptions

    func run() throws {
        let version = to ?? ToolDefaults.version
        let directory = URL(fileURLWithPath: dir).standardizedFileURL
        print(try PackageUpdater.update(in: directory, to: version, using: runtime.tool))
        if version != ToolDefaults.version {
            print(
                "Package \(version) differs from CLI \(ToolDefaults.version). Run xcprojgen validate to check compatibility."
            )
        }
    }
}
