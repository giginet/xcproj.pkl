import Foundation
import Testing
import XcodeProjectFormat

@testable import XCProjGenKit

@Suite(.enabled(if: hasPkl, "Set PKL_EXEC to test the typed Xcode schema"))
struct SchemaModelTests {
    @Test(arguments: [false, true])
    func nonNativeProjectsDoNotRequireAnAutomaticProductsGroup(_ customGroup: Bool) throws {
        let fixture = try Fixture()
        let plan = try fixture.compile(
            #"""
            targets {
              ["all"] { name = "All"; kind = "aggregate" }
              ["external"] {
                name = "External"; kind = "external-build-system"; buildToolPath = "/usr/bin/true"
              }
            }
            """#
                + (customGroup
                    ? #"productsGroup = "Artifacts"; files { new Group { name = "Artifacts" } }"#
                    : ""))
        let project = try decode(plan)
        #expect(project.targets.map(\.kind) == [.aggregate, .externalBuildSystem])
        #expect(project.targets.allSatisfy { $0.commonProperties.product == nil })
        if customGroup {
            #expect(project.productsGroup?.description == "Artifacts")
            #expect(project.topLevelReferences.count == 1)
        } else {
            #expect(project.productsGroup == nil)
            #expect(project.topLevelReferences.isEmpty)
        }
    }

    @Test(arguments: [
        "extensionkit-extension", "system-extension", "driver-extension", "kernel-extension",
    ])
    func extensionProductsWithOtherDestinationsRequireAnExplicitCopyPhase(_ type: String) throws {
        let fixture = try Fixture()
        expectFailure(containing: "embedding") {
            _ = try fixture.compile(
                """
                targets {
                  ["app"] {
                    name = "App"; type = "application"
                    dependencies { new { target = "extension"; link = false; embed = true } }
                  }
                  ["extension"] { name = "Extension"; type = \(quoted(type)) }
                }
                """)
        }
    }

    @Test func fileTreeExceptionsAndBuildRulesSurviveAppleDecoding() throws {
        let fixture = try Fixture()
        let plan = try fixture.compile(
            #"""
            files {
              new FileReference {
                path = "<PROJECT>/main.swift"; id = "source-file"
                type = "sourcecode.swift"; signature = "AppleDevelopment:Example"
                encoding = 99; lineEnding = "line-feed"; index = false
                targetMembership {
                  new ProjectBuildFile {
                    id = "source-membership"; buildPhase = "Tool/compile-sources"
                    platforms { "macos" }; arguments = "-DDEMO"; assetTags { "Initial" }
                    headerRole = "public"; machInterfaceGeneration = "both"
                    isWeak = true; codeSignOnCopy = true; codeGeneration = "skip"
                    headerPreservation = "remove-on-copy"; decompress = true
                    codeGenerationVisibility = "project"
                  }
                }
              }
              new Folder {
                path = "<PROJECT>/Sources"; id = "sources-folder"; index = true
                targetMembership { "Tool" }
                fileTypes { ["custom.txt"] = "text" }; opaqueFolders { "Generated" }
                membershipExceptions {
                  new TargetExceptionSet {
                    target = "Tool"; members { "Skipped.swift" }
                    publicHeaders { "Public.h" }; privateHeaders { "Private.h" }
                    compilerFlags { ["file.c"] = "-Wall" }
                    platforms { ["file.c"] { "macos" } }
                    attributes { ["Public.h"] { codeGeneration = "skip" } }
                    assetTags { ["image.png"] { "Initial" } }
                  }
                  new BuildPhaseExceptionSet {
                    buildPhase = "Tool/resources"; members { "Image.png" }
                  }
                }
              }
              new Group {
                name = "Extras/Utilities"; id = "extras-group"
                children { new FileReference { path = "Extra.txt" } }
              }
              new VariantGroup {
                name = "Localizable.strings"; id = "strings-group"
                targetMembership { "Tool/resources" }
                children { new FileReference { path = "en.lproj/Localizable.strings" } }
              }
              new VersionGroup {
                path = "Model.xcdatamodeld"; id = "model-group"
                type = "wrapper.xcdatamodel"; currentVersion = "Model.xcdatamodel"
                targetMembership { "Tool/resources" }
                children { new FileReference { path = "Model.xcdatamodel" } }
              }
              new FileReference { path = "Remote.xcodeproj"; id = "remote-project" }
            }
            importedProducts {
              new ImportedProduct {
                project = "Remote.xcodeproj"; target = "Library"
                productId = "remote-library-product"; path = "Library.framework"
                type = "wrapper.framework"; targetMembership { "Tool/frameworks" }
              }
            }
            targets {
              ["tool"] {
                name = "Tool"; type = "tool"
                targetDependencies {
                  new RemoteTargetDependency {
                    project = "id:remote-project"; target = "Library"
                    targetId = "remote-library"; platforms { "macos" }
                  }
                }
                buildRules {
                  new BuildRule {
                    id = "custom-rule"; name = "Compile Text"; fileType = "text"
                    filePatterns = "*.txt"; script = "cat input > output"
                    inputFiles { "input" }; inputFileLists { "inputs.xcfilelist" }
                    outputFiles { "output" }; outputFileLists { "outputs.xcfilelist" }
                    outputFilesCompilerFlags { "-Wall" }; dependencyFile = "deps.d"
                    runOncePerArchitecture = false
                  }
                }
              }
            }
            """#)
        let project = try decode(plan)
        #expect(project.importedProducts.count == 1)
        #expect(project.importedProducts.first?.productID.rawValue == "remote-library-product")
        let sourceFiles = project.topLevelReferences.compactMap {
            reference -> XCSchema.FileReference? in
            if case .fileReference(let file) = reference,
                file.objectID?.rawValue == "source-file"
            {
                return file
            }
            return nil
        }
        let source = try #require(sourceFiles.first)
        #expect(source.textEncoding?.rawValue.rawValue == 99)
        #expect(source.lineEnding == .lineFeed)
        #expect(source.commonProperties.includeInIndex == false)
        #expect(source.expectedSignature == "AppleDevelopment:Example")
        let buildFile = try #require(source.buildFiles.first)
        #expect(buildFile.objectID?.rawValue == "source-membership")
        #expect(buildFile.properties.additionalBuildFlags == "-DDEMO")
        #expect(buildFile.properties.attributes.headerRole == .public)
        #expect(buildFile.properties.attributes.machInterfaceGeneration == .both)
        #expect(buildFile.properties.attributes.isWeak)
        #expect(buildFile.properties.attributes.codeSignOnCopy)
        #expect(buildFile.properties.attributes.codeGeneration == .skip)
        #expect(buildFile.properties.attributes.headerPreservation == .removeOnCopy)
        #expect(buildFile.properties.attributes.decompress)
        #expect(buildFile.properties.attributes.codeGenerationVisibility == .project)
        let folders = project.topLevelReferences.compactMap { reference -> XCSchema.Folder? in
            if case .folder(let folder) = reference { return folder }
            return nil
        }
        let folder = try #require(folders.first)
        #expect(folder.explicitOpaqueFolders.contains { $0.value == "Generated" })
        #expect(folder.explicitFileTypes.count == 1)
        #expect(folder.membershipExceptions.count == 2)
        if case .target(let exceptions) = folder.membershipExceptions[0] {
            #expect(exceptions.commonProperties.sense == .exclusions)
            #expect(exceptions.publicHeaders.contains { $0.value == "Public.h" })
            #expect(exceptions.privateHeaders.contains { $0.value == "Private.h" })
            #expect(exceptions.additionalCompilerFlags.count == 1)
            #expect(exceptions.commonProperties.platformFiltersByFolderMemberID.count == 1)
            #expect(exceptions.commonProperties.attributesByFolderMemberID.count == 1)
            #expect(exceptions.commonProperties.assetTagsByFolderMemberID.count == 1)
        } else {
            Issue.record("Expected a target exception set")
        }
        if case .buildPhase(let exceptions) = folder.membershipExceptions[1] {
            #expect(exceptions.commonProperties.sense == .inclusions)
        } else {
            Issue.record("Expected a build phase exception set")
        }
        #expect(
            project.topLevelReferences.contains {
                if case .group(let group) = $0 { return group.name == "Extras/Utilities" }
                return false
            })
        #expect(
            project.topLevelReferences.contains {
                if case .variantGroup = $0 { return true }
                return false
            })
        #expect(
            project.topLevelReferences.contains {
                if case .versionGroup = $0 { return true }
                return false
            })
        let target = try #require(project.targets.first?.commonProperties)
        let rule = try #require(target.buildRules.first)
        #expect(rule.objectID?.rawValue == "custom-rule")
        #expect(rule.script == "cat input > output")
        #expect(rule.inputFiles == ["input"])
        #expect(rule.inputFileLists == ["inputs.xcfilelist"])
        #expect(rule.outputFiles == ["output"])
        #expect(rule.outputFileLists == ["outputs.xcfilelist"])
        #expect(rule.outputFilesCompilerFlags == ["-Wall"])
        #expect(rule.dependencyFile == "deps.d")
        #expect(!rule.runOncePerArchitecture)
        if case .remoteTarget(let remote, let platforms) = try #require(target.dependencies.first) {
            #expect(remote.targetID.rawValue == "remote-library")
            #expect(platforms.contains { $0.rawValue == "macos" })
        } else {
            Issue.record("Expected a remote target dependency")
        }
    }

    @Test func packageConstraintsTraitsProductsAndPluginsArePreserved() throws {
        let fixture = try Fixture()
        try fixture.file("Packages/Local/Package.swift", "// swift-tools-version: 6.0\n")
        let constraints: [(kind: String, value: String, maximum: String?)] = [
            ("revision", "abcdef0123456789", nil), ("branch", "main", nil),
            ("version", "1.2.3", nil), ("version-range", "1.2.3", "2.0.0"),
            ("up-to-next-minor-version", "1.2.3", nil),
            ("up-to-next-major-version", "1.2.3", nil),
        ]
        let entries = constraints.enumerated().map { index, constraint in
            """
            ["alias\(index)"] = new RemoteSwiftPackage {
              repository = "https://example.com/Package\(index).git"
              traits { "Feature\(index)" }
              version { kind = \(quoted(constraint.kind)); value = \(quoted(constraint.value)); \(constraint.maximum.map { "maximum = \(quoted($0))" } ?? "") }
            }
            """
        }.joined(separator: "\n")
        let plan = try fixture.compile(
            """
            packages {
              \(entries)
              ["localAlias"] = new LocalSwiftPackage { path = "Packages/Local"; traits { "LocalFeature" } }
            }
            targets {
              ["tool"] {
                name = "Tool"; type = "tool"
                dependencies {
                  new { package = "alias0"; product = "RemoteLibrary"; platforms { "macos" } }
                  new { package = "localAlias"; product = "LocalLibrary" }
                  new { package = "alias1"; product = "FormatterPlugin"; productType = "build-tool-plugin"; link = false }
                }
                packageProductMembers {
                  new PackageProductMember { package = "Package2"; productName = "WeakLibrary"; buildPhase { isWeak = true; platforms { "macos" } } }
                }
              }
            }
            """,
            outputDirectory: fixture.root.appendingPathComponent("Generated/Nested"))
        let project = try decode(plan)
        #expect(project.packages.count == 7)
        let remotes = project.packages.compactMap { package -> XCSchema.RemoteSwiftPackage? in
            if case .remote(let remote) = package.location { return remote }
            return nil
        }
        #expect(remotes.count == 6)
        #expect(remotes.contains { $0.versionConstraint == .revision("abcdef0123456789") })
        #expect(remotes.contains { $0.versionConstraint == .branch("main") })
        #expect(remotes.contains { $0.versionConstraint == .version("1.2.3") })
        #expect(
            remotes.contains { $0.versionConstraint == .versionRange(min: "1.2.3", max: "2.0.0") })
        #expect(remotes.contains { $0.versionConstraint == .upToNextMinorVersion("1.2.3") })
        #expect(remotes.contains { $0.versionConstraint == .upToNextMajorVersion("1.2.3") })
        #expect(project.packages.allSatisfy { $0.traits.count == 1 })
        let locals = project.packages.compactMap { package -> XCSchema.LocalSwiftPackage? in
            if case .local(let local) = package.location { return local }
            return nil
        }
        let local = try #require(locals.first)
        let localURL = URL(
            fileURLWithPath: local.path, relativeTo: plan.destination.deletingLastPathComponent())
        #expect(
            canonicalFileURL(localURL).path
                == canonicalFileURL(fixture.root.appendingPathComponent("Packages/Local")).path)
        let target = try #require(project.targets.first?.commonProperties)
        let products = target.dependencies.compactMap {
            dependency -> XCSchema.SwiftPackageProductReference? in
            if case .package(let product, _) = dependency { return product }
            return nil
        }
        #expect(
            products.contains {
                $0.package?.packageName == "Package0" && $0.productName == "RemoteLibrary"
            })
        #expect(
            products.contains {
                $0.package?.packageName == "Local" && $0.productName == "LocalLibrary"
            })
        #expect(
            products.contains {
                $0.productName == "FormatterPlugin" && $0.productType == .buildToolPlugin
            })
        let members = target.packageProductTargetMembers
        #expect(members.contains { $0.packageProduct.productName == "RemoteLibrary" })
        #expect(!members.contains { $0.packageProduct.productName == "FormatterPlugin" })
        let weak = try #require(members.first { $0.packageProduct.productName == "WeakLibrary" })
        #expect(weak.buildFile.properties.attributes.isWeak)
    }

    @Test func phaseOrderAndAllScriptPropertiesArePreserved() throws {
        let fixture = try Fixture()
        let plan = try fixture.compile(
            #"""
            targets {
              ["tool"] {
                name = "Tool"; type = "tool"
                preBuildScripts { new { name = "Before"; script = "echo before" } }
                buildPhases {
                  new StandardBuildPhase { kind = "compile-sources" }
                  new ScriptBuildPhase {
                    id = "middle-script"; name = "Middle"; shell = "/bin/zsh"
                    script = "echo first\necho second"; logEnvironmentVariables = true
                    inputPaths { "$(SRCROOT)/Input.txt" }
                    inputFileListPaths { "Inputs.xcfilelist" }
                    outputPaths { "$(DERIVED_FILE_DIR)/Output.txt" }
                    outputFileListPaths { "Outputs.xcfilelist" }
                    dependencyFile = "$(DERIVED_FILE_DIR)/deps.d"
                    runOnEveryBuild = true; scope = "install"
                  }
                  new CopyFilesBuildPhase { name = "Copy"; bundleBasePath = "shared-support-directory"; relativePath = "Data"; scope = "install" }
                  new AppleScriptBuildPhase { name = "AppleScript"; isSharedContext = true; contextName = "Shared" }
                  new StandardBuildPhase { kind = "java-archive" }
                  new StandardBuildPhase { kind = "rez" }
                }
                postBuildScripts { new { name = "After"; script = "echo after" } }
              }
            }
            """#)
        let project = try decode(plan)
        let phases = try #require(project.targets.first?.commonProperties.buildPhases)
        #expect(
            phases.map(\.kind) == [
                .script, .sources, .script, .copy, .appleScript, .javaArchive, .rez, .script,
            ])
        if case .script(let script) = phases[2] {
            #expect(script.baseProperties.objectID?.rawValue == "middle-script")
            #expect(script.shellPath == "/bin/zsh")
            #expect(script.script == "echo first\necho second")
            #expect(script.logEnvironmentVariables)
            #expect(script.inputPaths == ["$(SRCROOT)/Input.txt"])
            #expect(script.inputFileListPaths == ["Inputs.xcfilelist"])
            #expect(script.outputPaths == ["$(DERIVED_FILE_DIR)/Output.txt"])
            #expect(script.outputFileListPaths == ["Outputs.xcfilelist"])
            #expect(script.dependencyFile == "$(DERIVED_FILE_DIR)/deps.d")
            #expect(script.runOnEveryBuild)
            #expect(script.scope == .install)
        } else {
            Issue.record("Expected the middle script phase")
        }
        if case .copy(let copy) = phases[3] {
            #expect(copy.bundleBasePath == .sharedSupportDir)
            #expect(copy.relativePath == "Data")
            #expect(copy.scope == .install)
        } else {
            Issue.record("Expected a copy phase")
        }
        if case .appleScript(let script) = phases[4] {
            #expect(script.isSharedContext)
            #expect(script.contextName == "Shared")
        } else {
            Issue.record("Expected an AppleScript phase")
        }
    }

    @Test func localPackageDotPathUsesItsCanonicalDirectoryNameAfterRelocation() throws {
        let fixture = try Fixture()
        try fixture.file("Package.swift", "// swift-tools-version: 6.0\n")
        let plan = try fixture.compile(
            #"""
            packages { ["root"] = new LocalSwiftPackage { path = "." } }
            targets {
              ["tool"] {
                name = "Tool"; type = "tool"
                dependencies { new { package = "root"; product = "RootLibrary" } }
              }
            }
            """#,
            outputDirectory: fixture.root.appendingPathComponent("Generated/Nested"))
        let project = try decode(plan)
        let target = try #require(project.targets.first?.commonProperties)
        let dependency = try #require(target.dependencies.first)
        if case .package(let product, _) = dependency {
            #expect(product.package?.packageName == fixture.root.lastPathComponent)
        } else {
            Issue.record("Expected a local Swift package dependency")
        }
        let member = try #require(target.packageProductTargetMembers.first)
        #expect(member.packageProduct.package?.packageName == fixture.root.lastPathComponent)
        let package = try #require(project.packages.first)
        if case .local(let local) = package.location {
            let resolved = URL(
                fileURLWithPath: local.path,
                relativeTo: plan.destination.deletingLastPathComponent())
            #expect(canonicalFileURL(resolved).path == canonicalFileURL(fixture.root).path)
        } else {
            Issue.record("Expected a local Swift package location")
        }
    }

    @Test func aliasesOfTheSameCanonicalLocalPackageAreRejected() throws {
        let fixture = try Fixture()
        try fixture.file("Package.swift", "// swift-tools-version: 6.0\n")
        try fixture.directory("Packages")
        expectFailure(containing: "Duplicate Swift package") {
            _ = try fixture.compile(
                #"""
                packages {
                  ["root"] = new LocalSwiftPackage { path = "." }
                  ["alias"] = new LocalSwiftPackage { path = "Packages/.." }
                }
                targets { ["tool"] { name = "Tool"; type = "tool" } }
                """#)
        }
    }

    @Test func metadataConfigurationReferencesAndNonNativeTargetsArePreserved() throws {
        let fixture = try Fixture()
        let plan = try fixture.compile(
            #"""
            id = "custom-project-id"; rootGroupDebugId = "root-debug"
            configurationListDebugId = "project-config-list"
            organization = "Example Organization"; classPrefix = "EX"
            buildIndependentTargetsInParallel = false
            productsGroup = null
            lastUpgrade = "27.3"; lastSwiftUpdate = "27.2"; lastSwiftMigration = "27.1.1"
            localizations { development = "ja"; supported { "en"; "fr" } }
            files {
              new Folder { path = "Config"; id = "config-folder" }
              new Group { name = "Unusual/Group"; children { new FileReference { path = "Debug.xcconfig" } } }
            }
            configurationDetails {
              ["Debug"] { id = "project-debug"; file = new AnchoredFileReference { anchor = "Config"; relativePath = "Debug.xcconfig" } }
            }
            targets {
              ["app"] { name = "App"; type = "application"; platform = "iOS" }
              ["tests"] {
                name = "Tests"; type = "bundle.unit-test"; platform = "iOS"; testHostTarget = "app"
                legacyProvisioningStyle = "manual"; legacyTeamId = "TEAM123"
                lastSwiftUpdate = "27.2"; lastSwiftMigration = "27.1"
                configurationListDebugId = "test-config-list"
                configurationDetails {
                  ["Debug"] { id = "test-debug"; file = new Listing { new NamePathComponent { name = "Unusual/Group" }; "Debug.xcconfig" } }
                }
              }
              ["all"] {
                name = "All"; kind = "aggregate"
                dependencies { new { target = "app"; link = false } }
                targetDependencies { new LocalTargetDependency { target = "Tests"; platforms { "ios" } } }
              }
              ["external"] {
                name = "External"; kind = "external-build-system"; buildToolPath = "/usr/bin/make"
                buildToolArguments = "all"; buildToolWorkingDirectory = "$(SRCROOT)/External"
                passBuildSettingsInEnvironment = false
              }
              ["custom"] {
                name = "Custom"; fullProductType = "com.example.product.custom"
                productName = "Custom.custom"; productFileType = "file"
              }
            }
            """#)
        let project = try decode(plan)
        #expect(project.objectID?.rawValue == "custom-project-id")
        #expect(project.rootGroupDebugID?.rawValue == "root-debug")
        #expect(project.configurationListDebugID?.rawValue == "project-config-list")
        #expect(project.organizationName == "Example Organization")
        #expect(project.classPrefix == "EX")
        #expect(!project.buildIndependentTargetsInParallel)
        #expect(project.productsGroup == nil)
        #expect(project.localizationInfo.development.rawValue == "ja")
        #expect(project.localizationInfo.supported.contains { $0.rawValue == "fr" })
        #expect(project.lastUpgradeCheck?.major == 27)
        #expect(project.lastSwiftMigration?.update == 1)
        let configuration = try #require(
            project.configurations.first { $0.name.rawValue == "Debug" })
        #expect(configuration.objectID?.rawValue == "project-debug")
        #expect(configuration.file?.relativePath?.description == "Debug.xcconfig")
        let tests = try #require(project.targets.first { $0.name == "Tests" }?.commonProperties)
        #expect(tests.testHostTarget?.targetName == "App")
        #expect(tests.legacyProvisioningStyle == .manual)
        #expect(tests.legacyTeamID == "TEAM123")
        #expect(tests.configurationListDebugID?.rawValue == "test-config-list")
        #expect(tests.specializedConfigurations.first?.objectID?.rawValue == "test-debug")
        let aggregate = try #require(project.targets.first { $0.name == "All" })
        #expect(aggregate.kind == .aggregate)
        #expect(aggregate.commonProperties.product == nil)
        #expect(aggregate.commonProperties.productTypeID == nil)
        if case .externalBuildSystem(let external) = try #require(
            project.targets.first { $0.name == "External" })
        {
            #expect(external.buildToolPath == "/usr/bin/make")
            #expect(external.buildToolArguments == "all")
            #expect(external.buildToolWorkingDirectory == "$(SRCROOT)/External")
            #expect(!external.passBuildSettingsInEnvironment)
        } else {
            Issue.record("Expected an external build system target")
        }
        let custom = try #require(project.targets.first { $0.name == "Custom" }?.commonProperties)
        #expect(custom.productTypeID?.productTypeID == "com.example.product.custom")
    }

    @Test(arguments: [
        #"targets { ["bad"] { name = "Bad"; type = "typo" } }"#,
        #"targets { ["bad"] { name = "Bad"; type = "tool"; platform = "visionOS-typo" } }"#,
        #"targets { ["bad"] { name = "Bad"; kind = "typo" } }"#,
        #"targets { ["bad"] { name = "Bad"; type = "tool"; postBuildScripts { new { script = "true"; scope = "typo" } } } }"#,
        #"targets { ["bad"] { name = "Bad"; type = "tool"; buildPhases { new CopyFilesBuildPhase { bundleBasePath = "typo" } } } }"#,
        #"files { new FileReference { path = "a"; lineEnding = "typo" } }"#,
        #"files { new FileReference { path = "a"; encoding = -1 } }"#,
        #"packages { ["bad"] = new RemoteSwiftPackage { repository = "https://example.com/bad"; version { kind = "typo"; value = "1" } } }"#,
    ])
    func invalidEnumsAreRejectedByPkl(_ body: String) throws {
        let fixture = try Fixture()
        let project =
            body.hasPrefix("targets")
            ? body
            : body + #"targets { ["valid"] { name = "Valid"; type = "tool" } }"#
        expectFailure(containing: body.contains("encoding = -1") ? "constraint" : "typo") {
            _ = try fixture.compile(project)
        }
    }

    @Test func platformUnionValuesProduceTheCorrespondingBuildSettings() throws {
        let fixture = try Fixture()
        let platforms = [
            ("macOS", "macosx", "MACOSX_DEPLOYMENT_TARGET"),
            ("iOS", "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET"),
            ("tvOS", "appletvos", "TVOS_DEPLOYMENT_TARGET"),
            ("watchOS", "watchos", "WATCHOS_DEPLOYMENT_TARGET"),
            ("visionOS", "xros", "XROS_DEPLOYMENT_TARGET"),
            ("driverKit", "driverkit", "DRIVERKIT_DEPLOYMENT_TARGET"),
        ]
        let declarations = platforms.map { name, _, _ in
            "[\(quoted(name))] { name = \(quoted(name)); type = \"framework\"; platform = \(quoted(name)); deploymentTarget = \"1.0\" }"
        }.joined(separator: "\n")
        let project = try decode(fixture.compile("targets { \(declarations) }"))
        for (name, sdk, deployment) in platforms {
            let target = try #require(project.targets.first { $0.name == name })
            #expect(target.commonProperties.buildSettings["SDKROOT"] == .string(sdk))
            #expect(target.commonProperties.buildSettings[deployment] == .string("1.0"))
        }
    }

    @Test(arguments: [
        #"kind = "version-range"; value = "1.0.0""#,
        #"kind = "branch"; value = "main"; maximum = "2.0.0""#,
    ])
    func invalidVersionRangesAreRejected(_ requirement: String) throws {
        let fixture = try Fixture()
        expectFailure(containing: "PackageVersion.maximum") {
            _ = try fixture.compile(
                "packages { [\"bad\"] = new RemoteSwiftPackage { repository = \"https://example.com/bad\"; version { \(requirement) } } }\n"
                    + #"targets { ["valid"] { name = "Valid"; type = "tool" } }"#
            )
        }
    }

    private func decode(_ plan: GenerationPlan) throws -> XCSchema.Project {
        let data = try #require(plan.projects.first?.data)
        #expect(try ProjectValidator.validate(data: data) == plan.targetCount)
        return try XCSchema.Project(jsonRepresentation: data)
    }
}
