# xcproj.pkl

[![Build and test xcprojgen](https://img.shields.io/github/actions/workflow/status/giginet/xcproj.pkl/xcprojgen.yml?branch=main&style=flat-square&logo=github&label=xcprojgen)](https://github.com/giginet/xcproj.pkl/actions/workflows/xcprojgen.yml)
[![Pkl tests](https://img.shields.io/github/actions/workflow/status/giginet/xcproj.pkl/pkl-tests.yml?branch=main&style=flat-square&logo=github&label=Pkl%20tests)](https://github.com/giginet/xcproj.pkl/actions/workflows/pkl-tests.yml)
[![Swift 6.1+](https://img.shields.io/badge/Swift-6.1%2B-FA7343?logo=swift&style=flat-square)](./Package.swift)
[![Xcode 27.2+](https://img.shields.io/badge/Xcode-27.2%2B-147EFB?logo=xcode&style=flat-square)](https://developer.apple.com/xcode/)
[![Pkl 0.33+](https://img.shields.io/badge/Pkl-0.33%2B-blue?style=flat-square)](https://pkl-lang.org/)
[![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-green?logo=swift&style=flat-square)](https://swift.org/package-manager/)
[![Documentation](https://img.shields.io/badge/Documentation-available-green?style=flat-square)](https://giginet.me/xcproj.pkl/)
[![CLI Platform: macOS 14+](https://img.shields.io/badge/CLI%20Platform-macOS%2014%2B-lightgray?logo=apple&style=flat-square)](./Package.swift)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-darkgray?style=flat-square)](./LICENSE)

> [!WARNING]
> This project is under active development. APIs, the Pkl schema, and CLI behavior may change without notice.

xcproj.pkl is a DSL for describing the `*.xcproj` JSON format. It lets you define Xcode projects using the [apple/pkl](https://github.com/apple/pkl) language.

Inspired by [XcodeGen](https://github.com/yonaskolb/XcodeGen) and [Tuist](https://tuist.dev/), this project aims to provide a declarative language for defining projects.

## Getting Started

Use the `xcprojgen` CLI to create a Pkl project, describe a workspace, and generate its Xcode bundles. Run the following steps from the directory where you want to create `MyApp`.

### 1. Prerequisites

- macOS 14 or later
- Xcode 27.2 or later
- Homebrew

### 2. Install xcprojgen

```sh
brew tap giginet/xcproj https://github.com/giginet/xcproj.pkl.git
brew install giginet/xcproj/xcprojgen
```

Homebrew also installs the required Pkl compiler (0.33.0 or later).

### 3. Check your environment

```sh
xcprojgen doctor
```

This checks the Pkl version and the availability of `xcodeproj` and `xcprojformatter` in the Xcode installation selected by `xcode-select` or `DEVELOPER_DIR`. If either Xcode tool is unavailable, install and select Xcode 27.2 or later.

### 4. Initialize a Pkl project

```sh
xcprojgen init MyApp
```

This creates `MyApp/PklProject` with the `xcproj` package dependency, a `Main.pkl` workspace entry point, shared target templates, and a sample `Core` framework project with sources and a unit-test target.

### 5. Write Main.pkl

Replace `MyApp/Main.pkl` with:

```pkl
amends "@xcproj/Workspace.pkl"

name = "MyApp"
projects {
  ["core"] = import("Projects/Core/Project.pkl")
}
```

The workspace name determines the generated bundle name, `MyApp.xcworkspace`. The imported project defines the `Core` framework and its test target; edit `MyApp/Projects/Core/Project.pkl` to customize them. `@xcproj` refers to the dependency declared in `PklProject`.

### 6. Validate the Pkl project

```sh
xcprojgen validate MyApp
```

This resolves the package dependencies and validates the configuration without writing Xcode bundles.

### 7. Generate the workspace

```sh
xcprojgen generate MyApp
```

This creates `MyApp/MyApp.xcworkspace` and `MyApp/Projects/Core/Core.xcodeproj`. Each generated `project.xcproj` is formatted with `xcprojformatter`; repeated generation leaves unchanged files untouched.

### 8. Open the workspace

```sh
(cd MyApp && open MyApp.xcworkspace)
```

### Other CLI options

```sh
# Generate from Main.pkl in the current directory
(cd MyApp && xcprojgen generate)

# Specify the workspace output directory
xcprojgen generate MyApp --output-dir /tmp/generated

# Generate from a specific Pkl file
xcprojgen generate MyApp/Projects/Core/Project.pkl

# Create and generate a standalone project
xcprojgen init MyLibrary --type project
xcprojgen generate MyLibrary
open MyLibrary/Core.xcodeproj
```

`generate [path]` selects the entry point from its optional argument:

- No argument: `Main.pkl` in the current working directory.
- Directory: `Main.pkl` inside that directory.
- `.pkl` file: that file itself.

Relative paths are resolved from the current working directory. To use another entry point, pass its `.pkl` file path directly.

`validate [path]` uses the same input rules.

### Agent skill

Export the bundled [Agent Skills](https://agentskills.io/specification) instructions
into your agent's skills directory:

```sh
xcprojgen skills export .agents/skills
```

## Advanced Project Examples

### Target Template Inheritance

Pkl's language features let you describe complex Xcode projects concisely. For example, object amendments let you create multiple targets from a shared template.

Define the shared settings in `Templates.pkl`.

```pkl
import "@xcproj/Project.pkl" as X

open class Framework extends X.Target {
  local target = this
  type = "framework"
  platform = "iOS"
  deploymentTarget = "17.0"
  settings { base { ["SWIFT_VERSION"] = "6.0" } }
  sources { new { path = "Sources/\(target.name)" } }
}

open class ExtensionSafeFramework extends Framework {
  settings { base { ["APPLICATION_EXTENSION_API_ONLY"] = "YES" } }
}
```

Import the templates from `Main.pkl` and specify the name and dependencies for each target.

```pkl
amends "@xcproj/Project.pkl"
import "Templates.pkl" as Templates

name = "Demo"
bundleIdPrefix = "com.example.demo"

local framework: Templates.ExtensionSafeFramework = new {}

targets {
  ["core"] = (framework) {
    name = "DemoCore"
  }
  ["networking"] = (framework) {
    name = "DemoNetworking"
    dependencies { new { target = "core" } }
  }
}
```

`extends` defines class inheritance, while `(framework) { ... }` amends an object. In this example, the targets inherit the shared settings and reference `Sources/DemoCore` and `Sources/DemoNetworking`, respectively.

### Combining Settings with Mixins

For XcodeGen-style settings groups, use Pkl's built-in
[mixins](https://pkl-lang.org/main/current/language-reference/index.html#mixins).
Define independent, typed settings changes in `Settings.pkl`:

```pkl
import "@xcproj/Project.pkl" as X

swift6: Mixin<X.Settings> = new {
  base { ["SWIFT_VERSION"] = "6.0" }
  configs { ["Debug"] { base { ["ENABLE_TESTABILITY"] = "YES" } } }
}

warnings: Mixin<X.Settings> = new {
  base { ["SWIFT_TREAT_WARNINGS_AS_ERRORS"] = "YES" }
  configs { ["Debug"] { base { ["ONLY_ACTIVE_ARCH"] = "YES" } } }
}

extensionSafe: Mixin<X.Settings> = new {
  base { ["APPLICATION_EXTENSION_API_ONLY"] = "YES" }
}
```

In `Templates.pkl` above, add `import "Settings.pkl" as Common` alongside the
other imports, and replace `Framework`'s `settings` definition with:

```pkl
settings = super.settings |> Common.swift6 |> Common.warnings |> Common.extensionSafe
```

`super.settings` preserves the parent template's settings. Use `new X.Settings {}`
instead when starting from empty settings. The same mixins work on project or
target settings, and templates can select any combination.

Mixins apply left to right; a later assignment to the same key wins. Here both
Debug settings survive because each mixin amends `configs["Debug"].base`.
Use `base { ... }` and `configs { ... }` to retain earlier entries;
`base = new Mapping { ... }` replaces the mapping. A target can further override
the result with `settings { base { ["SWIFT_TREAT_WARNINGS_AS_ERRORS"] = "NO" } }`.

See [Examples/Shared/Settings.pkl](Examples/Shared/Settings.pkl) and
[the example guide](Examples/README.md#composing-shared-settings) for this pattern
in the runnable examples.

### Generating a Workspace

You can also concisely define a `*.xcworkspace` containing multiple Xcode projects. In addition to importing other Pkl files, you can include existing Xcode projects.

The following example uses the configuration from [Examples/MixedWorkspace/Main.pkl](./Examples/MixedWorkspace/Main.pkl).

```pkl
amends "@xcproj/Workspace.pkl"
import "../Tool/Main.pkl" as Tool

name = "Mixed"
projects {
  ["tool"] = Tool
  ["legacy"] = module.importXcodeproj("Legacy.xcodeproj")
}
```

Run the following commands from the repository root to generate `Mixed.xcworkspace` and `Tool.xcodeproj` from the imported Pkl project. The existing `Legacy.xcodeproj` is added as a reference.

```sh
swift run xcprojgen validate Examples/MixedWorkspace
swift run xcprojgen generate Examples/MixedWorkspace
open Examples/MixedWorkspace/Mixed.xcworkspace
```

## Reference

- [Pkl API reference (main)](https://giginet.me/xcproj.pkl/)
- [CI and GitHub Pages setup](./Docs/CI.md)
- [Pkl Language Reference](https://pkl-lang.org/main/current/language-reference/index.html)
- [Pkl CLI Manual](https://pkl-lang.org/main/current/pkl-cli/index.html)
- [Updating Your Xcode Project Configuration File Format (Apple Developer)](https://developer.apple.com/documentation/xcode/updating-your-xcode-project-configuration-file-format)

## License

xcproj.pkl is licensed under the [Apache License, Version 2.0](./LICENSE).
