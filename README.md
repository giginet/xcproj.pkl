# xcproj.pkl

`xcprojgen` is a Swift CLI that generates and validates Xcode JSON projects (`project.xcproj`) and workspaces (`xcworkspace`) from Pkl. Depending on the type of `Main.pkl`, it generates either a single xcodeproj or an xcworkspace containing multiple projects.

Version 2 uses Pkl class inheritance to reuse targets, module classes and `amends` to reuse projects, and imports and object amendments to share settings. Pkl handles settings resolution, defaults, stable IDs, and construction of Xcode JSON and workspace XML.

## Requirements

- macOS 14 or later and Swift 6.1 or later.
- Pkl 0.33 or later. Executables are located in this order: `--pkl`, `PKL_EXEC`, then `PATH`.
- An Xcode version that supports JSON projects. Tested with Xcode 27.3 beta 1.

Pkl runs as an external process. You do not need Pkl installed to validate an existing xcproj or workspace.

All examples use `Main.pkl` as their entry point and depend on the package in this checkout through `Examples/PklProject`. See the [examples guide](Examples/README.md) for the Swift 6 framework templates, app, and Notification Service Extension.

## Usage

```sh
swift build
swift run xcprojgen --help

# Check the Pkl CLI executable and version.
swift run xcprojgen doctor

# Create a workspace scaffold with Main.pkl as its entry point (the default).
swift run xcprojgen init MyWorkspace --type workspace

# Create a scaffold for a single xcodeproj.
swift run xcprojgen init MyLibrary --type project

# Resolve package dependencies and validate the resulting JSON/XML.
swift run xcprojgen validate MyWorkspace

# Generate MyWorkspace/Workspace.xcworkspace and its xcodeproj bundles.
swift run xcprojgen generate MyWorkspace

# Set the workspace output directory. Relative paths use the CLI working directory.
swift run xcprojgen validate MyWorkspace --output-dir /tmp/generated
swift run xcprojgen generate MyWorkspace --output-dir /tmp/generated
# => /tmp/generated/Workspace.xcworkspace

# Validate existing output without modifying it. Pkl is not required.
swift run xcprojgen validate /tmp/generated/Workspace.xcworkspace

# Set a Pkl external property. This option can be repeated.
swift run xcprojgen generate MyWorkspace --property flavor=debug
```

`init <dir>` does not access the network, launch Pkl, or overwrite existing files. It creates the following scaffold:

```text
MyWorkspace/
  PklProject
  Main.pkl
  Templates.pkl
  Projects/Core/
    Project.pkl
    Sources/Core.swift
    Tests/CoreTests.swift
```

`PklProject` declares a dependency on `xcproj@0.1.0` from a future GitHub release (`v0.1.0`) of this repository. That release has not been published yet, so the URI will become usable once distribution begins. During development, use a local dependency as described below, or populate the local cache with `Scripts/package-pkl.sh --skip-publish-check --install`.

`Main.pkl` is the common entry point. Use `amends "@xcproj/Workspace.pkl"` to generate a workspace or `amends "@xcproj/Project.pkl"` to generate a project. `init --type` only selects the scaffold; generation determines the output from the Pkl type. A single-project scaffold places `Main.pkl`, `Sources/`, and `Tests/` at the root.

To use another entry point, specify `--entry` relative to the input directory. A missing default `Main.pkl` is an error; the CLI does not search for `Project.pkl` or `Workspace.pkl` automatically.

```sh
swift run xcprojgen generate MyWorkspace --entry Projects/Core/Project.pkl --output-dir /tmp/generated
swift run xcprojgen validate MyWorkspace --entry Projects/Core/Project.pkl
```

`validate` and `generate` run `pkl project resolve` for the nearest `PklProject` before evaluation. `validate` may create or update the dependency lockfile, `PklProject.deps.json`, but does not write the generated xcworkspace or xcodeproj. Commit the lockfile in the consuming repository.

`--output-dir` (short form: `-o`) specifies the output directory. The entry-point Pkl module determines the bundle name and extension. A workspace with `name = "App"` generates `<output-dir>/App.xcworkspace`; a project generates `<output-dir>/App.xcodeproj`. Swift does not accept a bundle name or extension, or check the extension of the output argument. When `--entry` is specified, the selected Pkl module still determines the name and type.

Each generated project in a workspace is written to its own `projectDir`, and workspace references are adjusted accordingly. Existing project bundles remain in place. Without `--output-dir`, the output is `workspaceDir/name.xcworkspace` for a workspace or `projectDir/name.xcodeproj` for a project. Relative output directories are resolved against the CLI working directory.

You can also pass `Project.pkl` or `Workspace.pkl` directly, or validate an existing `.xcworkspace`, `.xcodeproj`, or `project.xcproj`.

```sh
swift run xcprojgen validate Examples/Workspace
swift run xcprojgen generate Examples/Tool --output-dir /tmp/generated
swift run xcprojgen validate /tmp/generated/Tool.xcodeproj
```

`--pkl /path/to/pkl` is available for `doctor`, `validate`, and `generate`. The lookup order is `--pkl`, `PKL_EXEC`, then `PATH`. `PKL_EXEC` must be an executable path without arguments. `doctor` prints the executable and version, and exits with a nonzero status if Pkl is missing, fails to run, or has an unsupported version. For a missing or unsupported installation, it links to the [official Pkl installation guide](https://pkl-lang.org/main/current/pkl-cli/index.html#installation). It does not install Pkl automatically.

`--pkl`, `--property`, `--entry`, and `--output-dir` cannot be used when validating existing output. Property names beginning with `xcproj.internal.` are reserved for internal use.

## Pkl project and package distribution

The distributable Pkl project lives in `Pkl/xcproj/`. The SwiftPM bridge sits outside it.

```text
Pkl/
  RuntimeResources.swift
  xcproj/
    PklProject
    Project.pkl
    Workspace.pkl
    Internal/
    tests/ApiTests.pkl
    README.md
Scripts/package-pkl.sh
```

```sh
# Run API tests, check existing published versions, and build the package.
Scripts/package-pkl.sh

# Build locally without network access.
Scripts/package-pkl.sh --skip-publish-check

# Specify the Pkl executable and output directory.
Scripts/package-pkl.sh --pkl /path/to/pkl --skip-publish-check -o /tmp/pkl-dist
```

The script uses the official `pkl project package` command. By default, it writes a ZIP archive, package metadata, and SHA-256 sidecar files for both to `dist/pkl/xcproj@0.1.0/`. The packager also runs the API tests and excludes tests, manifests, and Swift sources from the ZIP. See the [official CLI documentation](https://pkl-lang.org/main/current/pkl-cli/index.html#pkl-project-package).

The version, package URI, and ZIP URL are defined in `Pkl/xcproj/PklProject`. The current URLs are intended for future distribution through GitHub Releases. The repository is private and distribution is not yet configured; before publishing, set metadata and ZIP URLs that consumers can access. The script does not upload anything.

Consumers declare the package in their `PklProject` dependencies, run `pkl project resolve`, and then use `amends "@xcproj/Project.pkl"` or `import "@xcproj/Project.pkl" as X`. To use a checkout, declare a local dependency with `dependencies { ["xcproj"] = import("/path/to/xcproj.pkl/Pkl/xcproj/PklProject") }`. See the [official documentation on local dependencies](https://pkl-lang.org/main/current/language-reference/index.html#local-dependencies).

See the [package README](Pkl/xcproj/README.md) for examples and the distribution layout.

## Target classes and shared settings

`Pkl/xcproj/Project.pkl` is an `open module` exposing public types such as `Target` and `Settings`. The following examples are files placed at the repository root.

`Settings.pkl`:

```pkl
import "Pkl/xcproj/Project.pkl" as X

warnings: X.Settings = new {
  base { ["SWIFT_TREAT_WARNINGS_AS_ERRORS"] = "YES" }
}

compiler = (warnings) {
  base {
    ["SWIFT_VERSION"] = "6.0"
    ["OTHER_SWIFT_FLAGS"] = new Listing { "$(inherited)"; "-DTEAM" }
  }
  configs {
    ["Debug"] { base { ["ENABLE_TESTABILITY"] = "YES" } }
  }
}
```

`Targets.pkl`:

```pkl
import "Pkl/xcproj/Project.pkl" as X
import "Settings.pkl" as Common

open class SwiftTarget extends X.Target {
  local target = this
  platform = "macOS"
  deploymentTarget = "14.0"
  settings = Common.compiler
  sources { new { path = "Sources/\(target.name)" } }
}

open class Framework extends SwiftTarget { type = "framework" }
open class UnitTests extends SwiftTarget { type = "bundle.unit-test" }
```

`Project.pkl`:

```pkl
amends "Pkl/xcproj/Project.pkl"
import "Targets.pkl" as Shared

name = "Catalog"
idNamespace = "com.example.catalog"
targets {
  ["framework"] = new Shared.Framework {
    name = module.name
    sources = new Listing<Source> { new { path = "Sources" } }
  }
  ["tests"] = new Shared.UnitTests {
    name = "\(module.name)Tests"
    sources = new Listing<Source> { new { path = "Tests" } }
    dependencies { new { target = "framework" } }
  }
}
```

`extends` extends a type or shared module, `amends` changes values in an existing module, and `(base) { ... }` amends an object. Shared classes may remain incomplete, but generated native targets require `name` and either `type` or `fullProductType`. The default `platform` is `macOS`.

Properties added to user-defined classes are excluded by the explicit projection into generation data. Use typed or `hidden` properties for template parameters, and `local target = this` to capture the receiver for implementation details.

## Amendment rules

The standard Pkl rules apply.

| Syntax | Behavior |
|---|---|
| `settings = Common.compiler` | Replace the settings object |
| `settings { base { ["KEY"] = "value" } }` | Amend part of the inherited settings |
| `sources { new { path = "Extra" } }` | Append to the inherited Listing |
| `sources = new Listing<Source> { new { path = "Only" } }` | Replace the entire Listing |
| `settings { base { ["OTHER_SWIFT_FLAGS"] { "-DNEW" } } }` | Append when the existing value is a Listing |

The inferred-type syntax `sources = new { ... }` also amends the inherited value. To replace it completely, specify the Listing type explicitly as shown above.

Pkl uses single inheritance. To combine independent settings, use an explicit function that accepts and returns `Settings`. Spreading does not perform a deep merge.

`Settings` contains `base` and `configs`. Values in `configs` can define only `base`; configurations cannot be nested recursively. The final precedence for Xcode is:

`built-in base < built-in configuration < user base < user configuration`

User values are the settings after Pkl evaluates inheritance. Setting `SWIFT_OPTIMIZATION_LEVEL = "-Osize"` in `base` overrides even the built-in Debug and Release settings. Configuration-specific differences are converted to `KEY[config=Debug]`. Xcode macros such as `$(inherited)` are preserved.

The v1 fields `targetTemplates`, `templates`, `settingGroups`, `groups`, and `templateAttributes` have been removed. There is no custom `${...}` expansion. The v2 schema rejects these legacy fields.

## Workspaces with many projects

`Examples/Workspace` demonstrates a shared project module that defines a framework and tests, with each project using `amends` to customize it.

```text
Examples/Workspace/
  Shared/FrameworkProject.pkl
  Modules/
    Catalog/Project.pkl
    DesignSystem/Project.pkl
    Networking/Project.pkl
  Main.pkl
```

Each `Project.pkl`:

```pkl
amends "../../Shared/FrameworkProject.pkl"
name = "Catalog"
```

`Main.pkl`:

```pkl
amends "@xcproj/Workspace.pkl"
name = "Modular"
projects = import*("Modules/*/Project.pkl")
```

```sh
swift run xcprojgen validate Examples/Workspace
swift run xcprojgen generate Examples/Workspace
swift run xcprojgen validate Examples/Workspace/Modular.xcworkspace

# Each project can also be generated independently with identical contents.
swift run xcprojgen generate Examples/Workspace/Modules/Catalog/Project.pkl
```

Projects are generated at `projectDir/name.xcodeproj`, and workspaces at `workspaceDir/name.xcworkspace`. For workspace input, `--output-dir` changes the workspace output directory; its name comes from the workspace's `name`.

Amending an imported project inside a workspace preserves paths relative to the original `Project.pkl` directory. If the module itself is a symlink, the canonical module's parent directory is used, keeping standalone and workspace generation consistent. Project modules must use local file URIs. Shared templates and settings can use Pkl imports.

The CLI also canonicalizes the entry path before Pkl evaluation. Relative Pkl imports and reads inside projects imported by a workspace follow Pkl's own URI resolution. When importing a file symlink, those references must therefore also resolve from the symlink URI. This is separate from how source and xcconfig paths are resolved.

Registering the same canonical project twice, or using duplicate or nested output paths, is an error. Use the typed `RemoteTargetDependency` and `ImportedProduct` classes for dependencies between projects, specifying the referenced target and product IDs explicitly.

### Including existing Xcode projects

`Workspace.importXcodeproj(path)` returns an `ExistingProject` reference for the workspace's `projects` mapping. It accepts an existing `.xcodeproj` bundle containing either JSON `project.xcproj` or legacy `project.pbxproj`. Mix these references with imported Pkl project modules, or use them for every workspace member:

```pkl
amends "@xcproj/Workspace.pkl"
import "Projects/App/Project.pkl" as App

name = "AppWorkspace"
projects {
  ["app"] = App
  ["legacy"] = module.importXcodeproj("Vendor/Legacy.xcodeproj")
}
```

Relative paths use `workspaceDir`; absolute paths are also accepted. Moving the workspace with `--output-dir` rebases its XML references. Existing project bundles are neither moved nor converted, and their files, schemes, and settings are never rewritten. Canonical paths are used to reject duplicate imports and collisions with generated output.

Validation checks imported JSON projects with Apple's decoder and the same reference validation used for generated projects. For legacy projects, it checks the property list, project root, and target objects; this is structural validation, not full Xcode semantic validation. CLI project and target counts include both generated and existing members.

Importing a bundle does not turn its targets into Pkl `Target` objects. Generated workspace schemes can reference generated targets; use the imported project's own shared schemes for its targets. Workspace membership alone does not create cross-project target dependencies.

The [MixedWorkspace example](Examples/README.md#mixing-generated-and-existing-projects) combines a generated tool project with a checked-in legacy project and shared scheme.

## Path, ID, and output guarantees

- Relative paths for sources, xcconfig files, and target `infoPlist` files use each project's `projectDir`. `infoPlist` must point to an existing file; `INFOPLIST_FILE` is rebased when output moves.
- A source's `kind` is either `folder` or `file`. A folder's `excludes` must contain exact relative paths that exist; globs are not supported.
- Nested sources within a target are rejected. Sources pointing to the same filesystem object are merged after symlink resolution, with their excludes combined as a set.
- When multiple targets share a source, one reference is generated with separate membership for each target.
- The target Mapping key is its stable identifier. Dependencies use this key in their `target` field.
- IDs are the first 24 hexadecimal digits of the SHA-256 hash of a UTF-8 string containing the namespace, kind, and key, separated by NUL characters. Renaming a target preserves its ID as long as its key stays the same. Keep `idNamespace` fixed when renaming a project.
- You can also specify custom `id` and `productId` values. Duplicate IDs are detected case-insensitively.
- After validating all projects, `generate` checks every output destination before writing. It does not overwrite bundles containing a legacy `project.pbxproj`.
- Only generated `project.xcproj`, `contents.xcworkspacedata`, and shared schemes declared in Pkl are updated. Imported project bundles remain read-only. Other schemes and user settings are preserved, and files with identical bytes are not rewritten.
- Writes are atomic per file. Rollback of an entire workspace is not guaranteed, and projects removed from a workspace are not deleted automatically.

## Architecture

```text
Pkl/xcproj/Project.pkl, Workspace.pkl    Public module classes
Pkl/xcproj/Internal/ProjectModel.pkl     Base definitions for authoring types
Pkl/xcproj/Internal/SchemaTypes.pkl      Types and unions matching Apple's schema
Pkl/xcproj/Internal/SchemaRender.pkl     Projection from typed values to native JSON
Pkl/xcproj/Internal/Snapshot.pkl         Projection of evaluated settings and path requests
Pkl/xcproj/Internal/Builtins.pkl         Default settings, configurations, and IDs
Pkl/xcproj/Internal/Validation.pkl       Model and graph validation
Pkl/xcproj/Internal/Xcode.pkl            Final Xcode JSON construction
Pkl/xcproj/Internal/WorkspaceXml.pkl     Workspace XML construction
Pkl/xcproj/Internal/Schemes.pkl          Shared scheme reference resolution and XML construction
Pkl/xcproj/Internal/Render.pkl           Generation plan containing complete output files
Sources/XcprojPkl/HostFacts.swift        Filesystem path information
Sources/XcprojPkl/GenerationPlan.swift   Execution, final validation, and output control
Sources/XcprojPkl/PklTool.swift          Pkl evaluation, dependency resolution, and version checks
```

The user module is evaluated once to produce a fixed snapshot. Swift then supplies symlink, existence, and file-kind information before evaluating the internal `Render.pkl`. Evaluating a generation plan takes two Pkl processes for the entire workspace. The CLI launches one additional Pkl process beforehand to resolve dependencies when a `PklProject` exists. The second evaluation does not re-import user modules. Swift neither decodes the authoring models for targets and settings nor rewrites the completed JSON/XML.

Swift handles the CLI, Pkl process execution, filesystem path information, validation with Apple's XCSchema, reference validation for existing output, and file writes. Pkl handles target inheritance, settings composition, ID calculation, and JSON/XML construction. Since validating existing output does not use Pkl, Swift's `ProjectValidator` and `WorkspaceValidator` perform that validation.

In the Swift library, `PklTool` is the common interface for execution. Create generation plans with `GenerationPlan.compile(source:tool:properties:outputDirectory:)`.

The internal Pkl modules are included in a SwiftPM resource bundle. When moving the executable, place `xcproj-pkl_PklRuntimeResources.bundle` in the same directory.

## Supported features and validation

Typed Pkl classes cover projects, targets, packages, build phases, build rules, and file references from Apple's `xcode-project-format` 0.1.0. See the [schema coverage reference](Docs/SchemaCoverage.md) for upstream mappings, path handling, and constraints.

`TargetKind`, `ProductType`, `Platform`, and `BuildPhaseKind` are named string unions. `Platform` supports `iOS`, `macOS`, `tvOS`, `watchOS`, `visionOS`, and `driverKit`, generating the corresponding SDK and deployment target settings. Known product types include apps, extensions, frameworks, libraries, and test bundles. Custom types use `fullProductType` with `productName` and `productFileType`. File types and platform filters remain extensible strings, as defined by Apple.

`kind = "aggregate"` and `kind = "external-build-system"` are also supported. External targets require `buildToolPath`. For dependencies within a project, `dependencies.target` refers to a Mapping key; Swift package dependencies specify `package` and `product`. References to another project use `RemoteTargetDependency` and `ImportedProduct`. To embed an App Extension, specify `link = false; embed = true`.

`productName` is the product filename, including its extension, used in file references and schemes. If you change it, also set build settings such as `PRODUCT_NAME` so the actual output name matches. `productName` is also required when `product` refers to an existing file reference. ExtensionKit, System, Driver, and Kernel Extensions use different embedding destinations from regular App Extensions, so declare their destinations explicitly with `CopyFilesBuildPhase` and membership.

### Swift packages, build scripts, and schemes

```pkl
packages {
  ["collections"] = new RemoteSwiftPackage {
    repository = "https://github.com/apple/swift-collections.git"
    version { kind = "up-to-next-major-version"; value = "1.1.0" }
  }
  ["support"] = new LocalSwiftPackage { path = "Packages/Support" }
}
targets {
  ["app"] {
    name = "App"; type = "application"; platform = "iOS"
    dependencies { new { package = "collections"; product = "Collections" } }
    postBuildScripts {
      new {
        name = "Record Build"
        script = #"printf '%s\n' "$PRODUCT_NAME" > "$SCRIPT_OUTPUT_FILE_0""#
        outputPaths { "$(DERIVED_FILE_DIR)/build-name.txt" }
      }
    }
  }
}
schemes {
  ["App"] {
    build { targets { new { target = "app" } } }
    run = new { target = "app" }
    profile = new { target = "app" }
    analyze = new {}
    archive = new {}
  }
}
```

Package Mapping keys are aliases for use in Pkl. Xcode package reference names are derived from the last component of the repository URL or path, preserving case and removing `.git`. They are distinct from `Package.name` in `Package.swift`. Local package paths are relative to `projectDir` and are rebased for `--output-dir`. Remote version requirements support `revision`, `branch`, `version`, `version-range`, `up-to-next-minor-version`, and `up-to-next-major-version`; ranges also require `maximum`. Package traits, platform filters, and build tool plugins are supported.

`preBuildScripts` and `postBuildScripts` run before and after the generated build phases. An explicit `buildPhases` value replaces the default phase Listing and preserves the specified order. Scripts support input/output paths, file lists, dependency files, unconditional execution, and other options. These paths can contain Xcode build setting macros.

Schemes are generated at `xcshareddata/xcschemes/<name>.xcscheme`. They support Build, Run, Test, Profile, Analyze, and Archive actions, launch arguments, environment variables, and pre/post scripts for actions. Target references use the target key within a project, or `project-key/target-key` within a workspace. For example: `test = new { targets { new { target = "tests" } }; codeCoverage = true }`. Scheme names, targets, and configurations are validated, and schemes outside the generation plan are preserved.

The [Advanced example](Examples/Advanced/README.md) demonstrates local package linking, build scripts, and shared schemes with an actual build.

Pkl checks model names, types, configuration references, dependencies, cycles, and source consistency. Swift then validates with Apple's XCSchema and checks references. Successful validation does not guarantee a successful build.

Validation of existing workspaces supports groups and `group:`, `container:`, and `absolute:` references, detecting missing and duplicate entries. Both JSON and legacy project members are accepted; legacy validation is limited to property-list structure, the project root, and target objects. XML entities and nested workspaces are unsupported. Write-specific checks for legacy bundles and output file/directory conflicts run before generation writes any files.

```sh
swift test
PKL_EXEC="$(command -v pkl)" swift test
PKL_EXEC="$(command -v pkl)" bash Scripts/smoke-test.sh
PKL_EXEC="$(command -v pkl)" bash Scripts/workspace-smoke-test.sh
PKL_EXEC="$(command -v pkl)" bash Scripts/ios-smoke-test.sh
PKL_EXEC="$(command -v pkl)" bash Scripts/advanced-smoke-test.sh
```

Integration tests that use Pkl are skipped when `PKL_EXEC` is not set. They cover native inheritance, settings precedence, symlinks, 100 projects / 200 targets, Pkl process counts, and relocating resources for distribution. Swift-only tests cover validation of existing formats, filesystem behavior, and output control.

The Workspace example builds tests by specifying project targets directly. The Advanced example builds through a generated shared scheme. In the tested environment, Apple's CLI is `xcrun xcodeproj`.

## Swift formatting

Use `xcrun swift-format`. `.swift-format` contains the full output of `xcrun swift-format dump-configuration`, with `indentation.spaces` and `tabWidth` set to 4. Swift sources created by `init` also use four spaces.

```sh
git ls-files -z -- '*.swift' | xargs -0 xcrun swift-format format --in-place --configuration .swift-format
git ls-files -z -- '*.swift' | xargs -0 xcrun swift-format lint --strict --configuration .swift-format
```

The `PostToolUse` hook in `.codex/hooks.json` formats changed Swift files after edits, patches, and shell commands. It covers staged, unstaged, and untracked Swift files, excluding files ignored by Git and symlinks. It does not stage files automatically.

Before first use, review and trust this repository's hook in Codex via `/hooks` (Settings > Hooks in the desktop app). New or modified hooks do not run until trusted. See the [official hooks documentation](https://learn.chatgpt.com/docs/hooks).
