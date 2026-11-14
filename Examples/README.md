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
