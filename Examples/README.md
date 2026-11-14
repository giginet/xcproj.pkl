# Examples

Each example uses `Main.pkl` as its entry point. The shared `PklProject` references `Pkl/xcproj` in this checkout as a local dependency, so the examples work before a package is published on GitHub Releases. The CLI runs `pkl project resolve` to resolve dependencies.

Run these commands from the repository root:

```sh
swift run xcprojgen validate Examples/Tool
swift run xcprojgen generate Examples/Tool --output-dir /tmp/xcprojgen-tool

swift run xcprojgen validate Examples/Workspace
swift run xcprojgen generate Examples/Workspace

swift run xcprojgen validate Examples/iOS
swift run xcprojgen generate Examples/iOS --output-dir /tmp/xcprojgen-ios
```

`Tool` is a macOS command-line tool. `Workspace` groups three framework projects and their tests. Even when the workspace is generated in another directory, its member projects are generated in their respective `projectDir` directories.

[Advanced](Advanced/README.md) is a macOS tool that combines a local Swift package, pre- and post-build scripts, and a shared scheme. Generate it with `swift run xcprojgen generate Examples/Advanced --output-dir /tmp/xcprojgen-advanced`.

## Mixing generated and existing projects

`MixedWorkspace/Main.pkl` combines the Pkl project in `Tool/Main.pkl` with the checked-in legacy `MixedWorkspace/Legacy.xcodeproj`:

```pkl
amends "@xcproj/Workspace.pkl"
import "../Tool/Main.pkl" as Tool

name = "Mixed"
projects {
  ["tool"] = Tool
  ["legacy"] = module.importXcodeproj("Legacy.xcodeproj")
}
```

`Legacy` has an aggregate target and an existing shared scheme. It needs no source files or signing. Generation writes `Tool/Tool.xcodeproj` and the workspace, while leaving the existing project and scheme unchanged. The example's generated `Hello` workspace scheme selects `tool/hello`; Xcode also discovers the existing `Legacy` scheme.

```sh
swift run xcprojgen validate Examples/MixedWorkspace
swift run xcprojgen generate Examples/MixedWorkspace --output-dir /tmp/xcprojgen-mixed
swift run xcprojgen validate /tmp/xcprojgen-mixed/Mixed.xcworkspace
xcrun xcodebuild -list -workspace /tmp/xcprojgen-mixed/Mixed.xcworkspace
xcrun xcodebuild -workspace /tmp/xcprojgen-mixed/Mixed.xcworkspace -scheme Legacy build
xcrun xcodebuild -workspace /tmp/xcprojgen-mixed/Mixed.xcworkspace -scheme Hello build
```

`importXcodeproj` also accepts JSON project bundles and absolute paths. Relative paths use `workspaceDir`; `--output-dir` rebases the workspace reference without relocating the existing project. For an existing-only workspace, omit the `tool` entry and generated `Hello` scheme. Existing target definitions are not exposed as Pkl objects, so generated schemes cannot select those targets.

```sh
PKL_EXEC="$(command -v pkl)" bash Scripts/mixed-workspace-smoke-test.sh
```

This smoke test copies the example and its local Pkl dependency to a temporary directory, generates and validates the workspace, builds both `Hello` and `Legacy`, and checks the executable's output. It also verifies that generation and Xcode builds preserve the imported project and shared scheme's contents.

## Smoke tests

GitHub Actions runs each example's smoke test separately. Each script builds `xcprojgen`, validates the Pkl input, generates and validates the output, and runs `xcodebuild`. They require Pkl on `PATH` (or `PKL_EXEC`) and Xcode 27.2 or later.

| Script | Additional checks |
|---|---|
| `Scripts/smoke-test.sh` | Runs the generated `Hello` tool. |
| `Scripts/workspace-smoke-test.sh` | Builds all three frameworks and their hostless test bundles. |
| `Scripts/ios-smoke-test.sh` | Builds for iOS Simulator and verifies embedded frameworks and the notification extension. |
| `Scripts/advanced-smoke-test.sh` | Checks local Swift package linkage, executable output, and pre/post-build script results. |
| `Scripts/mixed-workspace-smoke-test.sh` | Builds generated and legacy projects and verifies that imported files are unchanged. |

For example:

```sh
PKL_EXEC="$(command -v pkl)" bash Scripts/smoke-test.sh
```

The framework and iOS scripts compile their test bundles; they do not execute those bundles.

## Swift 6 and a Notification Service Extension

`Swift6Framework` in `Shared/Templates.pkl` extends `Target` from the public schema. The `compiler` settings imported from `Shared/Settings.pkl` set `SWIFT_VERSION = "6.0"`, so the generated frameworks use Swift 6 language mode.

`ExtensionSafeFramework extends Swift6Framework` adds `APPLICATION_EXTENSION_API_ONLY = YES`. `iOS/Main.pkl` uses these classes to create the following six targets:

| Target | Template | Dependencies |
|---|---|---|
| DemoCore | ExtensionSafeFramework | None |
| DemoNetworking | Swift6Framework | DemoCore |
| DemoNotifications | ExtensionSafeFramework | DemoCore |
| DemoApp | App | All three frameworks, DemoNotificationService |
| DemoNotificationService | NotificationService | DemoNotifications |
| DemoCoreTests | UnitTests | DemoCore |

DemoApp embeds the three frameworks in `Frameworks/` and the notification extension in `PlugIns/`. The extension is declared as an app dependency with `link = false; embed = true`. Both DemoApp's startup code and the extension call APIs from the shared frameworks.

`NotificationService` is a target template that sets `type = "app-extension"` and `infoPlist`. The `infoPlist` path is relative to the project's `projectDir`; Pkl rebases `INFOPLIST_FILE` when the output directory changes.

This example uses [UNNotificationServiceExtension](https://developer.apple.com/documentation/usernotifications/unnotificationserviceextension) to modify an incoming notification's title through shared code, then calls the completion handler synchronously. It does not include APNs signing, provisioning, or server configuration. To use it with real remote notifications, enable Push Notifications for the app and send a payload containing `aps.alert` and `aps.mutable-content = 1`. See Apple's [guide to modifying notification content](https://developer.apple.com/documentation/usernotifications/modifying-content-in-newly-delivered-notifications).

```sh
# Verify an unsigned iOS Simulator build and embedded products.
PKL_EXEC="$(command -v pkl)" bash Scripts/ios-smoke-test.sh
```

This script builds the app, extension, frameworks, and test bundle. It does not deliver notifications or run the test bundle.
