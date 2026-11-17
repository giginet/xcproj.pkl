---
name: xcprojgen
description: Create Xcode projects and workspaces with Pkl and xcprojgen. Use when generating .xcodeproj or .xcworkspace bundles, defining target templates, or sharing build settings.
---

# xcprojgen

## Synchronize this skill

Once per session, run `xcprojgen skills export "<output-dir>"`. Use the absolute
path of the parent of the `xcprojgen` directory containing the loaded `SKILL.md`.
On `Updated`, notify the user, reread this file and any loaded references, then
resume the task.
If synchronization fails, report it and continue with the available instructions.
Skip synchronization when editing this skill's sources in the xcproj.pkl repository.

## Choose the entry point

- `xcprojgen generate` uses `Project.pkl` in the current directory.
- `xcprojgen generate <dir>` uses `<dir>/Project.pkl`.
- `xcprojgen generate <file.pkl>` uses that module directly.
- `validate` accepts the same inputs.

Amend `@xcproj/Project.pkl` for a `.xcodeproj`, or `@xcproj/Workspace.pkl` for a
`.xcworkspace` and its projects. The module's `name` determines the bundle name;
`--output-dir` selects the destination directory.

## Create or update a project

Run `xcprojgen doctor` to check Pkl and Xcode tools. For a new configuration,
choose a project or workspace scaffold:

```sh
xcprojgen init
xcprojgen init MyLibrary
xcprojgen init MyWorkspace --type workspace
```

`init` defaults to a project in the current directory. It creates only `PklProject`
and `Project.pkl`, with target templates and project definitions in the entry file.
Workspace scaffolds define their member projects inline. Add references to your
existing sources in `Project.pkl`, then validate and generate:

```sh
xcprojgen validate MyLibrary
xcprojgen generate MyLibrary
xcprojgen generate MyWorkspace --output-dir Build/Generated
```

`validate` checks Pkl evaluation and the generation plan. Both commands resolve
package dependencies. Use `xcrun xcodebuild` for build verification.

## References

- [Pkl authoring](references/authoring.md): target inheritance, settings mixins,
  dependencies, and schemes.
- [Workspaces](references/workspaces.md): reusable Projects and existing project imports.
- [Pkl API reference (main)](https://giginet.me/xcproj.pkl/)
- [Examples](https://github.com/giginet/xcproj.pkl/tree/main/Examples)
- [Pkl language reference](https://pkl-lang.org/main/current/language-reference/index.html)
