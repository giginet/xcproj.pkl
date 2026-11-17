# Authoring xcproj Pkl

## Modules, classes, and shared settings

Define target templates with `extends`, specialize objects with amendments, and
combine `Mixin<X.Settings>` values with `|>`. Put these modules next to `Project.pkl`.

`Settings.pkl`:

```pkl
import "@xcproj/Project.pkl" as X

compiler: X.Settings = new {
  base {
    ["SWIFT_VERSION"] = "6.0"
    ["OTHER_SWIFT_FLAGS"] = new Listing { "$(inherited)"; "-DTEAM" }
  }
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

`Templates.pkl`:

```pkl
import "@xcproj/Project.pkl" as X
import "Settings.pkl" as Common

open class Swift6Framework extends X.Target {
  local target = this
  type = "framework"
  platform = "macOS"
  deploymentTarget = "14.0"
  settings = Common.compiler |> Common.warnings
  sources { new { path = "Sources/\(target.name)" } }
}

open class ExtensionSafeFramework extends Swift6Framework {
  settings = super.settings |> Common.extensionSafe
}
```

Mixins apply left to right; later assignments to the same key win.
`super.settings` retains inherited settings. Amending `base` and `configs`
preserves existing entries, including both Debug settings in this example.
These mixins work on project and target settings.

`local target = this` lets nested objects use the target's specialized `name`.
`sources { new { ... } }` appends to the inherited listing;
`sources = new Listing { ... }` replaces it.

`Project.pkl`:

```pkl
amends "@xcproj/Project.pkl"
import "Templates.pkl" as Templates

name = "Libraries"
bundleIdPrefix = "com.example.libraries"

targets {
  ["core"] = new Templates.ExtensionSafeFramework { name = "Core" }
  ["networking"] = new Templates.Swift6Framework {
    name = "Networking"
    dependencies { new { target = "core" } }
  }
  ["tests"] {
    name = "CoreTests"
    type = "bundle.unit-test"
    platform = "macOS"
    deploymentTarget = "14.0"
    sources { new { path = "Tests/CoreTests" } }
    dependencies { new { target = "core" } }
  }
}

schemes {
  ["Libraries"] {
    build { targets { new { target = "core" }; new { target = "networking" } } }
    test = new { targets { new { target = "tests" } } }
  }
}
```

Create the source directories before validating. Mapping keys such as `core`
identify dependencies and scheme targets; `name` is the Xcode target name.

## Paths and common target choices

`projectDir` defaults to the directory of the Project module. Source folders,
`infoPlist`, and local Swift package paths are relative to `projectDir`.
Sources default to folders; use `kind = "file"` for an individual file.

`Target.type` and `Target.platform` are case-sensitive string unions. Common
types are `application`, `framework`, `tool`, `bundle.unit-test`,
`bundle.ui-testing`, and `app-extension`; platforms include `iOS`, `macOS`,
`tvOS`, `watchOS`, and `visionOS`.

Build settings accept `String` or `Listing<String>`, including `"YES"`, `"NO"`,
and `"6.0"`. Use `settings.base` for shared values and
`settings.configs["Debug"].base` for configuration overrides. Project `configs`
maps names to `"debug"` or `"release"` and defaults to Debug and Release.

Use `embed = true` for framework dependencies to bundle with an app. Embed an
extension with `link = false; embed = true`. See
[Examples/iOS](https://github.com/giginet/xcproj.pkl/tree/main/Examples/iOS)
for the app, notification service extension, and plist configuration.

## Swift packages, scripts, and schemes

Declare packages in `packages` and select products in target dependencies.
Add these entries to the existing mappings:

```pkl
packages {
  ["support"] = new LocalSwiftPackage { path = "Packages/Support" }
}
targets {
  ["networking"] {
    dependencies { new { package = "support"; product = "SupportCore" } }
  }
}
```

`package` is the mapping key; `product` is the Swift package's product name.
Remote packages use `RemoteSwiftPackage`.

Use `preBuildScripts` or `postBuildScripts` with `name`, `script`, `inputPaths`,
and `outputPaths`. An explicit `buildPhases` listing replaces the default phases.

`schemes` generates shared `.xcscheme` files. Project schemes use target keys;
workspace schemes use `project-key/target-key`.
