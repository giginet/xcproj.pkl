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

Use the `xcprojgen` CLI to create a Pkl project, define its targets, and generate Xcode projects or workspaces. Run the following steps from the directory where you want to create `MyApp`.

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

This creates only `MyApp/PklProject` and `MyApp/Project.pkl`. The first declares the `xcproj` package dependency; the second contains the target templates and project definition. To initialize the current directory, run `xcprojgen init` without a path. Existing files are never overwritten.

### 5. Edit Project.pkl

Replace `MyApp/Project.pkl` with the following to name the project and its targets `MyApp`, enable Swift 6, and share iOS settings between the framework and its tests:

```pkl
amends "@xcproj/Project.pkl"
import "@xcproj/Project.pkl" as X

local open class BaseTarget extends X.Target {
  platform = "iOS"
  deploymentTarget = "17.0"
  settings { base { ["SWIFT_VERSION"] = "6.0" } }
}

local class Framework extends BaseTarget { type = "framework" }
local class UnitTests extends BaseTarget { type = "bundle.unit-test" }

name = "MyApp"
bundleIdPrefix = "com.example.myapp"
targets {
  ["framework"] = new Framework {
    name = "MyApp"
    sources { new { path = "MyApp" } }
  }
  ["tests"] = new UnitTests {
    name = "MyAppTests"
    sources { new { path = "MyAppTests" } }
    dependencies { new { target = "framework" } }
  }
}
```

`@xcproj` refers to the dependency declared in `PklProject`. Change `platform` and `deploymentTarget` in `BaseTarget` to configure both targets. The project name determines the bundle name, `MyApp.xcodeproj`.

`init` does not generate source files. Place your files in `MyApp/` and `MyAppTests/` alongside `Project.pkl` before validating or generating. The `sources` entries add references to files in those directories and their subdirectories to the corresponding targets. Change each `path` to use a different source directory.

### 6. Validate the Pkl project

```sh
xcprojgen validate MyApp
```

This resolves the package dependencies and validates the configuration without writing Xcode bundles.

### 7. Generate the project

```sh
xcprojgen generate MyApp
```

This creates `MyApp/MyApp.xcodeproj`. Each generated `project.xcproj` is formatted with `xcprojformatter`; repeated generation leaves unchanged files untouched.

### 8. Open the project

```sh
(cd MyApp && open MyApp.xcodeproj)
```

### Agent skill

Export the bundled [Agent Skills](https://agentskills.io/specification) instructions
into your agent's skills directory:

```sh
xcprojgen skills export .agents/skills
```

## Advanced Usage

### Other CLI options

```sh
# Generate from Project.pkl in the current directory
(cd MyApp && xcprojgen generate)

# Specify the output directory
xcprojgen generate MyApp --output-dir /tmp/generated

# Generate from an explicitly selected Pkl file
xcprojgen generate MyApp/Project.pkl
```

`generate [path]` selects the entry point from its optional argument:

- No argument: `Project.pkl` in the current working directory.
- Directory: `Project.pkl` inside that directory.
- `.pkl` file: that file itself.

Relative paths are resolved from the current working directory. To use another entry point, pass its `.pkl` file path directly.

`validate [path]` uses the same input rules. `init [dir]` defaults to `--type project`; use `--type workspace` for a workspace entry.

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

Import the templates from `Project.pkl` and specify the name and dependencies for each target.

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

### Initialize a Workspace

```sh
xcprojgen init MyWorkspace --type workspace
```

This creates `PklProject` and a `Project.pkl` that amends `@xcproj/Workspace.pkl`, with the target templates and member project defined inline. Edit `Project.pkl`, then run:

```sh
xcprojgen validate MyWorkspace
xcprojgen generate MyWorkspace
open MyWorkspace/Workspace.xcworkspace
```

See [Examples/Workspace](./Examples/Workspace/Project.pkl) for a workspace with multiple Pkl projects, and [Examples/MixedWorkspace](./Examples/MixedWorkspace/Project.pkl) for importing existing Xcode projects. The [example guide](./Examples/README.md) includes commands to generate and build them.

## Reference

- [Pkl API reference (main)](https://giginet.me/xcproj.pkl/)
- [CI and GitHub Pages setup](./Docs/CI.md)
- [Pkl Language Reference](https://pkl-lang.org/main/current/language-reference/index.html)
- [Pkl CLI Manual](https://pkl-lang.org/main/current/pkl-cli/index.html)
- [Updating Your Xcode Project Configuration File Format (Apple Developer)](https://developer.apple.com/documentation/xcode/updating-your-xcode-project-configuration-file-format)

## License

xcproj.pkl is licensed under the [Apache License, Version 2.0](./LICENSE).
