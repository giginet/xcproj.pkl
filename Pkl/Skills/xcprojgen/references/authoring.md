# Authoring xcproj Pkl

## Modules, classes, and shared settings

Use the public `@xcproj/Project.pkl` and `@xcproj/Workspace.pkl` modules.
`Internal/` is an implementation detail. Public module evaluation produces an
intermediate snapshot; use `xcprojgen generate` to create Xcode bundles.

Reusable target templates are Pkl classes (`open class ... extends X.Target`).
Instantiate them with `new Templates.Framework { ... }`. Reuse settings as typed
`X.Settings` objects and amend them with `(Common.compiler) { ... }`. There are
no XcodeGen-style `targetTemplates` or `settingGroups` lookup tables.

For example, put these two modules next to the project's `Main.pkl`.

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
  settings = Common.compiler
  sources { new { path = "Sources/\(target.name)" } }
}

open class ExtensionSafeFramework extends Swift6Framework {
  settings { base { ["APPLICATION_EXTENSION_API_ONLY"] = "YES" } }
}
```

The `local target = this` binding lets nested source/settings objects refer to
the target's amended `name`. Pkl derives the path after specialization.
`settings { ... }` amends inherited settings. `sources { new { ... } }` appends
to an inherited listing; `sources = new Listing { ... }` replaces it. Use a new
listing when replacing inherited dependencies or build phases as well.

`Main.pkl`:

```pkl
amends "@xcproj/Project.pkl"
import "Templates.pkl" as Templates

name = "Libraries"
idNamespace = "com.example.libraries"

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

Create/adapt the source directories before validating. Mapping keys such as
`core` identify dependencies and scheme targets; `name` is the Xcode target
name. Keep keys and `idNamespace` stable when renaming display names to avoid
unnecessary identity changes.

## Paths and common target choices

`projectDir` defaults to the directory of the Project module. Source folders,
`infoPlist`, and local Swift package paths are relative to `projectDir`.
`sources { new { path = "Sources" } }` declares a folder; use
`kind = "file"` for an individual source file. Low-level Xcode file references
and script paths retain Xcode's own path syntax.

`Target.type` and `Target.platform` are case-sensitive string unions. Common
types are `application`, `framework`, `tool`, `bundle.unit-test`,
`bundle.ui-testing`, and `app-extension`; platforms include `iOS`, `macOS`,
`tvOS`, `watchOS`, and `visionOS`. Build settings accept strings or
`Listing<String>`, so use `"YES"`, `"NO"`, and `"6.0"` rather than booleans or
numbers. Configure shared values in `settings.base` and per-configuration values
in `settings.configs["Debug"].base`. Project `configs` maps names to `"debug"`
or `"release"`; its defaults are Debug and Release.

For an app, use `type = "application"`. A notification service extension uses
`type = "app-extension"` with an `infoPlist` path to a real plist declaring its
extension point and principal class. On the app target, embed it with
`dependencies { new { target = "notifications"; link = false; embed = true } }`.
Use `embed = true` for linked dynamic frameworks the app must contain. Shared
extension code should use extension-safe framework settings. See the matching
release's `Examples/iOS` for the complete app/extension configuration and plist.

## Swift packages, scripts, and schemes

Declare Swift packages in a Project's `packages` mapping, then select a product
in target dependencies. Merge these entries into the existing mappings; each
property can be declared once in a Pkl object. For a local package:

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

The package alias and Swift product name are different identifiers. Remote
packages use `RemoteSwiftPackage`; inspect the installed public schema's typed
version constraints before choosing one. Xcode resolves Swift packages during
builds, independently of the Pkl package resolved by `xcprojgen`.

Use `preBuildScripts` or `postBuildScripts` for script phases surrounding the
default phases. Specify `name`, `script`, and the actual `inputPaths` /
`outputPaths` needed for dependency analysis and sandboxing. An explicit
`buildPhases` listing replaces the generated phase order entirely.

`schemes` generates shared `.xcscheme` files with build, run, test, profile,
analyze, and archive actions. Project schemes use local target keys; workspace
schemes use `project-key/target-key`. A runnable scheme needs an appropriate
`run` target; the framework/test scheme above intentionally has no run action.
