# xcproj.pkl

`xcprojgen`はPklからXcodeのJSON形式 `project.xcproj` と `xcworkspace` を生成・検証するSwift CLIです。Main.pklの型に応じて、単一のxcodeprojまたは複数Projectをまとめたxcworkspaceを生成できます。

v2では、Targetの再利用にPklのクラス継承、Projectの再利用にmodule classと`amends`、共有設定にimportとオブジェクトのamendmentを使います。設定解決、既定値、安定ID、Xcode JSON・Workspace XMLの構築はPklが担当します。

## 必要なもの

- macOS 14以降、Swift 6.1以降。
- Pkl 0.33以降。実行ファイルの探索順は `--pkl`、`PKL_EXEC`、`PATH`。
- JSON形式のプロジェクトを扱えるXcode。検証環境はXcode 27.3 beta 1。

Pklは外部プロセスとして起動します。既存のxcproj/workspaceを検証する場合はPklのインストールは不要です。

サンプルはすべて `Main.pkl` を入口とし、`Examples/PklProject` でcheckout内のパッケージに依存します。[Examplesの説明](Examples/README.md)に、Swift 6のFrameworkテンプレート・アプリ・Notification Service Extensionの構成を記載しています。

## 実行

```sh
swift build
swift run xcprojgen --help

# Pkl CLIの実行ファイルとバージョンを確認。
swift run xcprojgen doctor

# Main.pklを入口とするWorkspaceの雛形を生成（既定値）。
swift run xcprojgen init MyWorkspace --type workspace

# 単一xcodeproj用の雛形。
swift run xcprojgen init MyLibrary --type project

# 依存パッケージを解決し、完成するJSON/XMLを検証。
swift run xcprojgen validate MyWorkspace

# MyWorkspace/Workspace.xcworkspace と配下のxcodeprojを生成。
swift run xcprojgen generate MyWorkspace

# Workspaceの出力先を指定。相対パスはCLI実行時の作業ディレクトリ基準。
swift run xcprojgen validate MyWorkspace --output-dir /tmp/generated
swift run xcprojgen generate MyWorkspace --output-dir /tmp/generated
# => /tmp/generated/Workspace.xcworkspace

# 既存の生成物を読み取り専用で検証。Pklは不要。
swift run xcprojgen validate /tmp/generated/Workspace.xcworkspace

# Pklのexternal property。複数回指定できます。
swift run xcprojgen generate MyWorkspace --property flavor=debug
```

`init <dir>`は通信やPklの起動を行わず、既存ファイルを上書きしません。次の雛形を作成します。

```text
MyWorkspace/
  PklProject
  Main.pkl
  Templates.pkl
  Projects/Core/
    Project.pkl
    Sources/Core.swift
    Tests/CoreTests.swift
```

`PklProject`はこのリポジトリの将来のGitHub Release (`v0.1.0`) にある `xcproj@0.1.0` をdependencyとして指定します。現時点ではReleaseは未配布なので、そのままのURIによる依存取得は配布開始後に可能になります。開発中は後述のlocal dependency、または `Scripts/package-pkl.sh --skip-publish-check --install` によるローカルキャッシュを利用できます。

`Main.pkl`が共通のエントリーポイントです。`amends "@xcproj/Workspace.pkl"` ならWorkspace、`amends "@xcproj/Project.pkl"` ならProjectを生成します。`init --type`は作成する雛形の選択にだけ使い、生成時にはPklの型で対象を決めます。単一Projectの雛形では `Main.pkl`、`Sources/`、`Tests/` をルートに置きます。

別の入口を使う場合は、ディレクトリ基準の `--entry` を明示します。既定の `Main.pkl` が存在しない場合はエラーになり、`Project.pkl` や `Workspace.pkl` の自動探索はしません。

```sh
swift run xcprojgen generate MyWorkspace --entry Projects/Core/Project.pkl --output-dir /tmp/generated
swift run xcprojgen validate MyWorkspace --entry Projects/Core/Project.pkl
```

`validate` / `generate` は最寄りの `PklProject` に対して `pkl project resolve` を実行してから評価します。`validate`も依存lockfileの `PklProject.deps.json` を作成・更新することがありますが、生成するxcworkspace/xcodeprojは書き込みません。lockfileは利用側のリポジトリで管理してください。

`--output-dir`（短縮形 `-o`）は出力先ディレクトリです。バンドル名と拡張子は入口のPklが決めます。Workspace型で `name = "App"` なら `<output-dir>/App.xcworkspace`、Project型なら `<output-dir>/App.xcodeproj` を生成します。Swift側でバンドル名・拡張子を指定する処理や、出力指定の拡張子チェックはありません。`--entry`を指定した場合も、選択したPklの名前と型で決まります。

Workspace内の各Projectはそれぞれの `projectDir` に出力し、Workspaceからの参照を調整します。`--output-dir`省略時はWorkspaceの `workspaceDir/name.xcworkspace`、Projectの `projectDir/name.xcodeproj` です。相対的な出力先ディレクトリはCLIの作業ディレクトリ基準です。

`Project.pkl` / `Workspace.pkl` の直接指定と、既存 `.xcworkspace` / `.xcodeproj` / `project.xcproj` の検証にも対応しています。

```sh
swift run xcprojgen validate Examples/Workspace
swift run xcprojgen generate Examples/Tool --output-dir /tmp/generated
swift run xcprojgen validate /tmp/generated/Tool.xcodeproj
```

`--pkl /path/to/pkl`は `doctor` / `validate` / `generate` で使えます。探索順は `--pkl`、`PKL_EXEC`、`PATH` です。`PKL_EXEC`は引数を含まない実行ファイルのパスです。`doctor`は実行ファイルとバージョンを表示し、未導入・実行失敗・対応外バージョンの場合は非ゼロで終了します。未導入・対応外の場合は [Pkl公式Installationガイド](https://pkl-lang.org/main/current/pkl-cli/index.html#installation) を案内します。自動インストールは行いません。

`--pkl`・`--property`・`--entry`・`--output-dir`は既存の生成物の検証には指定できません。`xcproj.internal.`というproperty名は内部処理用に予約しています。

## Pkl Projectと配布パッケージ

配布用のPkl Projectは `Pkl/xcproj/` です。SwiftPMのbridgeはその外に置いています。

```text
Pkl/
  RuntimeResources.swift
  xcproj/
    PklProject
    Project.pkl
    Workspace.pkl
    Internal/
    tests/ApiTests.pkl
    README.md
Scripts/package-pkl.sh
```

```sh
# APIテストと既存公開バージョンのチェックを実行し、配布物を作成。
Scripts/package-pkl.sh

# ネットワークを使わないローカル作成。
Scripts/package-pkl.sh --skip-publish-check

# Pklの実行ファイルと出力先を指定。
Scripts/package-pkl.sh --pkl /path/to/pkl --skip-publish-check -o /tmp/pkl-dist
```

スクリプトは公式の `pkl project package` を使います。既定では `dist/pkl/xcproj@0.1.0/` にZip、パッケージメタデータ、両者のSHA-256 sidecarを生成します。APIテストもpackagerが実行し、テスト・manifest・SwiftソースをZipへ含めません。[公式CLI仕様](https://pkl-lang.org/main/current/pkl-cli/index.html#pkl-project-package)

バージョン、package URI、ZipのURLは `Pkl/xcproj/PklProject` に集約しています。現在のURLは将来のGitHub Releases配布を想定した値です。リポジトリはprivateで配布先は未設定のため、公開時には利用者が取得できるmetadata/ZipのURLへ設定してください。スクリプトはアップロードしません。

利用側は `PklProject` のdependenciesでパッケージを指定し、`pkl project resolve` 後に `amends "@xcproj/Project.pkl"` や `import "@xcproj/Project.pkl" as X` を使えます。checkoutを使う場合は `dependencies { ["xcproj"] = import("/path/to/xcproj.pkl/Pkl/xcproj/PklProject") }` というlocal dependencyも使えます。[依存とlocal dependencyの公式仕様](https://pkl-lang.org/main/current/language-reference/index.html#local-dependencies)

具体例と配布先の配置は [パッケージREADME](Pkl/xcproj/README.md) に記載しています。

## Targetクラスと共有設定

`Pkl/xcproj/Project.pkl`は`open module`であり、Target、Settingsなどの公開型を含みます。次の例はリポジトリ直下に置くファイルです。

`Settings.pkl`:

```pkl
import "Pkl/xcproj/Project.pkl" as X

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
import "Pkl/xcproj/Project.pkl" as X
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
amends "Pkl/xcproj/Project.pkl"
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

`extends`は型・共通モジュールの拡張、`amends`は既存モジュールの値の変更、`(base) { ... }`はオブジェクトの変更です。共通クラスは未完成のまま定義できますが、生成するnative Targetでは`name`と`type`（または`fullProductType`）が必須です。`platform`の既定値は`macOS`です。

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
  Main.pkl
```

各Project.pkl:

```pkl
amends "../../Shared/FrameworkProject.pkl"
name = "Catalog"
```

Main.pkl:

```pkl
amends "@xcproj/Workspace.pkl"
name = "Modular"
projects = import*("Modules/*/Project.pkl")
```

```sh
swift run xcprojgen validate Examples/Workspace
swift run xcprojgen generate Examples/Workspace
swift run xcprojgen validate Examples/Workspace/Modular.xcworkspace

# 各Projectは単独でも同じ内容で生成できます。
swift run xcprojgen generate Examples/Workspace/Modules/Catalog/Project.pkl
```

Projectは自分の`projectDir/name.xcodeproj`、Workspaceは`workspaceDir/name.xcworkspace`へ生成します。Workspace入力に対する`--output-dir`はWorkspaceの出力先ディレクトリを変更し、名前はWorkspaceの`name`から決まります。

Workspace内でimportしたProjectをamendしても、パスは元のProject.pklがあるディレクトリを基準にします。モジュール自体がsymlinkの場合もcanonicalなモジュールの親を使い、単独生成とWorkspace経由で統一します。Projectモジュールはローカルのfile URIに限定しています。共有テンプレート・設定にはPklのimportを使えます。

CLIに指定したentryはPkl評価前にもcanonical化します。WorkspaceからimportしたProject内のPkl相対import/readはPkl自身のURI解決に従うため、ファイルsymlinkをimportする場合はリンク側のURIからも解決できる配置が必要です。ソース・xcconfigのパス基準とは別の規則です。

同じcanonical Projectの二重登録、出力先の重複・入れ子はエラーです。Project間の依存には型付きの`RemoteTargetDependency`と`ImportedProduct`を使い、参照先のTarget/Product IDを明示します。

## パス・ID・出力の契約

- ソース・xcconfig・Targetの`infoPlist`の相対パスは各Projectの`projectDir`基準です。`infoPlist`は存在するファイルを指定し、生成先の移動時に`INFOPLIST_FILE`をリベースします。
- sourceの`kind`は`folder`または`file`。folderの`excludes`は実在する正確な相対パスで、globは使えません。
- 同一Target内のsourceの入れ子は拒否します。同一実体を指すsourceはsymlinkを解決して統合し、excludesを集合化します。
- 複数Targetが同じsourceを持つ場合は、1つの参照とTargetごとのmembershipを生成します。
- TargetのMappingキーが安定した識別子です。依存の`target`にもこのキーを指定します。
- IDはnamespace・kind・keyをNULで区切ったUTF-8文字列のSHA-256の先頭24桁です。Targetの表示名を変えてもキーが同じならIDを保ちます。Project名を変える際は`idNamespace`を固定してください。
- 任意の`id` / `productId`も指定できます。IDの重複は大文字・小文字を区別せず検出します。
- 全Projectの検証後、generateは全出力先を事前確認してから書き込みます。legacy `project.pbxproj`のあるbundleを上書きしません。
- 更新するのは`project.xcproj`、`contents.xcworkspacedata`、Pklで宣言した共有Schemeです。それ以外のSchemeやユーザー設定を保持し、同一bytesなら書き換えません。
- 書き込みはファイル単位でatomicです。Workspace全体のrollbackは保証しません。Workspaceから外れたProjectも自動削除しません。

## 構成

```text
Pkl/xcproj/Project.pkl、Workspace.pkl      作者向けmodule class
Pkl/xcproj/Internal/ProjectModel.pkl     作者向け型の基底定義
Pkl/xcproj/Internal/SchemaTypes.pkl      Appleスキーマに対応する型・Union
Pkl/xcproj/Internal/SchemaRender.pkl     型付き値からネイティブJSONへの投影
Pkl/xcproj/Internal/Snapshot.pkl         評価済み設定とパス要求の投影
Pkl/xcproj/Internal/Builtins.pkl         標準設定、configuration、ID
Pkl/xcproj/Internal/Validation.pkl       モデル・グラフ検証
Pkl/xcproj/Internal/Xcode.pkl            完成Xcode JSONの構築
Pkl/xcproj/Internal/WorkspaceXml.pkl     XML構築
Pkl/xcproj/Internal/Schemes.pkl          共有Schemeの参照解決・XML構築
Pkl/xcproj/Internal/Render.pkl           完成ファイルを含む生成計画
Sources/XcprojPkl/HostFacts.swift  OSパス情報の取得
Sources/XcprojPkl/GenerationPlan.swift  実行、最終検証、出力制御
Sources/XcprojPkl/PklTool.swift  Pklの評価・依存解決・バージョン確認
```

ユーザーモジュールを一度評価して固定Snapshotを作り、Swiftがsymlink・存在・種別の情報を補った後、内部Render.pklを評価します。生成計画の評価はWorkspace全体でPklプロセス2回です。CLIはその前に依存解決のためのPklプロセスを1回起動します（PklProjectがある場合）。2回目にユーザーモジュールを再importしません。SwiftはTargetやSettingsの作者モデルをdecodeせず、完成したJSON/XMLも書き換えません。

Swift側に残すのはCLI、Pklプロセスの起動、OS上のパス情報、Apple XCSchemaと既存成果物の参照検証、ファイル書き込みです。Targetの継承・設定の合成・ID計算・JSON/XML構築はPkl側にあります。既存成果物の検証はPklを使わないため、SwiftのProjectValidator / WorkspaceValidatorが担当します。

Swiftライブラリからは `PklTool` を共通の実行窓口として使います。生成計画は `GenerationPlan.compile(source:tool:properties:outputDirectory:)` で作成します。

内部PklはSwiftPMのresource bundleに含めています。実行ファイルを移動する場合は`xcproj-pkl_PklRuntimeResources.bundle`も同じディレクトリへ配置してください。

## 対応範囲と検証

Appleの `xcode-project-format` 0.1.0のProject・Target・Package・Build Phase・Build Rule・ファイル参照を型付きPklクラスで指定できます。[型とプロパティの対応表](Docs/SchemaCoverage.md)に上流との対応、パスの扱い、制約を記載しています。

`TargetKind`、`ProductType`、`Platform`、`BuildPhaseKind`などは名前付きstring unionです。`Platform`は `iOS` / `macOS` / `tvOS` / `watchOS` / `visionOS` / `driverKit` で、対応するSDKとdeployment target設定を生成します。既知のproduct typeにはアプリ・各Extension・Framework・ライブラリ・テストbundleなどを含みます。独自の型は `fullProductType` と `productName` / `productFileType` で指定できます。Appleが自由文字列としているfile typeやplatform filterはその拡張性を維持しています。

`kind = "aggregate"`、`kind = "external-build-system"` にも対応します。external targetには `buildToolPath` を指定します。同じProject内の `dependencies.target` はMappingのキーを参照し、Swift Packageの依存は `package` と `product` を指定します。別Projectの参照には `RemoteTargetDependency` と `ImportedProduct` を使います。App Extensionを埋め込む場合は `link = false; embed = true` を指定します。

`productName`は拡張子込みの製品ファイル名で、ファイル参照とSchemeに使います。変更する場合は、実際の出力名が一致するよう `PRODUCT_NAME` などのbuild settingも指定してください。既存のファイル参照を `product` に指定する場合も `productName` が必要です。ExtensionKit・System・Driver・Kernel Extensionの埋め込み先は通常のApp Extensionと異なるため、`CopyFilesBuildPhase`とmembershipで明示します。

### Swift Package・ビルドスクリプト・Scheme

```pkl
packages {
  ["collections"] = new RemoteSwiftPackage {
    repository = "https://github.com/apple/swift-collections.git"
    version { kind = "up-to-next-major-version"; value = "1.1.0" }
  }
  ["support"] = new LocalSwiftPackage { path = "Packages/Support" }
}
targets {
  ["app"] {
    name = "App"; type = "application"; platform = "iOS"
    dependencies { new { package = "collections"; product = "Collections" } }
    postBuildScripts {
      new {
        name = "Record Build"
        script = #"printf '%s\n' "$PRODUCT_NAME" > "$SCRIPT_OUTPUT_FILE_0""#
        outputPaths { "$(DERIVED_FILE_DIR)/build-name.txt" }
      }
    }
  }
}
schemes {
  ["App"] {
    build { targets { new { target = "app" } } }
    run = new { target = "app" }
    profile = new { target = "app" }
    analyze = new {}
    archive = new {}
  }
}
```

PackageのMappingキーは作者向けのaliasです。Xcodeのpackage参照名はrepository/pathの末尾から `.git` を除いた名前を大文字・小文字を保持して生成します。`Package.swift` の `Package.name` とは別です。ローカルpackageのパスは `projectDir` 基準で、`--output-dir` に追従します。remoteのversion指定は `revision` / `branch` / `version` / `version-range` / `up-to-next-minor-version` / `up-to-next-major-version` に対応し、rangeには `maximum` も指定します。`traits`、platform filter、build tool pluginにも対応します。

`preBuildScripts` と `postBuildScripts` は生成するBuild Phaseの前後に配置します。`buildPhases` を明示すると標準PhaseのListingを置き換え、指定順で出力します。scriptのinput/output paths、file lists、dependency file、常時実行なども設定できます。これらのパスにはXcodeのbuild settingマクロを記述できます。

Schemeは `xcshareddata/xcschemes/<name>.xcscheme` に生成します。Build / Run / Test / Profile / Analyze / Archive、実行引数・環境変数、各actionのpre/post scriptに対応します。Project内のターゲット参照にはキー、Workspace内では `project-key/target-key` を使います。例えば `test = new { targets { new { target = "tests" } }; codeCoverage = true }` と指定できます。Schemeの名前・ターゲット・configurationを検証し、生成対象外のSchemeは保持します。

[Advancedの例](Examples/Advanced/README.md)では、ローカルPackageのリンク、ビルドスクリプト、共有Schemeを実際にビルドして確認できます。

モデル上の名前・型・configuration参照・依存先・循環・sourceの整合性をPklで検査します。さらにSwiftでAppleのXCSchemaと参照検証を行います。`validate`の成功はビルド成功を保証しません。

既存Workspaceの検証はGroup、`group:`、`container:`、`absolute:`参照に対応し、欠落・重複を検出します。XML entity、ネストWorkspace、旧pbxprojは対象外です。書き込み固有のlegacy検出や出力先file/directory競合はgenerate時に事前確認します。

```sh
swift test
PKL_EXEC="$(command -v pkl)" swift test
PKL_EXEC="$(command -v pkl)" bash Scripts/smoke-test.sh
PKL_EXEC="$(command -v pkl)" bash Scripts/workspace-smoke-test.sh
PKL_EXEC="$(command -v pkl)" bash Scripts/ios-smoke-test.sh
PKL_EXEC="$(command -v pkl)" bash Scripts/advanced-smoke-test.sh
```

Pklを利用する統合テストは`PKL_EXEC`がない場合skipされます。統合テストではネイティブ継承、設定優先度、symlink、100 Projects / 200 Targets、Pkl起動回数、配布先へのresource移動を確認します。Swiftのみのテストは既存形式の検証とOS・出力制御を確認します。

WorkspaceサンプルのTestsはProjectのTargetを直接指定してビルドします。Advancedサンプルでは生成した共有Schemeを使ってビルドします。Apple CLIは検証環境では`xcrun xcodeproj`です。

## Swiftの整形

`xcrun swift-format`を使います。`.swift-format` は `xcrun swift-format dump-configuration` の全設定を出力したもので、`indentation.spaces` と `tabWidth` を4に指定しています。`init` が作成するSwiftソースも4スペースです。

```sh
git ls-files -z -- '*.swift' | xargs -0 xcrun swift-format format --in-place --configuration .swift-format
git ls-files -z -- '*.swift' | xargs -0 xcrun swift-format lint --strict --configuration .swift-format
```

`.codex/hooks.json` の `PostToolUse` hookは、編集・パッチ・シェルコマンドの完了後に変更されたSwiftファイルを整形します。対象はstaged・unstaged・未追跡のSwiftファイルで、Gitのignore対象とsymlinkは含めません。ファイルを自動でstageすることはありません。

初回利用時はCodexの `/hooks`（デスクトップアプリではSettings > Hooks）で、このリポジトリのhookを確認して信頼してください。新規・変更されたhookは信頼されるまで実行されません。[公式Hooks仕様](https://learn.chatgpt.com/docs/hooks)
