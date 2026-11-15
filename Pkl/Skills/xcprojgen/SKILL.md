---
name: xcprojgen
description: Create and maintain Xcode projects with Pkl and xcprojgen. Use when generating .xcodeproj projects or .xcworkspace workspaces, authoring Main.pkl, defining reusable target templates, or sharing build settings across targets and projects.
---

# xcprojgen

Edit the Pkl source of truth, then use `xcprojgen` to generate Xcode bundles.
These instructions accompany the CLI's bundled xcproj schemas and renderer.

## Choose the entry point

Inspect the existing `PklProject`, `Main.pkl`, and imported modules before
changing a configuration. Keep the project's chosen package dependency and
organization unless the task calls for changing them.

- `xcprojgen generate` uses `Main.pkl` in the current directory.
- `xcprojgen generate <dir>` uses `<dir>/Main.pkl`.
- `xcprojgen generate <file.pkl>` uses that module directly.
- `validate` accepts the same inputs.

`Main.pkl` is the CLI's default entry point. Amending `@xcproj/Project.pkl`
generates one `.xcodeproj`; amending `@xcproj/Workspace.pkl` generates a
`.xcworkspace` and its Pkl-defined member projects. The module's `name` determines
the bundle name. `--output-dir` accepts a directory, not a bundle filename;
there is no `--entry` option.

## Create or update a project

Check the toolchain with `xcprojgen doctor`. It checks Pkl 0.33.0+ and the selected
Xcode's `xcodeproj` and `xcprojformatter` tools. If the Xcode tools are missing,
install/select Xcode 27.2 or later using `xcode-select` or `DEVELOPER_DIR`. Use
`--pkl <path>` or `PKL_EXEC` when Pkl is not on `PATH`.

For a new configuration, scaffold the requested shape:

```sh
xcprojgen init MyLibrary --type project
xcprojgen init MyWorkspace --type workspace
```

Choose one command for the requested result. `init` refuses to overwrite files.
It creates `PklProject` with a versioned `xcproj` package dependency, `Main.pkl`,
templates, and sample Swift sources. Adapt those sources to the real project;
preserve existing application code. `validate` and `generate` resolve package
dependencies automatically, so the configured package release must be accessible.

- For targets, inheritance, settings, sources, and dependencies, read
  [Pkl authoring](references/authoring.md).
- For reusable Project modules, multiple projects, existing `.xcodeproj`
  imports, and workspace schemes, read [Workspaces](references/workspaces.md).

## Validate, generate, and build

```sh
xcprojgen validate MyLibrary
xcprojgen generate MyLibrary
xcprojgen generate MyWorkspace --output-dir Build/Generated
```

`validate` checks Pkl evaluation and the generation plan. It does not validate
generated Xcode bundles or compile Swift. `generate` formats generated projects
with `xcprojformatter` and leaves identical files untouched. Fix configuration
errors in Pkl and regenerate.

When build verification is part of the task, list the generated bundle's schemes
with `xcrun xcodebuild -list -project <name>.xcodeproj` or
`-workspace <name>.xcworkspace`, then build the intended scheme and destination.
An iOS Simulator build does not demonstrate device signing or runtime behavior.

Consult the [xcproj Pkl API reference (pkldoc)](https://giginet.github.io/xcproj.pkl/)
for public types and properties. The hosted reference tracks `main`; check the
public schema at the matching release tag when using an older package or when
the hosted reference is unavailable. The repository's
[package guide](https://github.com/giginet/xcproj.pkl/blob/main/Pkl/xcproj/README.md)
and [examples](https://github.com/giginet/xcproj.pkl/tree/main/Examples) cover
additional features. Pkl's [language reference](https://pkl-lang.org/main/current/language-reference/index.html)
explains the underlying amendment and inheritance semantics.
