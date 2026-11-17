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
        let projectDirectory = type == .workspace ? "Projects/Core/" : ""
        let templateImport = type == .workspace ? "../../Templates.pkl" : "Templates.pkl"
        let project = """
            amends "@xcproj/Project.pkl"
            import "\(templateImport)" as Templates

            name = "Core"
            bundleIdPrefix = "com.example.core"
            targets {
              ["framework"] = new Templates.Framework {
                name = "Core"
                sources { new { path = "Sources" } }
              }
              ["tests"] = new Templates.UnitTests {
                name = "CoreTests"
                sources { new { path = "Tests" } }
                dependencies { new { target = "framework" } }
              }
            }
            """
        var files = [
            "PklProject": """
            amends "pkl:Project"

            dependencies {
              ["xcproj"] {
                uri = "\(ToolDefaults.packageURI)"
              }
            }
            """,
            "Main.pkl": type == .project
                ? project
                : #"""
                amends "@xcproj/Workspace.pkl"

                name = "Workspace"
                projects {
                  ["core"] = import("Projects/Core/Project.pkl")
                }
                """#,
            "Templates.pkl": #"""
            import "@xcproj/Project.pkl" as X

            open class BaseTarget extends X.Target {
              platform = "iOS"
              deploymentTarget = "17.0"
            }

            open class Framework extends BaseTarget { type = "framework" }
            open class UnitTests extends BaseTarget { type = "bundle.unit-test" }
            """#,
            "\(projectDirectory)Sources/Core.swift": """
            public enum Core {
                public static let greeting = "Hello, xcprojgen!"
            }
            """,
            "\(projectDirectory)Tests/CoreTests.swift": """
            import Core
            import XCTest

            final class CoreTests: XCTestCase {
                func testGreeting() {
                    XCTAssertEqual(Core.greeting, "Hello, xcprojgen!")
                }
            }
            """,
        ]
        if type == .workspace {
            files["Projects/Core/Project.pkl"] = project
        }
        return files
    }
}
