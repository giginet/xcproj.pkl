# xcproj.pkl

PklからXcodeのJSON形式 `project.xcproj` と `xcworkspace` を生成・検証するSwift CLIです。1つのProject.pklを1つのxcodeprojとして扱い、Workspace.pklから多数のProjectをまとめて生成できます。

v2では、Targetの再利用にPklのクラス継承、Projectの再利用にmodule classと`amends`、共有設定にimportとオブジェクトのamendmentを使います。設定解決、既定値、安定ID、Xcode JSON・Workspace XMLの構築はPklが担当します。

## 必要なもの

- macOS 14以降、Swift 6.1以降。
- Pkl 0.33以降。実行ファイルの探索順は `--pkl`、`PKL_EXEC`、`PATH`。
- JSON形式のプロジェクトを扱えるXcode。検証環境はXcode 27.3 beta 1。

Pklは外部プロセスとして起動します。既存のxcproj/workspaceを検証する場合はPklのインストールは不要です。

## 実行

```sh
swift build

# 完成したJSON/XMLまで検証。成果物は書き込みません。
swift run xcproj-pkl validate Examples/Tool/Project.pkl

# 既定の projectDir/name.xcodeproj へ生成。
swift run xcproj-pkl generate Examples/Tool/Project.pkl

# 出力先を移動。ソースとxcconfigの参照もリベースします。
swift run xcproj-pkl generate Examples/Tool/Project.pkl -o /tmp/Tool.xcodeproj

# 既存ファイルを読み取り専用で検証。
swift run xcproj-pkl validate /tmp/Tool.xcodeproj
swift run xcproj-pkl validate /tmp/Tool.xcodeproj/project.xcproj

# Pklのexternal property。複数回指定できます。
swift run xcproj-pkl generate MyProject.pkl --property flavor=debug
```

`--pkl`と`--property`はPkl入力にのみ指定できます。`PKL_EXEC`は引数を含まない実行ファイルのパスです。`xcproj.internal.`というproperty名は内部処理用に予約しています。

## Targetクラスと共有設定

`Pkl/Project.pkl`は`open module`であり、Target、Settingsなどの公開型を含みます。次の例はリポジトリ直下に置くファイルです。

`Settings.pkl`:

```pkl
import "Pkl/Project.pkl" as X

warnings: X.Settings = new {
  base { ["SWIFT_TREAT_WARNINGS_AS_ERRORS"] = "YES" }
}

compiler = (warnings) {
  base {
    ["SWIFT_VERSION"] = "6.0"
    ["OTHER_SWIFT_FLAGS"] = new Listing { "$(inherited)"; "-DTEAM" }
  }
  configs {
    ["Debug"] { base { ["ENABLE_TESTABILITY"] = "YES" } }
  }
}
```

`Targets.pkl`:

```pkl
import "Pkl/Project.pkl" as X
import "Settings.pkl" as Common

open class SwiftTarget extends X.Target {
  local target = this
  platform = "macOS"
  deploymentTarget = "14.0"
  settings = Common.compiler
  sources { new { path = "Sources/\(target.name)" } }
}

open class Framework extends SwiftTarget { type = "framework" }
open class UnitTests extends SwiftTarget { type = "bundle.unit-test" }
```

`Project.pkl`:

```pkl
amends "Pkl/Project.pkl"
import "Targets.pkl" as Shared

name = "Catalog"
idNamespace = "com.example.catalog"
targets {
  ["framework"] = new Shared.Framework {
    name = module.name
    sources = new Listing<Source> { new { path = "Sources" } }
  }
  ["tests"] = new Shared.UnitTests {
    name = "\(module.name)Tests"
    sources = new Listing<Source> { new { path = "Tests" } }
    dependencies { new { target = "framework" } }
  }
}
```

`extends`は型・共通モジュールの拡張、`amends`は既存モジュールの値の変更、`(base) { ... }`はオブジェクトの変更です。共通クラスは未完成のまま定義できますが、生成するTargetでは`name`、`type`、`platform`が必須です。

作者クラスに追加したプロパティは、生成用データへの明示的な投影で除外されます。テンプレート用パラメータには型付きプロパティや`hidden`、実装用の受け手には`local target = this`を使えます。

## Amendmentの規則

Pkl自身の規則を使います。

| 記述 | 動作 |
|---|---|
| `settings = Common.compiler` | 設定オブジェクトを置換 |
| `settings { base { ["KEY"] = "value" } }` | 継承した設定の一部を変更 |
| `sources { new { path = "Extra" } }` | 継承したListingへ追加 |
| `sources = new Listing<Source> { new { path = "Only" } }` | Listing全体を置換 |
| `settings { base { ["OTHER_SWIFT_FLAGS"] { "-DNEW" } } }` | 既存値がListingなら追加 |

`sources = new { ... }`という型を省略した記法も、継承した値のamendmentになります。全置換には上記のようにListing型を明示します。

Pklは単一継承です。独立した設定を合成する場合は、Settingsを受け取って変更後のSettingsを返す関数で明示します。spreadはdeep mergeではありません。

Settingsは`base`と`configs`を持ち、`configs`の値には`base`だけを定義できます。再帰的なconfigurationは作れません。Xcode向けの最終優先度は次のとおりです。

`組み込みbase < 組み込みconfiguration < user base < user configuration`

userの値はPklで継承を評価した後の設定です。`SWIFT_OPTIMIZATION_LEVEL = "-Osize"`をbaseで指定すれば、組み込みDebug/Release設定にも優先します。configuration固有の差分は`KEY[config=Debug]`へ変換します。`$(inherited)`などXcodeのマクロはそのまま保持します。

v1の`targetTemplates`、`templates`、`settingGroups`、`groups`、`templateAttributes`は廃止しました。`${...}`の独自展開もありません。v2スキーマは旧フィールドを拒否します。

## 多数のProjectを持つWorkspace

共通のProjectモジュールでFrameworkとTestsを定義し、各Projectが`amends`する例を`Examples/Workspace`に同梱しています。

```text
Examples/Workspace/
  Shared/FrameworkProject.pkl
  Modules/
    Catalog/Project.pkl
    DesignSystem/Project.pkl
    Networking/Project.pkl
  Workspace.pkl
```

各Project.pkl:

```pkl
amends "../../Shared/FrameworkProject.pkl"
name = "Catalog"
```

Workspace.pkl:

```pkl
amends "../../Pkl/Workspace.pkl"
name = "Modular"
projects = import*("Modules/*/Project.pkl")
```

```sh
swift run xcproj-pkl validate Examples/Workspace/Workspace.pkl
swift run xcproj-pkl generate Examples/Workspace/Workspace.pkl
swift run xcproj-pkl validate Examples/Workspace/Modular.xcworkspace

# 各Projectは単独でも同じ内容で生成できます。
swift run xcproj-pkl generate Examples/Workspace/Modules/Catalog/Project.pkl
```

Projectは自分の`projectDir/name.xcodeproj`、Workspaceは`workspaceDir/name.xcworkspace`へ生成します。Workspace入力に対する`-o`はWorkspaceだけを移動します。

Workspace内でimportしたProjectをamendしても、パスは元のProject.pklがあるディレクトリを基準にします。モジュール自体がsymlinkの場合もcanonicalなモジュールの親を使い、単独生成とWorkspace経由で統一します。Projectモジュールはローカルのfile URIに限定しています。共有テンプレート・設定にはPklのimportを使えます。

CLIに指定したentryはPkl評価前にもcanonical化します。WorkspaceからimportしたProject内のPkl相対import/readはPkl自身のURI解決に従うため、ファイルsymlinkをimportする場合はリンク側のURIからも解決できる配置が必要です。ソース・xcconfigのパス基準とは別の規則です。

同じcanonical Projectの二重登録、出力先の重複・入れ子はエラーです。Project間の依存解決はまだ対応していません。

## パス・ID・出力の契約

- ソースとxcconfigの相対パスは各Projectの`projectDir`基準です。
- sourceの`kind`は`folder`または`file`。folderの`excludes`は実在する正確な相対パスで、globは使えません。
- 同一Target内のsourceの入れ子は拒否します。同一実体を指すsourceはsymlinkを解決して統合し、excludesを集合化します。
- 複数Targetが同じsourceを持つ場合は、1つの参照とTargetごとのmembershipを生成します。
- TargetのMappingキーが安定した識別子です。依存の`target`にもこのキーを指定します。
- IDはnamespace・kind・keyをNULで区切ったUTF-8文字列のSHA-256の先頭24桁です。Targetの表示名を変えてもキーが同じならIDを保ちます。Project名を変える際は`idNamespace`を固定してください。
- 任意の`id` / `productId`も指定できます。IDの重複は大文字・小文字を区別せず検出します。
- 全Projectの検証後、generateは全出力先を事前確認してから書き込みます。legacy `project.pbxproj`のあるbundleを上書きしません。
- 更新するのは`project.xcproj`と`contents.xcworkspacedata`のみ。Schemeやユーザー設定を保持し、同一bytesなら書き換えません。
- 書き込みはファイル単位でatomicです。Workspace全体のrollbackは保証しません。Workspaceから外れたProjectも自動削除しません。

## 構成

```text
Pkl/Project.pkl、Workspace.pkl      作者向けmodule class
Pkl/Internal/ProjectModel.pkl     作者向け型の基底定義
Pkl/Internal/Snapshot.pkl         評価済み設定とパス要求の投影
Pkl/Internal/Builtins.pkl         標準設定、configuration、ID
Pkl/Internal/Validation.pkl       モデル・グラフ検証
Pkl/Internal/Xcode.pkl            完成Xcode JSONの構築
Pkl/Internal/WorkspaceXml.pkl     XML構築
Pkl/Internal/Render.pkl           完成ファイルを含む生成計画
Sources/XcprojPkl/HostFacts.swift  OSパス情報の取得
Sources/XcprojPkl/GenerationPlan.swift  実行、最終検証、出力制御
```

ユーザーモジュールを一度評価して固定Snapshotを作り、Swiftがsymlink・存在・種別の情報を補った後、内部Render.pklを評価します。Pklプロセスの起動はWorkspace全体で2回です。2回目にユーザーモジュールを再importしません。SwiftはTargetやSettingsの作者モデルをdecodeせず、完成したJSON/XMLも書き換えません。

内部PklはSwiftPMのresource bundleに含めています。実行ファイルを移動する場合は`xcproj-pkl_PklRuntimeResources.bundle`も同じディレクトリへ配置してください。

## 対応範囲と検証

対応するproduct typeは`application`、`framework`、`bundle`、`bundle.unit-test`、`tool`です。platformはiOS/macOS、toolはmacOSのみです。依存は同じProject内に限定し、linkはFramework、embedはapplicationからFrameworkのみを許可します。

モデル上の名前・型・configuration参照・依存先・循環・sourceの整合性をPklで検査します。さらにSwiftでAppleのXCSchemaと参照検証を行います。`validate`の成功はビルド成功を保証しません。

既存Workspaceの検証はGroup、`group:`、`container:`、`absolute:`参照に対応し、欠落・重複を検出します。XML entity、ネストWorkspace、旧pbxprojは対象外です。書き込み固有のlegacy検出や出力先file/directory競合はgenerate時に事前確認します。

```sh
swift test
PKL_EXEC="$(command -v pkl)" swift test
PKL_EXEC="$(command -v pkl)" bash Scripts/smoke-test.sh
PKL_EXEC="$(command -v pkl)" bash Scripts/workspace-smoke-test.sh
```

Pklを利用する統合テストは`PKL_EXEC`がない場合skipされます。統合テストではネイティブ継承、設定優先度、symlink、100 Projects / 200 Targets、Pkl起動回数、配布先へのresource移動を確認します。Swiftのみのテストは既存形式の検証とOS・出力制御を確認します。

共有Schemeはまだ生成しないため、WorkspaceサンプルのTestsはProjectのTargetを直接指定してビルドします。Apple CLIは検証環境では`xcrun xcodeproj`です。
