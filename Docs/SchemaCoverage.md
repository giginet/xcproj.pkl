# Xcode project format coverage

This document records the schema used by `xcprojgen`, the corresponding Pkl authoring types, and the boundaries between Xcode's file format and this package's conveniences. The source of truth is Apple's [`xcode-project-format` 0.1.0](https://github.com/apple/xcode-project-format/tree/0.1.0), pinned by `Package.resolved` to [`c132630aabf40f6d6c3f7bb004595d2e5a28ea42`](https://github.com/apple/xcode-project-format/commit/c132630aabf40f6d6c3f7bb004595d2e5a28ea42). The audit reads the public `XCSchema` types and their JSON encoders/decoders, including properties omitted from JSON when equal to their defaults.

Pkl provides two complementary levels:

- `Project`, `Target`, `Source`, settings, and local target dependencies provide defaults, deterministic IDs, filesystem validation, and output-directory rebasing.
- Typed schema classes represent Xcode's file tree, phases, rules, package references, and metadata. Their native Xcode paths and references retain the meanings described below.

Both levels are evaluated by Pkl. Swift observes requested filesystem paths, validates generated documents using Apple's decoder and xcprojgen's reference validator, and writes the artifacts.

## Project and configurations

Source: [`Project.swift`](https://github.com/apple/xcode-project-format/blob/c132630aabf40f6d6c3f7bb004595d2e5a28ea42/Sources/Library/Schema/Project.swift), [`Configuration.swift`](https://github.com/apple/xcode-project-format/blob/c132630aabf40f6d6c3f7bb004595d2e5a28ea42/Sources/Library/Schema/Configuration.swift).

| Upstream JSON property | Pkl representation / purpose |
| --- | --- |
| `files` | `files: Listing<Reference>`, alongside references generated from `Target.sources`, xcconfigs, and products |
| `packages` | `packages: Mapping<String, SwiftPackage>` containing `LocalSwiftPackage` / `RemoteSwiftPackage` |
| `configurations` | `configs` and `configFiles`; `configurationDetails: Mapping<String, Configuration>` adds native `file` references and explicit `id` values |
| `default-configuration` | `defaultConfiguration` |
| `build-settings` | `settings`; values remain strings or string lists |
| `targets` | `Target` mapping, projected to ordered target objects |
| `localizations` | `Localizations` with `development` and `supported` |
| `required-capabilities` | `requiredCapabilities`: capability strings |
| `build-independent-targets-in-parallel` | `buildIndependentTargetsInParallel`; upstream default is `true` |
| `organization`, `class-prefix` | Optional `organization`, `classPrefix` strings |
| `products-group` | `productsGroup: GroupTreeReference?`; generator default is `Products` when it creates product files, otherwise explicit `null` |
| `last-upgrade`, `last-swift-update`, `last-swift-migration` | `lastUpgrade`, `lastSwiftUpdate`, `lastSwiftMigration`: optional Xcode marketing-version strings |
| `id`, `root-group-debug-id`, `configuration-list-debug-id` | Optional `id`, `rootGroupDebugId`, `configurationListDebugId` |
| `imported-products` | `importedProducts: Listing<ImportedProduct>` for referenced projects |

`Configuration.file` is an `AnchoredReference`: it can reference an explicit file or a file discovered inside a synchronized folder. A target's `specialized-configurations` entry must specify a `file` or `id`; a name-only entry is redundant and upstream rejects it. Configuration names are open strings; `debug` and `release` are generator presets, not an upstream enumeration. The debug preset uses `ONLY_ACTIVE_ARCH = YES`, matching Swift Package targets when building for a selected destination; the release preset uses `NO`. Author settings can override these defaults.

## Targets and products

Source: [`Target.swift`](https://github.com/apple/xcode-project-format/blob/c132630aabf40f6d6c3f7bb004595d2e5a28ea42/Sources/Library/Schema/Target/Target.swift), [`ProductTypeID.swift`](https://github.com/apple/xcode-project-format/blob/c132630aabf40f6d6c3f7bb004595d2e5a28ea42/Sources/Library/Schema/Values/ProductTypeID.swift).

| Upstream JSON property | Pkl representation / purpose |
| --- | --- |
| `kind` | `TargetKind`: `native`, `aggregate`, `external-build-system` |
| `name`, `id` | Target name and stable identifier |
| `product` | Optional `product: GroupTreeReference` to an explicitly authored product file; otherwise generated using `productName` / `productFileType` overrides or known defaults |
| `product-type` | `type: ProductType?` shorthand; upstream prepends `com.apple.product-type.` |
| `full-product-type` | `fullProductType`: full identifier for product types outside the shorthand convenience API |
| `build-settings`, `specialized-configurations` | `settings`, `configFiles`, and `configurationDetails` |
| `dependencies` | `dependencies` convenience or `targetDependencies: Listing<TargetDependency>` |
| `build-phases` | Optional `buildPhases: Listing<BuildPhase>` replaces the generated phases; `preBuildScripts` / `postBuildScripts` add scripts around the phases |
| `build-rules` | `buildRules: Listing<BuildRule>` |
| `package-product-members` | `packageProductMembers: Listing<PackageProductMember>` |
| `test-host-target` | `testHostTarget`: local target key resolved to its target name |
| `legacy-provisioning-style`, `legacy-team-id` | `legacyProvisioningStyle`, `legacyTeamId`; not substitutes for modern signing build settings |
| `last-swift-update`, `last-swift-migration` | `lastSwiftUpdate`, `lastSwiftMigration` |
| `configuration-list-debug-id` | `configurationListDebugId` |
| `build-tool-path`, `build-tool-arguments` | `buildToolPath`, `buildToolArguments` |
| `build-tool-working-directory` | `buildToolWorkingDirectory` |
| `pass-build-settings-in-environment` | `passBuildSettingsInEnvironment`; upstream default is `true` |

Aggregate and external targets need not produce a product. A project containing only those targets has no generated Products group, so the generator emits `products-group: null`; simply omitting the property would make Apple's decoder assume a nonexistent `Products` reference. An explicitly authored `productsGroup` reference is preserved and validated.

Product type and target kind are separate concepts. Apple's `ProductTypeID` is an open string wrapper, not a closed enum: the Pkl known-product union helps author common targets, while the full identifier preserves extensibility. Product filenames and file types must also be supplied when the generator cannot derive them from a known product type. `productName` supplies the complete filename for references and schemes; when overriding it, also supply matching product build settings such as `PRODUCT_NAME` and `WRAPPER_EXTENSION` as appropriate for that product type.

## Swift packages and dependencies

Source: [`Packages`](https://github.com/apple/xcode-project-format/tree/c132630aabf40f6d6c3f7bb004595d2e5a28ea42/Sources/Library/Schema/Packages), [`Target/Dependencies`](https://github.com/apple/xcode-project-format/tree/c132630aabf40f6d6c3f7bb004595d2e5a28ea42/Sources/Library/Schema/Target/Dependencies).

| Pkl type | Upstream fields |
| --- | --- |
| `LocalSwiftPackage` | `kind = "local"`, `path`, `traits` |
| `RemoteSwiftPackage` | `kind = "remote"`, `repository`, optional `version`, `traits` |
| `PackageVersion` | Revision, branch, exact version, next minor, next major, or minimum/maximum range |
| `LocalTargetDependency` | Optional `kind = "localTarget"`, `target`, `platforms` |
| `RemoteTargetDependency` | `kind = "remoteTarget"`, `project`, `target`, `target-id`, `platforms` |
| `PackageDependency` | `kind = "package"`, optional `package`, `product-name`, `product-type`, optional `id`, `platforms` |
| `PackageProductMember` | Package product reference plus `build-phase: TargetBuildFile` |
| `ImportedProduct` | `project`, `target`, `product-id`, `path` or `name`, optional `type`, `target-membership` |

`PackageVersion` emits exactly one requirement shape inside the remote package's `version` object:

| Requirement | JSON key(s) |
| --- | --- |
| Revision | `revision` |
| Branch | `branch` |
| Exact version | `version` |
| Next minor | `up-to-next-minor-version` |
| Next major | `up-to-next-major-version` |
| Range | `version-range` as `minimum..<maximum`, or `version-range-min` and `version-range-max` |

The upper bound of a version range is exclusive. An omitted requirement is allowed by the schema. Package `traits` apply to both local and remote packages.

A native package declaration has no arbitrary alias field. The keys in Pkl's `packages` mapping are generator conveniences and are not emitted as package fields. A native package-product reference's optional `package` identifies the package as understood by Xcode. The generator derives it from the repository or local-directory basename, removes a trailing `.git`, and preserves case. It is distinct from `Package.name` in the Swift manifest and from the Pkl module dependency name in `PklProject`. The Advanced example builds a package whose alias, directory, manifest name, product, and module names all differ to exercise this distinction.

A package dependency establishes build order; linking its product additionally requires a `PackageProductMember` targeting the frameworks phase. `product-type` here is `other` or `build-tool-plugin`, independent of native target product types. The convenience `dependencies` API accepts package/product references and emits the corresponding dependency and linked membership.

Cross-project dependencies require a project file reference and the remote target ID. Linking a remote product additionally uses `ImportedProduct` and its build-file membership. A workspace's project listing alone does not create those dependency edges.

## Build phases and build rules

Source: [`BuildPhases`](https://github.com/apple/xcode-project-format/tree/c132630aabf40f6d6c3f7bb004595d2e5a28ea42/Sources/Library/Schema/BuildPhases), [`BuildRule.swift`](https://github.com/apple/xcode-project-format/blob/c132630aabf40f6d6c3f7bb004595d2e5a28ea42/Sources/Library/Schema/BuildRules/BuildRule.swift).

| Pkl type | Upstream fields |
| --- | --- |
| `BuildPhase` | Common optional `name`, `id` |
| `StandardBuildPhase` | `kind`: `headers`, `frameworks`, `resources`, `compile-sources`, `java-archive`, or `rez` |
| `ScriptBuildPhase` | `kind = "script"`, `shell`, `script`, `log-environment-variables`, `input-paths`, `input-file-list-paths`, `output-paths`, `output-file-list-paths`, `dependency-file`, `run-on-every-build`, `scope` |
| `CopyFilesBuildPhase` | `kind = "copy"`, `bundle-base-path`, `relative-path`, `scope` |
| `AppleScriptBuildPhase` | `kind = "apple-script"`, `is-shared-context`, `context-name` |
| `BuildRule` | `processor`, `name`, `file-type`, `file-patterns`, `script`, `input-files`, `input-file-lists`, `output-files`, `output-file-lists`, `output-files-compiler-flags`, `dependency-file`, `run-once-per-architecture`, `id` |

Phase ordering comes from the array order. A post-build script is a script phase placed after the normal phases; it is not a separate upstream phase kind. Script paths and bodies may contain Xcode build-setting expressions, so they are not host-resolved filesystem requests. The shell-script body accepts multiline content; Apple's codec also supports its array-of-lines representation.

`scope` is `always` or `install`. `run-on-every-build` defaults to `false`. Build rules' `run-once-per-architecture` defaults to `true`.

`bundle-base-path` accepts all upstream destinations: `root`, `build-products-directory`, `shared-frameworks-directory`, `shared-support-directory`, `java-directory`, `frameworks-directory`, `resources-directory`, `package-info-file`, `apple-scripts-directory`, `plugins-directory`, `private-headers-directory`, `headers-directory`, `contents-directory`, `executables-directory`, `info-plist-file`, `main-executable-file`, and `shallow-main-executable-file`.

## File tree and membership

Source: [`References`](https://github.com/apple/xcode-project-format/tree/c132630aabf40f6d6c3f7bb004595d2e5a28ea42/Sources/Library/Schema/References), [`BuildFiles`](https://github.com/apple/xcode-project-format/tree/c132630aabf40f6d6c3f7bb004595d2e5a28ea42/Sources/Library/Schema/BuildFiles).

| Pkl type | Upstream fields |
| --- | --- |
| `Reference` | Common `path`, optional `id`, optional `index` |
| `FileReference` | `type`, `signature`, `encoding`, `line-ending`, `target-membership` |
| `Group` | `name`, `children: Reference` |
| `Folder` | `target-membership` as target names, `membership-exceptions`, `file-types`, `opaque-folders` |
| `VariantGroup` | `name`, `children: FileReference`, `target-membership` |
| `VersionGroup` | Variant-group fields plus `current-version` and `type` |
| `ProjectBuildFile` | `build-phase` including target, optional `id`, build-file properties |
| `TargetBuildFile` | `build-phase` relative to its target, optional `id`, build-file properties |
| `BuildFileProperties` | `platforms`, `arguments`, `asset-tags`, attributes below |
| `BuildFileAttributes` | `header-role`, `mach-interface-generation`, `is-weak`, `code-sign-on-copy`, `code-generation`, `header-preservation`, `decompress`, `code-generation-visibility` |
| `TargetExceptionSet` | `target`, `inclusions` or `exclusions`, `public-headers`, `private-headers`, `compiler-flags`, per-member properties below |
| `BuildPhaseExceptionSet` | `build-phase`, `inclusions`, per-member properties below |
| Common exception properties | Per-folder-member `platforms`, `attributes`, and `asset-tags` mappings |

Groups organize the navigator and are not target members. Folders discover their children dynamically and assign their files to phases using Xcode's rules. An opaque folder instead uses a single `FileReference` that participates in the build as one item. `VariantGroup` models localized resources; `VersionGroup` models versioned resources such as Core Data models.

File membership and target dependencies are different edges. Membership attaches a file or product to a phase and carries compiler flags, platform filters, weak linking, header visibility, copy-signing, and related attributes. The existing `Source.excludes` and dependency `link` / `embed` settings are conveniences over these structures.

Automatic extension embedding applies to the supported `.appex` variants that belong in `PlugIns`. ExtensionKit, system, DriverKit, and kernel extensions require explicit copy phases and product membership for their different destinations; selecting their product type alone does not choose a copy destination.

## Paths and references

Source: [`FilePath.swift`](https://github.com/apple/xcode-project-format/blob/c132630aabf40f6d6c3f7bb004595d2e5a28ea42/Sources/Library/Schema/References/FilePath.swift), [`GroupTreeReference.swift`](https://github.com/apple/xcode-project-format/blob/c132630aabf40f6d6c3f7bb004595d2e5a28ea42/Sources/Library/Schema/Values/GroupTreeReference.swift), [`GroupTreeAnchoredReference.swift`](https://github.com/apple/xcode-project-format/blob/c132630aabf40f6d6c3f7bb004595d2e5a28ea42/Sources/Library/Schema/Values/GroupTreeAnchoredReference.swift), [`NamePath.swift`](https://github.com/apple/xcode-project-format/blob/c132630aabf40f6d6c3f7bb004595d2e5a28ea42/Sources/Library/Schema/Values/NamePath.swift).

Native schema paths are interpreted by Xcode and are emitted unchanged. They are not implicitly rebased when `--output-dir` changes:

| Path | Meaning |
| --- | --- |
| `Sources/File.swift` | Relative to the parent group |
| `<PROJECT>/Sources/File.swift` | Relative to the generated Xcode project's directory |
| `<SDK>/System/Library/Frameworks/Foundation.framework` | Relative to the selected SDK |
| `<DEVELOPER>/...` | Relative to the developer directory |
| `<PRODUCTS>/Example.framework` | Relative to the built-products directory |
| `<USER:SETTING>/...` | Relative to the named Xcode source-tree/build-setting base |
| `/absolute/path` | Absolute filesystem path |

By contrast, convenience `Source.path`, `configFiles`, `infoPlist`, and `LocalSwiftPackage.path` paths are observed relative to `projectDir` and rebased by the generator. Use those conveniences for checked source paths when relocating generated bundles. Native file references, external build-tool paths, and script input/output paths retain Xcode semantics; a source tree that does not yet exist can therefore be represented with a native reference.

`GroupTreeReference` is a navigator reference, not a filesystem path. It accepts a unique name path or `id:<identifier>`. Its component-list representation handles names containing `/`, names literally equal to `.` or `..`, and names beginning with `id:`. `NamePathComponent { name = "..." }` expresses a literal child name; bare `.` and `..` components express relative navigation.

`AnchoredReference` additionally supports an object with `anchor` and `relativePath`, corresponding to JSON `anchor` and `relative-path`. This is useful for an xcconfig file discovered within a folder. Project-context phase references contain a target name plus phase kind and optional name; target-context phase references omit the target. Both can use an explicit object ID when names are ambiguous.

## Enum boundaries and value types

Pkl's named unions of string literals serve as enums. Closed sets follow Apple's actual enums: target kind, build-phase kind, phase scope, bundle destination, package location/constraint kind, package-product type, legacy provisioning style, line ending, header role/preservation, Mach-interface generation, and code-generation mode/visibility.

The generator's `Target.platform` convenience is also a union: `iOS`, `macOS`, `tvOS`, `watchOS`, `visionOS`, or `driverKit`. It selects SDK, supported-platform, and deployment-target build settings. Native membership/dependency platform filters remain open strings, matching Apple's `PlatformFilter` rather than this generator-level platform vocabulary.

| Value | Upstream accepted representation |
| --- | --- |
| `ProductTypeID`, `FileTypeID`, `PlatformFilter`, `Language`, `AssetTag`, `SwiftPackageName` | Open strings; known-value convenience aliases must preserve an escape hatch where needed |
| `ObjectID` | Any string in upstream; 24 hexadecimal characters are a generator/Xcode convention, not an upstream type constraint |
| `MarketingVersion` | Two or three dot-separated integer components, for example `27.3` or `27.3.1` |
| `BuildSetting` | String or array of strings; no JSON number or Boolean coercion |
| `TextEncoding` | Recognized encoding string or integer raw encoding value |
| `Capability` | Open descriptive string, checked against the decoder's supported capabilities |

The upstream capability list currently contains only a test capability. Setting an unknown capability deliberately makes the decoder reject the document; it is not an arbitrary project annotation field. Development language is separate from the supported-language set; the latter should not duplicate it.

## Schemes and workspaces

Apple's `XCSchema.Project` covers `project.xcproj`. It contains no Scheme type or `schemes` property, and this library does not encode `.xcscheme` files. Shared schemes are separate XML artifacts under `xcshareddata/xcschemes/`. Workspace XML is also a separate artifact.

Consequently, Pkl scheme authoring and XML generation are generator features, not claims of extra keys supported by Apple's project JSON schema. Scheme support must be documented and validated separately from project-schema coverage. A scheme build action references generated target IDs and product names; changing only a workspace's project membership does not define a scheme's build, test, run, profile, analyze, or archive actions.

`Workspace.projects` accepts both Pkl `Project` modules and `ExistingProject` references returned by `importXcodeproj(path)`. An existing reference adds a workspace XML member without importing its targets into the Pkl authoring model. Paths are resolved relative to `workspaceDir` or may be absolute, canonicalized for duplicate/collision checks, and rebased relative to the generated workspace. The existing bundle and its schemes remain unchanged. A workspace can consist entirely of existing references.

Both JSON `project.xcproj` and legacy `project.pbxproj` bundles are supported. JSON members use the same schema and reference validators as generated documents. Legacy members are parsed as property lists and checked for a valid project root and target objects. This structural check is not a complete validator for the legacy format or Xcode build semantics. The importer does not convert between formats. Generated schemes reference generated targets only; imported projects retain their existing shared schemes.

## Validation boundary

Pkl type constraints catch malformed authoring values and required properties. Generator validation checks local convenience dependencies, conflicting names, and filesystem requests. Apple's parser and xcprojgen's reference validator check the final native document, including typed low-level references. A successfully decoded project does not establish that a remote package resolves, a build tool exists, a custom product type is installed, signing succeeds, or a script can run. Build smoke tests cover representative generated projects in addition to schema-level tests.

When upgrading `xcode-project-format`, compare this table with every `public var`, enum case, and encoder key under `Sources/Library/Schema`; update the pin and coverage together.
