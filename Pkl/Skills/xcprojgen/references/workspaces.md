# Projects inside a Workspace

Keep one module per generated Xcode project and compose them from the workspace
entry. A useful layout for a family of framework/test projects is:

```text
PklProject
Main.pkl
Templates/FrameworkProject.pkl
Modules/Core/Project.pkl
Modules/Core/Sources/
Modules/Core/Tests/
Modules/Networking/Project.pkl
Modules/Networking/Sources/
Modules/Networking/Tests/
```

The root `PklProject` contains the `xcproj` dependency created by `init`. Project
modules below it can use the same `@xcproj` dependency.

`Templates/FrameworkProject.pkl` defines a reusable Project module:

```pkl
open module templates.FrameworkProject
extends "@xcproj/Project.pkl"

open class SwiftTarget extends Target {
  platform = "macOS"
  deploymentTarget = "14.0"
  settings { base { ["SWIFT_VERSION"] = "6.0" } }
}

idNamespace = "com.example.\(name)"
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

The root `Main.pkl` collects both Projects and optionally defines a shared scheme:

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

Run `xcprojgen validate` and `xcprojgen generate` at the workspace root.
`Libraries.xcworkspace` and the projects beside their respective Project modules
are generated. A specific project can also be generated with
`xcprojgen generate Modules/Core/Project.pkl`.

For many projects, `projects = import*("Modules/*/Project.pkl")` discovers the
modules automatically. Glob imports use the matched import paths as mapping
keys, so use explicit aliases as above when stable short keys are useful for
workspace schemes. Adding projects to a workspace does not itself create target
dependencies between them.

## Output paths and existing projects

`workspaceDir` defaults to the workspace module's directory. Passing
`--output-dir Build/Generated` changes the workspace destination to
`Build/Generated/Libraries.xcworkspace`; member projects keep their own output
directories. Relative `--output-dir` paths use the current working directory.

To include an existing project, add this entry to `projects`:

```pkl
["legacy"] = module.importXcodeproj("Vendor/Legacy.xcodeproj")
```

Use `module.importXcodeproj` inside the mapping so the receiver remains the
workspace module. Relative paths use `workspaceDir`; absolute paths also work.
The directory must already exist. Imported bundles are referenced as-is:
generation does not parse, convert, or format their contents. Their targets are
not available as Pkl objects and cannot be selected by generated schemes;
their existing shared schemes remain available in Xcode. A workspace may contain
only existing projects.
