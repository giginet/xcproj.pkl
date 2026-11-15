# xcproj Pkl package

Typed authoring schemas for `xcprojgen` (schema version 2, Pkl 0.33+).

- `Project.pkl`: project module class; exports `Target`, `Settings`, `Source`, and `Dependency`.
- `Workspace.pkl`: workspace module class, collecting local Project modules and existing Xcode project references.
- `Internal/`: implementation dependencies required by the public modules and Swift CLI renderer; not a stable public API.
- `PklProject`: package identity, version, artifact URL, and API tests.

Consumer example, once the artifacts have been published:

```pkl
// PklProject
amends "pkl:Project"
dependencies {
  ["xcproj"] {
    uri = "package://github.com/giginet/xcproj.pkl/releases/download/v0.1.0/xcproj@0.1.0"
  }
}
```

Resolve dependencies with `pkl project resolve`. Then define a local Main.pkl:

```pkl
amends "@xcproj/Project.pkl"
name = "Tool"
targets {
  ["hello"] {
    name = "Hello"
    type = "tool"
    platform = "macOS"
    sources { new { path = "Sources" } }
  }
}
```

Use `import "@xcproj/Project.pkl" as X` to define reusable classes extending `X.Target` and reusable `X.Settings` objects. For a workspace, Main.pkl can amend `@xcproj/Workspace.pkl` and import local Project modules. The CLI defaults to `<dir>/Main.pkl`; `--entry` selects another module relative to `<dir>`. Run the resulting local entry through the matching Swift CLI; evaluating the public schemas produces an intermediate Snapshot, not the final Xcode project.

To include an existing `.xcodeproj` bundle, use the workspace's `importXcodeproj(path)` function:

```pkl
amends "@xcproj/Workspace.pkl"
import "Projects/App/Project.pkl" as App

name = "AppWorkspace"
projects {
  ["app"] = App
  ["legacy"] = module.importXcodeproj("Vendor/Legacy.xcodeproj")
}
```

The return type is `ExistingProject`; `projects` accepts either it or a `Project` module. A workspace may contain only existing projects. Relative paths use `workspaceDir`, and absolute paths are accepted. `--output-dir` changes workspace references without moving, converting, or rewriting imported bundles or their schemes. Duplicate canonical references and collisions with generated output are rejected.

Imported paths must identify existing `.xcodeproj` directories. Their contents are opaque: neither `project.xcproj` nor `project.pbxproj` is required or parsed. Imported targets are not exposed as Pkl `Target` objects and cannot be selected by generated schemes; existing shared schemes remain available in Xcode. Importing a project does not create target dependencies. CLI project counts include imported members; target counts include generated targets only.

Direct `.xcworkspace` validation checks XML membership and project directories, reporting only the project count. Direct `.xcodeproj` or `project.xcproj` validation checks JSON project contents; direct legacy `project.pbxproj` validation is unsupported.

Targets support `application`, `framework`, `tool`, `bundle`, `bundle.unit-test`, and `app-extension` product types. To embed an extension in an application, add a dependency with `link = false` and `embed = true`. Framework dependencies may be linked and embedded independently. An optional `infoPlist` names an existing file relative to `projectDir`; the renderer sets `INFOPLIST_FILE` relative to the generated project and disables automatic plist generation. The repository's `Examples/iOS` demonstrates inherited Swift 6 framework targets, an application, and a notification service extension.

The public module also exports typed counterparts for the complete `xcode-project-format` 0.1.0 schema families: local/remote Swift packages and all version constraints, build tool plugins and package products, local/remote target dependencies, ordered build phases and scripts, build rules, file/group/folder/variant/version references and build-file attributes, configuration IDs, localization and project/target metadata. `TargetKind`, `ProductType`, `Platform`, phase kinds/scopes, and other closed choices are named string unions. `fullProductType` with explicit product filename/type supports custom product identifiers. `aggregate` and `external-build-system` target kinds are available alongside `native`.

Use `packages` as a mapping of aliases to `LocalSwiftPackage` or `RemoteSwiftPackage`, and target `dependencies { new { package = "alias"; product = "ProductName" } }` to link a product. Local package paths are relative to `projectDir` and rebased when output moves. Package reference names preserve the case of the repository/path basename (without `.git`), which is distinct from `Package.name`. Low-level `files`, raw target dependencies, and script paths retain Xcode's own path/reference syntax.

`preBuildScripts` / `postBuildScripts` wrap the default phases; an explicit `buildPhases` listing replaces those default phases in the given order. Project and Workspace `schemes` mappings produce shared `.xcscheme` XML files, supporting Build, Run, Test, Profile, Analyze and Archive actions, arguments, environment variables and pre/post actions. A project scheme references target keys; a workspace scheme references `project-key/target-key`. Schemes are separate artifacts, outside the upstream JSON schema. See the repository's `Docs/SchemaCoverage.md` for the field-by-field mapping and `Examples/Advanced` for a runnable package/script/scheme example.

`xcprojgen generate <dir> --output-dir <directory>` writes `<directory>/<name>.xcodeproj` or `<directory>/<name>.xcworkspace`, according to the selected entry's Pkl type and `name`. Generated workspace members retain their own project output directories; existing members retain their original locations. Without `--output-dir`, `projectDir` or `workspaceDir` determines the output directory.

For checkout-based development, a consumer may use a local dependency instead:

```pkl
amends "pkl:Project"
dependencies {
  ["xcproj"] = import("/path/to/xcproj.pkl/Pkl/xcproj/PklProject")
}
```

From the repository root:

```sh
# API tests, archive, metadata, and checksums.
Scripts/package-pkl.sh

# Local/offline packaging (no published-version lookup).
Scripts/package-pkl.sh --skip-publish-check
```

The output is `dist/pkl/xcproj@0.1.0/` with four files: `xcproj@0.1.0.zip`, `xcproj@0.1.0`, and their `.sha256` sidecars. The ZIP contains package-root modules and README; tests and project manifests are excluded. Swift sources and application-specific examples are outside this package directory.

Publication layout is configured for GitHub Releases tag `v0.1.0`. Upload all four artifacts to that release: the package URI's HTTPS equivalent serves metadata, and `packageZipUrl` serves the archive. No upload or release creation is performed here. These URLs describe a future accessible GitHub Release. The repository is currently private and hosting has not been configured; choose metadata and ZIP URLs that consumers can actually retrieve before publishing. Local cache installation and local dependencies do not require publishing.

Official specifications:

- [Creating a package and local dependencies](https://pkl-lang.org/main/current/language-reference/index.html#creating-a-package)
- [pkl project package](https://pkl-lang.org/main/current/pkl-cli/index.html#pkl-project-package)
- [Package metadata, exclusions, and API tests](https://pkl-lang.org/package-docs/pkl/current/Project/Package.html)
