import Foundation
import Testing

@testable import XcprojPkl

@Suite(.enabled(if: hasPkl, "Set PKL_EXEC to exercise shared scheme generation"))
struct SchemeTests {
    @Test func projectSchemeRendersActionsAndPreservesUnmanagedSchemes() throws {
        let fixture = try Fixture()
        let source = try fixture.project(
            #"""
            targets {
              ["app"] { name = "App"; type = "tool"; platform = "macOS" }
              ["tests"] { name = "Tests"; type = "bundle.unit-test"; platform = "macOS" }
              ["all"] { name = "All"; kind = "aggregate" }
            }
            schemes {
              ["Development"] {
                build {
                  targets { new { target = "app" }; new { target = "tests"; forRunning = false }; new { target = "all" } }
                  preActions { new { title = "Prepare"; script = "echo 'before & after'"; environmentTarget = "app" } }
                  postActions { new { script = "echo first\necho second" } }
                }
                run = new { target = "app"; arguments { "--name=one & two" }; environment { ["MODE"] = "test < debug" } }
                test = new { targets { new { target = "tests"; parallelizable = true } }; codeCoverage = true }
                profile = new { target = "app" }
                analyze = new {}
                archive = new { revealArchiveInOrganizer = false }
              }
            }
            """#)
        let output = fixture.root.appendingPathComponent("Relocated")
        let plan = try GenerationPlan.compile(source: source, outputDirectory: output)
        let scheme = try #require(plan.files.first { $0.isScheme })
        #expect(scheme.bundle == plan.destination)
        #expect(
            scheme.destination.path.hasSuffix(
                "Example.xcodeproj/xcshareddata/xcschemes/Development.xcscheme"))
        let xml = try XMLDocument(data: scheme.data)
        #expect(
            try xml.nodes(forXPath: "/Scheme/BuildAction/BuildActionEntries/BuildActionEntry").count
                == 3)
        #expect(
            try xml.nodes(
                forXPath: "/Scheme/LaunchAction/CommandLineArguments/CommandLineArgument/@argument"
            ).first?.stringValue == "--name=one & two")
        #expect(
            try xml.nodes(
                forXPath: "/Scheme/LaunchAction/EnvironmentVariables/EnvironmentVariable/@value"
            ).first?.stringValue == "test < debug")
        #expect(
            try xml.nodes(
                forXPath: "/Scheme/BuildAction/PreActions/ExecutionAction/ActionContent/@scriptText"
            ).first?.stringValue == "echo 'before & after'")
        #expect(
            try xml.nodes(
                forXPath:
                    "/Scheme/BuildAction/PostActions/ExecutionAction/ActionContent/@scriptText"
            ).first?.stringValue == "echo first\necho second")
        #expect(
            try xml.nodes(forXPath: "/Scheme/TestAction/@codeCoverageEnabled").first?.stringValue
                == "YES")
        #expect(
            try xml.nodes(forXPath: "/Scheme/ProfileAction/@buildConfiguration").first?.stringValue
                == "Release")
        #expect(
            try xml.nodes(forXPath: "/Scheme/AnalyzeAction/@buildConfiguration").first?.stringValue
                == "Debug")
        #expect(
            try xml.nodes(forXPath: "/Scheme/ArchiveAction/@revealArchiveInOrganizer").first?
                .stringValue == "NO")
        #expect(
            try xml.nodes(forXPath: "//BuildableReference/@ReferencedContainer").allSatisfy {
                $0.stringValue == "container:Example.xcodeproj"
            })
        let unmanaged = try fixture.file(
            "Relocated/Example.xcodeproj/xcshareddata/xcschemes/Manual.xcscheme", "keep")
        let personal = try fixture.file(
            "Relocated/Example.xcodeproj/xcuserdata/person.xcuserdatad/xcschemes/Personal.xcscheme",
            "personal")
        #expect(try plan.write())
        #expect(try !plan.write())
        #expect(try String(contentsOf: unmanaged, encoding: .utf8) == "keep")
        #expect(try String(contentsOf: personal, encoding: .utf8) == "personal")
        let next = try GenerationPlan.compile(source: source, outputDirectory: output)
        #expect(plan.files.map(\.data) == next.files.map(\.data))
    }

    @Test func workspaceSchemeUsesRelocatedContainerAndProjectTargetIDs() throws {
        let fixture = try Fixture()
        for name in ["A", "B"] {
            try fixture.project(
                "targets { [\"app\"] { name = \"\(name)\"; type = \"tool\"; platform = \"macOS\" } }",
                at: "\(name)/Project.pkl")
        }
        let source = try fixture.file(
            "Main.pkl",
            """
            amends \(quoted(workspaceSchema))
            name = "Together"
            projects { ["Modules/Core/Project.pkl"] = import("A/Project.pkl"); ["b"] = import("B/Project.pkl") }
            schemes {
              ["All"] {
                build { targets { new { target = "Modules/Core/Project.pkl/app" }; new { target = "b/app" } } }
                run = new { target = "b/app" }
              }
            }
            """)
        let plan = try GenerationPlan.compile(
            source: source, outputDirectory: fixture.root.appendingPathComponent("Generated"))
        let scheme = try #require(plan.files.first { $0.isScheme })
        let xml = try XMLDocument(data: scheme.data)
        let containers = try xml.nodes(forXPath: "//BuildableReference/@ReferencedContainer")
            .compactMap(\.stringValue)
        #expect(
            Set(containers) == [
                "container:../A/Example.xcodeproj", "container:../B/Example.xcodeproj",
            ])
        #expect(
            scheme.destination.path.hasSuffix(
                "Generated/Together.xcworkspace/xcshareddata/xcschemes/All.xcscheme"))
        try plan.write()
    }

    @Test(arguments: ["target", "configuration", "test-type", "name"])
    func invalidSchemesAreRejectedBeforeWriting(_ kind: String) throws {
        let fixture = try Fixture()
        let scheme: String
        let expected: String
        switch kind {
        case "target":
            scheme = #"["Dev"] { build { targets { new { target = "missing" } } } }"#
            expected = "unknown target"
        case "configuration":
            scheme =
                #"["Dev"] { build { targets { new { target = "app" } } }; run = new { target = "app"; configuration = "Missing" } }"#
            expected = "unknown configuration"
        case "test-type":
            scheme =
                #"["Dev"] { build { targets { new { target = "app" } } }; test = new { targets { new { target = "app" } } } }"#
            expected = "must be a test bundle"
        default:
            scheme = #"["../Outside"] { build { targets { new { target = "app" } } } }"#
            expected = "Invalid scheme name"
        }
        expectFailure(containing: expected) {
            _ = try fixture.compile(
                "targets { [\"app\"] { name = \"App\"; type = \"tool\"; platform = \"macOS\" } }\nschemes { \(scheme) }"
            )
        }
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.root.appendingPathComponent("Example.xcodeproj").path))
    }

    @Test func projectSchemeResolvesLocalTargetKeysContainingSlashes() throws {
        let fixture = try Fixture()
        let plan = try fixture.compile(
            #"""
            targets { ["tools/app"] { name = "App"; type = "tool" } }
            schemes {
              ["Dev"] {
                build { targets { new { target = "tools/app" } } }
                run = new { target = "tools/app" }
              }
            }
            """#)
        let scheme = try #require(plan.files.first { $0.isScheme })
        let xml = try XMLDocument(data: scheme.data)
        #expect(
            try xml.nodes(forXPath: "//BuildableReference/@BlueprintName").allSatisfy {
                $0.stringValue == "App"
            })
    }

    @Test func workspaceSchemeRejectsAmbiguousProjectAndTargetKeyBoundaries() throws {
        let fixture = try Fixture()
        try fixture.project(
            #"targets { ["b/app"] { name = "One"; type = "tool" } }"#,
            at: "A/Project.pkl")
        try fixture.project(
            #"targets { ["app"] { name = "Two"; type = "tool" } }"#,
            at: "B/Project.pkl")
        let source = try fixture.file(
            "Main.pkl",
            """
            amends \(quoted(workspaceSchema))
            name = "Ambiguous"
            projects { ["a"] = import("A/Project.pkl"); ["a/b"] = import("B/Project.pkl") }
            schemes { ["Dev"] { build { targets { new { target = "a/b/app" } } } } }
            """)
        expectFailure(containing: "ambiguous target reference") {
            _ = try GenerationPlan.compile(source: source)
        }
    }

    @Test(arguments: [#"type = "application""#, #"fullProductType = "com.example.custom-product""#])
    func explicitProductReferencesRequireAndUseTheProductFilename(_ productType: String) throws {
        let fixture = try Fixture()
        let body = """
            files {
              new Group {
                name = "Products"
                children { new FileReference { path = "<PRODUCTS>/Custom.app"; type = "wrapper.application" } }
              }
            }
            targets {
              ["app"] {
                name = "App"
                \(productType)
                product = "Products/Custom.app"
                settings { base { ["PRODUCT_NAME"] = "Custom" } }
              }
            }
            schemes {
              ["Dev"] {
                build { targets { new { target = "app" } } }
                run = new { target = "app" }
              }
            }
            """
        expectFailure(containing: "explicit product reference requires productName") {
            _ = try fixture.compile(body)
        }
        let plan = try fixture.compile(
            body.replacingOccurrences(
                of: #"name = "App""#, with: #"name = "App"; productName = "Custom.app""#))
        let scheme = try #require(plan.files.first { $0.isScheme })
        let xml = try XMLDocument(data: scheme.data)
        #expect(
            try xml.nodes(forXPath: "//BuildableReference/@BuildableName").allSatisfy {
                $0.stringValue == "Custom.app"
            })
        #expect(
            try xml.nodes(forXPath: "//BuildableReference/@BlueprintName").allSatisfy {
                $0.stringValue == "App"
            })
    }
}
