# Projects inside a Workspace

For a small workspace, `xcprojgen init --type workspace` puts the templates and
member projects inside `Project.pkl`. Inline project paths are relative to that
entry file. For a larger workspace, use one Pkl module per Xcode project and
import them from the workspace entry:

```text
PklProject
Project.pkl
Templates/FrameworkProject.pkl
Modules/Core/Project.pkl
Modules/Core/Sources/
Modules/Core/Tests/
Modules/Networking/Project.pkl
Modules/Networking/Sources/
Modules/Networking/Tests/
```

The root `PklProject` supplies the `@xcproj` dependency to these modules.

`Templates/FrameworkProject.pkl` defines a reusable Project module:

```pkl
open module templates.FrameworkProject
extends "@xcproj/Project.pkl"

open class SwiftTarget extends Target {
  platform = "macOS"
  deploymentTarget = "14.0"
  settings { base { ["SWIFT_VERSION"] = "6.0" } }
}

bundleIdPrefix = "com.example.\(name)"
targets {
  ["framework"] = new SwiftTarget {
    name = module.name
    type = "framework"
    sources { new { path = "Sources" } }
  }
  ["tests"] = new SwiftTarget {
    name = "\(module.name)Tests"
    type = "bundle.unit-test"
    sources { new { path = "Tests" } }
    dependencies { new { target = "framework" } }
  }
}
```

`Modules/Core/Project.pkl` instantiates it (use `name = "Networking"` in the
Networking module):

```pkl
amends "../../Templates/FrameworkProject.pkl"
name = "Core"
```

The root `Project.pkl` collects both Projects and optionally defines a shared scheme:

```pkl
amends "@xcproj/Workspace.pkl"

name = "Libraries"
projects {
  ["core"] = import("Modules/Core/Project.pkl")
  ["networking"] = import("Modules/Networking/Project.pkl")
}
schemes {
  ["Core"] {
    build { targets { new { target = "core/framework" } } }
    test = new { targets { new { target = "core/tests" } } }
  }
}
```

Run `xcprojgen validate` and `xcprojgen generate` at the root. This creates
`Libraries.xcworkspace` and each project beside its Project module.
Generate a single project with
`xcprojgen generate Modules/Core/Project.pkl`.

For many projects, use `projects = import*("Modules/*/Project.pkl")`.
Glob imports use matched paths as keys; explicit imports allow short aliases
for scheme targets.

## Output paths and existing projects

`workspaceDir` defaults to the workspace module's directory.
`--output-dir Build/Generated` writes `Build/Generated/Libraries.xcworkspace`
relative to the working directory; member projects keep their own output paths.

To include an existing project, add this entry to `projects`:

```pkl
["legacy"] = module.importXcodeproj("Vendor/Legacy.xcodeproj")
```

`module.importXcodeproj` resolves relative paths from `workspaceDir` and also
accepts absolute paths. The directory must exist. Xcode uses the referenced
project and its existing shared schemes.
