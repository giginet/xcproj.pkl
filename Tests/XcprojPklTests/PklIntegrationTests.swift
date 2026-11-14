import Foundation
import Testing
import XcodeProjectFormat

@testable import XcprojPkl

@Suite(.enabled(if: hasPkl, "Set PKL_EXEC to run the real Pkl integration tests"))
struct NativePklTests {
    @Test func nativeClassesAmendmentsLateBindingAndProjection() throws {
        let f = try Fixture()
        try f.directory("Sources/Renamed")
        try f.file(
            "Settings.pkl",
            """
            import \(quoted(schema)) as X
            warnings: X.Settings = new { base { ["WARN"] = "YES" } }
            compiler = (warnings) { base { ["FLAGS"] = new Listing { "$(inherited)"; "-DBASE" } } }
            """)
        try f.file(
            "Templates.pkl",
            """
            import \(quoted(schema)) as X
            import "Settings.pkl" as Common
            open class Base extends X.Target {
              local target = this
              organization: String = "example"
              type = "tool"; platform = "macOS"
              sources { new { path = "Sources/\\(target.name)" } }
              settings = (Common.compiler) { base { ["DERIVED"] = "\\(target.organization).\\(target.name)" } }
            }
            original = new Base { name = "Original" }
            amended = (original) { name = "Renamed"; settings { base { ["FLAGS"] { "-DCHILD" } } } }
            """)
        let plan = try f.compile(
            """
            import "Templates.pkl" as T
            targets { ["stable"] = T.amended }
            """)
        let json = try #require(
            JSONSerialization.jsonObject(with: plan.projects[0].data) as? [String: Any])
        let targets = try #require(json["targets"] as? [[String: Any]])
        let settings = try #require(targets[0]["build-settings"] as? [String: Any])
        #expect(settings["WARN"] as? String == "YES")
        #expect(settings["DERIVED"] as? String == "example.Renamed")
        #expect(settings["FLAGS"] as? [String] == ["$(inherited)", "-DBASE", "-DCHILD"])
        #expect(!String(decoding: plan.projects[0].data, as: UTF8.self).contains("organization"))
        let original = try PklEvaluator().evaluate(
            f.root.appendingPathComponent("Templates.pkl"), expression: "original.name")
        #expect(
            String(decoding: original, as: UTF8.self).trimmingCharacters(
                in: .whitespacesAndNewlines)
                == "Original")
    }

    @Test func listingAppendAndReplacementAreNative() throws {
        let f = try Fixture()
        for path in ["One", "Two", "Only"] { try f.directory(path) }
        try f.file(
            "Templates.pkl",
            """
            import \(quoted(schema)) as X
            open class Base extends X.Target {
              type = "tool"; platform = "macOS"
              sources { new { path = "One" } }
            }
            """)
        let plan = try f.compile(
            """
            import "Templates.pkl" as T
            targets {
              ["append"] = new T.Base { name = "Append"; sources { new { path = "Two" } } }
              ["replace"] = new T.Base { name = "Replace"; sources = new Listing<Source> { new { path = "Only" } } }
            }
            """)
        let project = try XCSchema.Project(jsonRepresentation: plan.projects[0].data)
        let folders = project.topLevelReferences.compactMap { ref -> XCSchema.Folder? in
            if case .folder(let folder) = ref { return folder }
            return nil
        }
        #expect(folders.count == 3)
        #expect(folders.first { $0.path.path == "One" }?.targets.map(\.targetName) == ["Append"])
        #expect(folders.first { $0.path.path == "Only" }?.targets.map(\.targetName) == ["Replace"])
    }

    @Test func configurationPrecedenceAndXcodeMacros() throws {
        let f = try Fixture()
        let plan = try f.tool(
            """
            settings {
              base { ["SWIFT_OPTIMIZATION_LEVEL"] = "-Osize"; ["FLAGS"] = new Listing { "$(inherited)" } }
              configs { ["Debug"] { base { ["SPECIAL"] = "yes" } } }
            }
            """)
        let object = try #require(
            JSONSerialization.jsonObject(with: plan.projects[0].data) as? [String: Any])
        let targets = try #require(object["targets"] as? [[String: Any]])
        let settings = try #require(targets[0]["build-settings"] as? [String: Any])
        #expect(settings["SWIFT_OPTIMIZATION_LEVEL"] as? String == "-Osize")
        #expect(settings["SWIFT_OPTIMIZATION_LEVEL[config=Debug]"] == nil)
        #expect(settings["SPECIAL[config=Debug]"] as? String == "yes")
        #expect(settings["SDKROOT"] as? String == "macosx")
        #expect(settings["FLAGS"] as? [String] == ["$(inherited)"])
    }

    @Test func idsSurviveDisplayNameChangesAndExplicitIDsArePreserved() throws {
        let f = try Fixture()
        let first = try XCSchema.Project(jsonRepresentation: f.tool().projects[0].data)
        let second = try XCSchema.Project(
            jsonRepresentation: f.compile(
                """
                targets { ["app"] { name = "Renamed"; type = "tool"; platform = "macOS" } }
                """
            ).projects[0].data)
        #expect(
            first.targets[0].commonProperties.objectID
                == second.targets[0].commonProperties.objectID)
        let explicit = try f.tool(
            "id = \"abcdefabcdefabcdefabcdef\"; productId = \"123456123456123456123456\"")
        let target = try XCSchema.Project(jsonRepresentation: explicit.projects[0].data).targets[0]
        #expect(target.commonProperties.objectID.rawValue == "abcdefabcdefabcdefabcdef")
    }

    @Test(arguments: [
        (#"targetTemplates {}"#, "targetTemplates"),
        (#"schemaVersion = 1"#, "schemaVersion"),
        (#"kind = "workspace""#, "kind"),
        (#"targets { ["a"] { type = "tool"; platform = "macOS" } }"#, "name"),
        (
            #"targets { ["a"] { name = "A"; type = "tool"; platform = "iOS" } }"#,
            "tool requires macOS"
        ),
        (#"targets { ["a"] { name = "A"; type = "unit-test-bundle"; platform = "iOS" } }"#, "type"),
        (#"defaultConfiguration = "Missing""#, "defaultConfiguration"),
        (#"settings { configs { ["Typo"] {} } }"#, "Unknown build configuration"),
        (#"settings { base { ["SWIFT_VERSION"] = 6 } }"#, "SettingValue"),
        (
            #"targets { ["a"] { name = "A"; type = "tool"; platform = "macOS"; templateAttributes {} } }"#,
            "templateAttributes"
        ),
    ])
    func schemaErrorsHavePklDiagnostics(_ body: String, _ message: String) throws {
        let f = try Fixture()
        let prefix =
            body.contains("targets") || body.contains("defaultConfiguration")
            ? "" : #"targets { ["a"] { name = "A"; type = "tool"; platform = "macOS" } }"#
        expectFailure(containing: message) { _ = try f.compile(prefix + "\n" + body) }
    }

    @Test(arguments: ["missing", "cycle", "link", "embed", "platform", "duplicate", "conflict"])
    func graphAndDependencyErrors(_ kind: String) throws {
        let f = try Fixture()
        let a: String
        let b: String
        let message: String
        switch kind {
        case "missing":
            a = #"dependencies { new { target = "missing" } }"#
            b = ""
            message = "unknown dependency"
        case "cycle":
            a = #"dependencies { new { target = "b"; link = false } }"#
            b = #"dependencies { new { target = "a"; link = false } }"#
            message = "cycle"
        case "link":
            a = #"dependencies { new { target = "b" } }"#
            b = ""
            message = "only frameworks"
        case "embed":
            a = #"dependencies { new { target = "b"; link = false; embed = true } }"#
            b = ""
            message = "embedding"
        case "platform":
            a = #"dependencies { new { target = "b"; link = false } }"#
            b = #"platform = "iOS"; type = "bundle""#
            message = "different platform"
        case "duplicate":
            a = #"id = "AAAAAAAAAAAAAAAAAAAAAAAA""#
            b = #"id = "aaaaaaaaaaaaaaaaaaaaaaaa""#
            message = "Duplicate object ID"
        default:
            a =
                #"dependencies { new { target = "b"; link = false }; new { target = "b"; link = false; embed = true } }"#
            b = ""
            message = "conflicting dependency options"
        }
        let bType = kind == "platform" ? "" : #"type = "tool"; platform = "macOS";"#
        expectFailure(containing: message) {
            _ = try f.compile(
                """
                targets {
                  ["a"] { name = "A"; type = "tool"; platform = "macOS"; \(a) }
                  ["b"] { name = "B"; \(bType) \(b) }
                }
                """)
        }
    }

    @Test func sharedSymlinkSourcesMergeExclusionsAndRetainMemberships() throws {
        let f = try Fixture()
        try f.file("Sources/a.swift")
        try f.file("Sources/b.swift")
        try f.symlink("Alias", to: "Sources")
        let plan = try f.compile(
            #"""
            targets {
              ["a"] { name = "A"; type = "tool"; platform = "macOS"
                sources {
                  new { path = "Sources"; excludes { "a.swift" } }
                  new { path = "Alias"; excludes { "b.swift" } }
                }
              }
              ["b"] { name = "B"; type = "tool"; platform = "macOS"; sources { new { path = "Sources" } } }
            }
            """#)
        let project = try XCSchema.Project(jsonRepresentation: plan.projects[0].data)
        guard case .folder(let folder) = project.topLevelReferences[0] else {
            Issue.record("Expected folder")
            return
        }
        #expect(folder.targets.count == 2)
        #expect(folder.membershipExceptions.count == 1)
        let json = String(decoding: plan.projects[0].data, as: UTF8.self)
        #expect(json.contains("a.swift") && json.contains("b.swift"))
        #expect(!json.contains("Alias"))
    }

    @Test func sourceAndExclusionValidation() throws {
        let f = try Fixture()
        try f.directory("Sources/Nested")
        expectFailure(containing: "overlapping source roots") {
            _ = try f.tool(
                #"sources { new { path = "Sources" }; new { path = "Sources/Nested" } }"#)
        }
        expectFailure(containing: "Invalid folder exclusion") {
            _ = try f.tool(#"sources { new { path = "Sources"; excludes { "../wrong" } } }"#)
        }
        expectFailure(containing: "does not exist") {
            _ = try f.tool(#"sources { new { path = "Missing" } }"#)
        }
    }

    @Test func xcconfigAliasesUseOneStableReferenceAndOutputRebases() throws {
        let f = try Fixture()
        try f.file("Config/Debug.xcconfig")
        try f.symlink("Alias.xcconfig", to: "Config/Debug.xcconfig")
        let body = #"""
            configFiles { ["Debug"] = "Config/Debug.xcconfig" }
            targets { ["app"] { name = "App"; type = "tool"; platform = "macOS"; configFiles { ["Release"] = "Alias.xcconfig" } } }
            """#
        let moved = try f.compile(
            body, output: f.root.appendingPathComponent("Build/Moved.xcodeproj"))
        let project = try XCSchema.Project(jsonRepresentation: moved.projects[0].data)
        guard case .group(let group) = project.topLevelReferences[0] else {
            Issue.record("Expected Configurations")
            return
        }
        #expect(group.children.count == 1)
        guard case .fileReference(let file) = group.children[0] else {
            Issue.record("Expected file")
            return
        }
        #expect(file.path.path == "../Config/Debug.xcconfig")
        let original = try f.compile(body)
        let originalProject = try XCSchema.Project(jsonRepresentation: original.projects[0].data)
        #expect(originalProject.configurations[0].file == project.configurations[0].file)
    }

    @Test func folderAndIndividualFilePathsEscapeWithoutURLEncoding() throws {
        let f = try Fixture()
        try f.file("A & B <日本>/main.swift")
        let plan = try f.tool(
            #"sources { new { path = "A & B <日本>/main.swift"; kind = "file" } }"#,
            output: f.root.appendingPathComponent("Build/Example.xcodeproj"))
        let project = try XCSchema.Project(jsonRepresentation: plan.projects[0].data)
        guard case .fileReference(let file) = project.topLevelReferences[0] else {
            Issue.record("Expected file")
            return
        }
        #expect(file.path.path == "../A & B <日本>/main.swift")
        #expect(file.buildFiles.count == 1)
    }

    @Test func frameworkLinkAndEmbedProducesValidAppleModel() throws {
        let f = try Fixture()
        let plan = try f.compile(
            #"""
            targets {
              ["app"] { name = "App"; type = "application"; platform = "iOS"; dependencies { new { target = "core"; embed = true }; new { target = "core"; embed = true } } }
              ["core"] { name = "Core"; type = "framework"; platform = "iOS" }
              ["tests"] { name = "Tests"; type = "bundle.unit-test"; platform = "iOS"; dependencies { new { target = "core" } } }
            }
            """#)
        let project = try XCSchema.Project(jsonRepresentation: plan.projects[0].data)
        let app = try #require(project.targets.first { $0.name == "App" })
        #expect(app.commonProperties.dependencies.count == 1)
        #expect(app.commonProperties.buildPhases.contains { $0.kind == .copy })
        #expect(try ProjectValidator.validate(data: plan.projects[0].data) == 3)
    }

    @Test func writesOnlyChangesAndPreservesOtherBundleContents() throws {
        let f = try Fixture()
        let first = try f.tool()
        #expect(!FileManager.default.fileExists(atPath: first.destination.path))
        #expect(try first.write())
        try f.file("Example.xcodeproj/xcshareddata/keep.txt", "keep")
        let date = try first.projects[0].destination.resourceValues(forKeys: [
            .contentModificationDateKey
        ]).contentModificationDate
        let second = try f.tool()
        #expect(first.projects[0].data == second.projects[0].data)
        #expect(try !second.write())
        #expect(
            try second.projects[0].destination.resourceValues(forKeys: [.contentModificationDateKey]
            )
            .contentModificationDate == date)
        #expect(
            FileManager.default.fileExists(
                atPath: f.root.appendingPathComponent("Example.xcodeproj/xcshareddata/keep.txt")
                    .path))
        try f.file("Example.xcodeproj/project.pbxproj", "legacy")
        _ = try f.tool()  // validation remains independent of write preflight
        expectFailure(containing: "legacy project") { try second.write() }
    }

    @Test func sourceDiagnosticsAndReservedProperties() throws {
        let f = try Fixture()
        let source = try f.project(
            #"targets { ["a"] { name = "A"; type = "tool"; platform = "macOS" } }"#)
        expectFailure(containing: "reserved") {
            _ = try GenerationPlan.compile(
                source: source, properties: ["xcproj.internal.request=oops"])
        }
        expectFailure(containing: "key=value") {
            _ = try GenerationPlan.compile(source: source, properties: ["bad"])
        }
        expectFailure(containing: ".xcodeproj") {
            _ = try GenerationPlan.compile(
                source: source, output: f.root.appendingPathComponent("wrong.txt"))
        }
    }

    @Test func externalPropertiesAreFrozenBeforeRenderingAndUserModuleIsNotReevaluated() throws {
        let f = try Fixture()
        let source = try f.file(
            "Project.pkl",
            """
            amends \(quoted(schema))
            name = read("prop:display")
            targets {
              ["app"] {
                name = module.name
                type = "tool"; platform = "macOS"
                settings { base { ["EXTERNAL"] = read("prop:complex") } }
              }
            }
            """)
        let real = try #require(ProcessInfo.processInfo.environment["PKL_EXEC"])
        // Mutate the authoring file after evaluation 1. Render must use the frozen snapshot.
        let wrapper = try f.file(
            "pkl-wrapper",
            """
            #!/bin/sh
            \(shellQuoted(real)) "$@"
            result=$?
            for argument in "$@"; do input="$argument"; done
            if [ "$input" = \(shellQuoted(source.path)) ]; then
              printf 'invalid Pkl after snapshot\\n' > \(shellQuoted(source.path))
            fi
            exit "$result"
            """)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
        let plan = try GenerationPlan.compile(
            source: source, evaluator: PklEvaluator(executable: wrapper.path),
            properties: ["display=FlavorDebug", "complex=one=two"])
        #expect(plan.destination.lastPathComponent == "FlavorDebug.xcodeproj")
        let project = try XCSchema.Project(jsonRepresentation: plan.projects[0].data)
        #expect(project.targets[0].name == "FlavorDebug")
        #expect(String(decoding: plan.projects[0].data, as: UTF8.self).contains("one=two"))
        #expect(try String(contentsOf: source, encoding: .utf8).contains("invalid Pkl"))
    }

    @Test func optionalV1BaselineComparison() throws {
        guard let directory = ProcessInfo.processInfo.environment["XCPROJ_V1_BASELINE"] else {
            return
        }
        for name in ["Tool", "Demo"] {
            let source = repository.appendingPathComponent(
                name == "Tool" ? "Examples/Tool/Project.pkl" : "Examples/iOS/Project.pkl")
            let baseline = URL(fileURLWithPath: directory).appendingPathComponent(
                "\(name).xcodeproj/project.xcproj")
            let plan = try GenerationPlan.compile(
                source: source, output: baseline.deletingLastPathComponent())
            let old = try XCSchema.Project(jsonRepresentation: Data(contentsOf: baseline))
                .jsonRepresentation()
            let new = try XCSchema.Project(jsonRepresentation: plan.projects[0].data)
                .jsonRepresentation()
            #expect(old == new)
        }
        let workspace = try GenerationPlan.compile(
            source: repository.appendingPathComponent("Examples/Workspace/Workspace.pkl"))
        for file in workspace.projects {
            let baseline = URL(fileURLWithPath: directory).appendingPathComponent(
                file.bundle.deletingPathExtension().lastPathComponent + ".xcproj")
            let old = try XCSchema.Project(jsonRepresentation: Data(contentsOf: baseline))
                .jsonRepresentation()
            let new = try XCSchema.Project(jsonRepresentation: file.data).jsonRepresentation()
            #expect(old == new)
        }
    }
}
