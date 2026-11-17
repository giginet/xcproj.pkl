import Foundation

public enum InitializationType: String, CaseIterable, Sendable {
    case workspace
    case project
}

/// Writes a scaffold without invoking Pkl or reading the network.
public enum ProjectInitializer {
    public static func write(to directory: URL, type: InitializationType) throws {
        let files = templates(for: type)
        let manager = FileManager.default
        // Check every destination and ancestor before creating any files.
        for path in files.keys.sorted() {
            let destination = directory.appendingPathComponent(path)
            if (try? manager.attributesOfItem(atPath: destination.path)) != nil {
                throw ProjectError("Refusing to overwrite existing file: \(destination.path)")
            }
            var parent = destination.deletingLastPathComponent().standardizedFileURL
            while parent.path != "/" {
                var isDirectory: ObjCBool = false
                if manager.fileExists(atPath: parent.path, isDirectory: &isDirectory),
                    !isDirectory.boolValue
                {
                    throw ProjectError("Expected a directory: \(parent.path)")
                }
                parent = parent.deletingLastPathComponent().standardizedFileURL
            }
        }
        for path in files.keys.sorted() {
            let destination = directory.appendingPathComponent(path)
            try manager.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((files[path]! + "\n").utf8).write(
                to: destination, options: .withoutOverwriting)
        }
    }

    private static func templates(for type: InitializationType) -> [String: String] {
        let project = """
            name = "Core"
            bundleIdPrefix = "com.example.core"
            targets {
              ["framework"] = new Framework {
                name = "Core"
              }
              ["tests"] = new UnitTests {
                name = "CoreTests"
                dependencies { new { target = "framework" } }
              }
            }
            """
        let definition: String
        switch type {
        case .project:
            definition = project
        case .workspace:
            let nestedProject = project.split(separator: "\n").map { "    " + $0 }
                .joined(separator: "\n")
            definition = """
                name = "Workspace"
                projects {
                  ["core"] = new X {
                \(nestedProject)
                  }
                }
                """
        }
        let schema = type == .project ? "Project" : "Workspace"
        return [
            "PklProject": """
            amends "pkl:Project"

            dependencies {
              ["xcproj"] {
                uri = "\(ToolDefaults.packageURI)"
              }
            }
            """,
            "Project.pkl": """
            amends "@xcproj/\(schema).pkl"
            import "@xcproj/Project.pkl" as X

            local open class BaseTarget extends X.Target {
              platform = "iOS"
              deploymentTarget = "17.0"
            }

            local class Framework extends BaseTarget { type = "framework" }
            local class UnitTests extends BaseTarget { type = "bundle.unit-test" }

            \(definition)
            """,
        ]
    }
}
