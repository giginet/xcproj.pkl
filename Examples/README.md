# Examples

各例の入口は `Main.pkl` です。共通の `PklProject` はcheckout内の `Pkl/xcproj` をlocal dependencyとして指定しているため、GitHub Releaseの公開前でも使えます。CLIが `pkl project resolve` を実行し、依存を解決します。

リポジトリルートから実行してください。

```sh
swift run xcprojgen validate Examples/Tool
swift run xcprojgen generate Examples/Tool --output-dir /tmp/xcprojgen-tool

swift run xcprojgen validate Examples/Workspace
swift run xcprojgen generate Examples/Workspace

swift run xcprojgen validate Examples/iOS
swift run xcprojgen generate Examples/iOS --output-dir /tmp/xcprojgen-ios
```

`Tool` はmacOSのCLI、`Workspace` は3つのFramework Projectと各テストをまとめる例です。Workspaceを別ディレクトリへ生成しても、メンバーのProjectは各 `projectDir` に生成します。

## Swift 6とNotification Service Extension

`Shared/Templates.pkl` の `Swift6Framework` は公開スキーマの `Target` を継承します。`Shared/Settings.pkl` からimportする `compiler` に `SWIFT_VERSION = "6.0"` があり、生成するFrameworkはSwift 6モードになります。

`ExtensionSafeFramework extends Swift6Framework` は `APPLICATION_EXTENSION_API_ONLY = YES` を追加します。`iOS/Main.pkl` はこれらのクラスから次の6ターゲットを作成します。

| ターゲット | テンプレート | 依存先 |
|---|---|---|
| DemoCore | ExtensionSafeFramework | なし |
| DemoNetworking | Swift6Framework | DemoCore |
| DemoNotifications | ExtensionSafeFramework | DemoCore |
| DemoApp | App | 3つのFramework、DemoNotificationService |
| DemoNotificationService | NotificationService | DemoNotifications |
| DemoCoreTests | UnitTests | DemoCore |

DemoAppは3つのFrameworkを `Frameworks/` に、通知Extensionを `PlugIns/` に埋め込みます。Extensionは `link = false; embed = true` としてアプリの依存に指定します。DemoAppの起動処理とExtensionの処理は、共有FrameworkのAPIを実際に呼び出します。

`NotificationService` は `type = "app-extension"` と `infoPlist` を指定したTargetテンプレートです。`infoPlist` のパスは各Projectの `projectDir` 基準で、生成先を変更するとPklが `INFOPLIST_FILE` をリベースします。

この例は [UNNotificationServiceExtension](https://developer.apple.com/documentation/usernotifications/unnotificationserviceextension) を使い、受信した通知のタイトルを共有コードで加工して、同期的に完了ハンドラーを呼びます。APNsの署名・プロビジョニング・サーバー設定は含みません。実際のリモート通知で動作させる場合は、アプリ側のPush Notifications設定と、`aps.alert`・`aps.mutable-content = 1` を含むpayloadが必要です。[通知加工の公式ガイド](https://developer.apple.com/documentation/usernotifications/modifying-content-in-newly-delivered-notifications)

```sh
# iOS Simulator向けの署名なしビルドと埋め込みを確認します。
PKL_EXEC="$(command -v pkl)" bash Scripts/ios-smoke-test.sh
```

このスクリプトはアプリ・Extension・Framework・テストbundleをビルドします。通知の配信やテストbundleの実行は行いません。
