# xcproj-pkl

PklからXcodeのJSON形式 `project.xcproj` と、複数プロジェクトをまとめる `.xcworkspace` を生成・検証するSwift製CLIのプロトタイプです。

XcodeGenの `targetTemplates` / `settingGroups` を参考にしたPklスキーマを提供します。
Pklの `import`、オブジェクト継承、型チェックと、Swiftによる名前付きテンプレートの展開・参照検証を組み合わせています。
YAML入力やXcodeGenとの完全互換は対象外です。

## 必要なもの

- macOS 14以降、Swift 6.1以降
- Pkl 0.33以降：`brew install pkl`
- 生成したプロジェクトのビルドにはXcode 27.2以降を想定しています。検証環境はXcode 27.3 beta 1です。

SwiftPMでApple公式の `xcode-project-format` 0.1.0と `swift-argument-parser` を取得します。
Pklは別の実行ファイルとして起動します。探索順は `--pkl`、`PKL_EXEC`、`PATH` です。
`PKL_EXEC` は引数付きコマンドではなく、実行ファイルのパスを指定してください。

## 実行

```sh
swift build

# Pklを評価し、テンプレート・設定を解決して検証。ファイルは出力しません。
swift run xcproj-pkl validate Examples/Tool/Project.pkl

# デフォルトでは projectDir/name.xcodeproj に生成します。
swift run xcproj-pkl generate Examples/Tool/Project.pkl

# 出力先を変えると、ソースとxcconfigの参照パスも調整します。
swift run xcproj-pkl generate Examples/Tool/Project.pkl -o /tmp/Tool.xcodeproj

# 既存のJSON形式のプロジェクトを読み取り専用で検証します。
swift run xcproj-pkl validate /tmp/Tool.xcodeproj
swift run xcproj-pkl validate /tmp/Tool.xcodeproj/project.xcproj
```

PklがPATH上にない場合は `--pkl /path/to/pkl` を指定できます。
Pklの `read("prop:key")` へ値を渡すには、`-p key=value` を使います。
Pkl Packageをimportする場合は、通常どおり `PklProject` を用意し、事前に `pkl project resolve` を実行してください。

生成は検証成功後に行い、`project.xcproj` だけをアトミックに書き換えます。
出力が同じなら書き込みません。既存のSchemeなどは保持します。
`project.pbxproj` が存在する出力先への生成はエラーにし、自動変換・削除は行いません。

## 多数のプロジェクトを持つWorkspace

**1つのProject.pklを1つのxcodeprojとして扱い、Workspace.pklからまとめて生成します。**
実例は [Examples/Workspace](Examples/Workspace/Workspace.pkl) です。
3つのプロジェクトがそれぞれFrameworkとTestsを持ち、共通のターゲットテンプレートと設定を継承します。

```text
Examples/Workspace/
├── Workspace.pkl
├── Shared/FrameworkProject.pkl      共通設定とFramework / Testsテンプレート
└── Modules/
    ├── Catalog/Project.pkl          → Catalog.xcodeproj（2ターゲット）
    ├── DesignSystem/Project.pkl     → DesignSystem.xcodeproj（2ターゲット）
    └── Networking/Project.pkl       → Networking.xcodeproj（2ターゲット）
```

Workspace.pklではProjectモジュールをimportします。多数のプロジェクトは `import*` で列挙できます。

```pkl
amends "../../Pkl/Workspace.pkl"

name = "Modular"
projects = import*("Modules/*/Project.pkl")
```

再帰的な探索には `Modules/**/Project.pkl` を使えます。明示的に選ぶ場合も同じ型を使います。

```pkl
projects {
  ["catalog"] = import("Modules/Catalog/Project.pkl")
  ["networking"] = import("Modules/Networking/Project.pkl")
}
```

各Project.pklは共通のProjectテンプレートをamendします。
[FrameworkProject.pkl](Examples/Workspace/Shared/FrameworkProject.pkl) が `Project.pkl` スキーマをextendsし、
`Swift` → `Framework` / `Tests` のターゲットテンプレート継承と、2つのターゲットを定義しています。

```pkl
// Modules/Catalog/Project.pkl
amends "../../Shared/FrameworkProject.pkl"

name = "Catalog"
// 共通定義からCatalog / CatalogTestsが生成されます。
// 必要なら targets { ["framework"] { settings { ... } } } で個別に上書きできます。
```

この例ではTestsから同じプロジェクトのFrameworkへの依存もテンプレートに含めています。
各モジュールの `Sources/` と `Tests/` は、そのモジュール自身のProject.pkl基準で解決されます。

```sh
# 全Projectの継承・ソース・依存を検証。まだ出力しません。
swift run xcproj-pkl validate Examples/Workspace/Workspace.pkl

# 3つのxcodeprojと、それらを参照するModular.xcworkspaceを生成
swift run xcproj-pkl generate Examples/Workspace/Workspace.pkl
swift run xcproj-pkl validate Examples/Workspace/Modular.xcworkspace

# Workspace経由でFrameworkをビルド
xcodebuild -workspace Examples/Workspace/Modular.xcworkspace \
  -scheme Catalog -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

# 共有Schemeをまだ生成しないため、TestsはProjectのターゲットを直接指定
xcodebuild -project Examples/Workspace/Modules/Catalog/Catalog.xcodeproj \
  -target CatalogTests -sdk macosx CODE_SIGNING_ALLOWED=NO build

# 1つのProject.pklだけを生成することもできます。
swift run xcproj-pkl generate Examples/Workspace/Modules/Catalog/Project.pkl
```

### Workspaceの生成規則

- PklはWorkspace単位で1回評価します。共通のimportと型チェックもその評価内で処理します。
- 各ProjectモジュールのURIを `pkl:reflect.moduleOf` で取得し、その場所を `projectDir` の基準にします。
  Workspace側でインポートしたProjectをamendしても、元のモジュールの場所を保持します。
- Workspaceは `workspaceDir/name.xcworkspace` に生成します。`workspaceDir` はWorkspace.pkl基準で、既定値は `"."` です。
- 各Projectは従来どおり、自分自身の `projectDir/name.xcodeproj` に生成します。
- `generate Workspace.pkl -o /tmp/Modular.xcworkspace` はWorkspaceの出力先だけを変更します。
  Projectの出力先はそのままで、Workspaceの参照パスを相対パスに調整します。
- Projectの登録キーで並べ替えて出力し、globの列挙順による差分を避けます。
- 重複する登録キー、同じProjectモジュールの二重登録、出力先の重複・入れ子を拒否します。
- 全Projectの生成・検証と、全出力先の既存ファイルとの衝突確認を終えてから書き出します。
  書き込みはファイル単位でアトミックです。ディスク障害などに対するWorkspace全体のロールバックはありません。
- Workspaceの `contents.xcworkspacedata` と各Projectの `project.xcproj` だけを更新します。
  Scheme・ユーザー設定は保持し、一覧から外れたProjectの生成物は自動削除しません。

Projectモジュール自身はローカルの `.pkl` ファイルが対象です。共通設定・テンプレートのPkl Package importは利用できます。
Workspace内のProjectは一度のPkl評価を共有するため、`--property` と評価設定も共通です。
この機能はProjectの集約と各Project内の依存に対応しています。**Projectをまたぐターゲット依存・リンクは未対応**です。
共有Scheme、複数Projectを横断するTest Action、Workspace上の表示グループも生成しません。
検証環境ではFrameworkの自動SchemeにTestsが含まれないため、スモークテストもTestsのビルドはターゲットを直接指定しています。

## 入力例

実行可能な例は [Examples/Tool](Examples/Tool/Project.pkl) と [Examples/iOS](Examples/iOS/Project.pkl) にあります。
以下はiOS App・Framework・Testsの例の抜粋です。全体はファイルを参照してください。

```pkl
amends "../../Pkl/Project.pkl"
import "../Shared/Settings.pkl" as SharedSettings
import "../Shared/Templates.pkl" as SharedTemplates

name = "Demo"
idNamespace = "com.example.demo"

settingGroups {
  ["warnings"] = SharedSettings.warnings
  ["compiler"] = SharedSettings.compiler
}

targetTemplates {
  ["Swift"] = SharedTemplates.swiftTarget
  ["iOS"] = SharedTemplates.iOS
  ["Framework"] {
    templates { "iOS" }
    type = "framework"
  }
}

targets {
  ["core"] {
    name = "DemoCore"
    templates { "Framework" }
    templateAttributes { ["bundleSuffix"] = "core" }
  }
}
```

### 設定のimport

共通設定は通常のPklモジュールです。例えば [Examples/Shared/Settings.pkl](Examples/Shared/Settings.pkl) は、型付きの設定を公開します。

```pkl
import "../../Pkl/Project.pkl"

warnings: Project.Settings = new {
  base {
    ["SWIFT_TREAT_WARNINGS_AS_ERRORS"] = "YES"
  }
}
```

利用側で `import` して `settingGroups` に登録し、`settings.groups` から参照します。
インポートしたオブジェクトを `(SharedSettings.warnings) { ... }` でamendしてから登録することもできます。
`settings = SharedSettings.warnings` と直接代入する方法も使えます。

```pkl
settings {
  groups { "compiler" }
  base {
    ["SWIFT_VERSION"] = "6.0"
    ["OTHER_SWIFT_FLAGS"] = new Listing {
      "$(inherited)"
      "-DLOCAL"
    }
  }
  configs {
    ["Debug"] {
      groups { "debugSettings" }
      base { ["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone" }
    }
  }
}
```

この抜粋の `debugSettings` は、利用側の `settingGroups` に定義する必要があります。
設定値は文字列または文字列配列です。例えば `YES` は `"YES"`、Swiftバージョンは `"6.0"` と記述します。
`.xcconfig` のimportに相当する参照も、project/target両方の `configFiles` で指定できます。

```pkl
configFiles {
  ["Debug"] = "Config/Debug.xcconfig"
}
```

xcconfigの内容は変更しません。存在と参照を確認し、Xcodeのconfigurationへ紐付けます。

## 継承とマージ規則

| 対象 | 規則 |
| --- | --- |
| `target.templates` | 左から右に適用し、最後にターゲット自身を適用 |
| テンプレートの `templates` | 親を再帰的に適用してから、そのテンプレートを適用 |
| `type`、`platform`、`name`など | 後に指定した非null値で上書き |
| `sources`、`dependencies` | 追加。重複するソースは除外リストを統合。同一依存先の矛盾したオプションはエラー |
| `settings.groups` | 名前リストを追加し、記述順に適用 |
| `settings.base` | キー単位で後の値が優先 |
| `settings.configs` | configuration名ごとにSettingsを再帰マージ |
| 設定の解決 | groups → base → 該当configurationのgroups → 該当configurationのbase |
| 設定値の配列 | キー単位で全置換。自動連結しない |
| `templateAttributes`、`configFiles` | キー単位で後の値が優先 |

Pklのオブジェクトamendmentと、Swiftで解決する名前付きテンプレートは別の段階です。
例えばPklで `sources = new Listing { ... }` と書けば、そのPklオブジェクトのリストは置換されますが、
`templates` に名前で指定した親テンプレートのsourcesは、その後のSwift側の処理で追加されます。
このプロトタイプにはXcodeGenの `:REPLACE` 相当の指定や、継承した項目の削除指定はありません。

configuration名は完全一致・大文字小文字を区別します。XcodeGenの部分一致は行いません。
`configs` 内のSettingsからgroupを参照できますが、さらに `configs` をネストすることはできません。
`[sdk=...]` などの条件付き設定キーはそのまま保持します。configuration条件には `settings.configs` を使ってください。

`$(inherited)` は文字列としてXcodeへ渡します。これはXcodeのproject/target/xcconfig間の継承であり、
同一ターゲットに適用するsetting groupの前の値を復元する指定ではありません。

### テンプレート属性

`${target_name}` は最終的なターゲット表示名に置換します。
`${attribute}` は合成後の `templateAttributes` から取得します。
置換対象はソースパス、除外パス、依存先キー、xcconfigパス、Build Settingsの値です。
置換は一度だけで、属性値の再帰展開や環境変数の暗黙展開は行いません。
不明な属性はエラーです。`target_name` は予約名です。

### パスとID

- 全ソース・xcconfigパスは `projectDir` 基準です。importしたテンプレートの置き場所には依存しません。
- `projectDir` はエントリーPklファイル基準で、既定値は `"."` です。
- `targets` のキーは安定した識別子、`name` は表示名です。依存先にはキーを指定します。
- IDは `idNamespace`・種類・ターゲットキーをSHA-256でハッシュし、24桁の16進数にします。
- 表示名だけを変更してもIDは変わりません。プロジェクトの改名時にもIDを維持するには `idNamespace` を固定してください。
- 移行用に `id` と `productId` を明示できます。重複は拒否します。

## 対応範囲

- iOS / macOS
- application / framework / bundle / bundle.unit-test / tool（toolはmacOSのみ）
- Debug / Release、および任意名のconfiguration
- 同期フォルダ、明示的な単一ファイル、同期フォルダのファイル除外（相対パスの完全一致）
- ローカルターゲット依存、Frameworkのリンク、AppへのFramework埋め込み
- project/targetのBuild Settingsとxcconfig参照

`Source.kind` は `folder`（既定）または `file` です。
明示的なファイルは拡張子からSources / Headers / Resourcesのフェーズを選びます。
`folder` の内容の分類はXcodeの同期フォルダ機能に任せます。
同一ターゲットで重なるソースルートは拒否します。存在しない生成予定ソースやglobは未対応です。

`Dependency` は `target`、`link`（既定true）、`embed`（既定false）を持ちます。
`unit-test-bundle` も `bundle.unit-test` の別名として受け付けます。
ビルド順だけの依存には `link = false` を指定します。リンク対象はFrameworkのみ、埋め込み先はAppのみです。
ホストアプリ付きテスト、UI Tests、SwiftPM依存、任意のBuild Script、Schemeの生成は未対応です。
Xcodeの自動Schemeでビルドできますが、共有SchemeやTest Actionは生成していません。
このプロトタイプの検証ではmacOSツールの実行とiOS App・Framework・Testsのビルドまで確認しています。
Simulator上でのテスト実行は、検証環境のCoreSimulatorとXcodeのバージョン不一致により未確認です。

## バリデーション

Pkl入力は、Pklの型チェックに加えて以下を検証します。

- 入力フィールド、schemaVersion、対象のtype/platform
- テンプレート・設定グループの存在と循環（未使用の定義も検証）
- configuration名、ターゲット名、IDの一意性
- ローカル依存先の存在、依存の循環、platform/link/embedの整合性
- ソース・除外ファイル・xcconfigの存在
- 不明なテンプレート属性、重複する依存オプション、重なるソースルート

生成時と既存xcprojの検証には、Appleの `XCSchema` によるデコードと、独自のローカル参照検証を使います。
独自検証ではターゲット所属、Build Phase参照、生成物参照、xcconfigアンカー、ローカル依存の存在・循環、
configuration、ID重複を確認します。

既存xcprojの検証では、ディスク上のソースの存在、xcconfigの内容、Build Settingsの意味、
外部プロジェクト・SwiftPM依存の解決、SDKや署名の可否までは検証しません。
Appleのデコーダーが無視する未知キーも、この検証では検出できません。
`validate` の成功はビルド成功を保証しません。必要に応じて `xcodebuild` を併用してください。

WorkspaceのPkl入力では、含まれる全Projectに同じ検証を適用します。
既存 `.xcworkspace` の検証ではXMLを読み、全参照先の `project.xcproj` を検証します。
`Group` と `group:` / `container:` / `absolute:` のパスに対応し、参照の重複・欠落を拒否します。
旧形式の `project.pbxproj`、Project以外のファイル参照、ネストしたWorkspaceは検証対象外で、エラーにします。

## 構成とテスト

```text
Pkl/Project.pkl             型付きの入力スキーマ
Pkl/Workspace.pkl           複数Projectの集約とモジュールURIの付与
Examples/Shared/            import可能な設定・テンプレート
Examples/Workspace/         Framework + Testsを持つ複数Projectのサンプル
Sources/XcprojPkl/          Pkl起動、継承解決、検証、xcproj変換
Sources/XcprojPklCLI/       generate / validateコマンド
Tests/XcprojPklTests/       Swift Testingによる回帰テスト
```

```sh
swift test

# 実際にPklを起動する統合テストも有効にする
PKL_EXEC="$(command -v pkl)" swift test

# 別ディレクトリへ生成し、macOSターゲットをビルド・実行する
bash Scripts/smoke-test.sh

# Workspace生成と、3つのFramework / Testsのビルド
bash Scripts/workspace-smoke-test.sh

# iOSサンプル：Frameworkリンク・埋め込みを確認
swift run xcproj-pkl generate Examples/iOS/Project.pkl
xcodebuild -project Examples/iOS/Demo.xcodeproj -scheme DemoApp \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Pkl統合テストは `PKL_EXEC` が未指定の場合はスキップされます。
Workspaceの統合テストは一時ディレクトリに100個のProject.pklを用意し、`import*` でまとめて評価して、
100プロジェクト・200ターゲットの生成・検証・再生成を確認します。
生成する設定の継承規則は [Resolver.swift](Sources/XcprojPkl/Resolver.swift)、
保存形式への変換は [Generator.swift](Sources/XcprojPkl/Generator.swift) に集約しています。
Workspaceの集約は [WorkspaceGenerator.swift](Sources/XcprojPkl/WorkspaceGenerator.swift)、
入力種別による振り分けは [GenerationPlan.swift](Sources/XcprojPkl/GenerationPlan.swift) が担当します。

仕様の参照元：
[XcodeGen ProjectSpec](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)、
[Pkl Language Reference](https://pkl-lang.org/main/current/language-reference/index.html)、
[Pkl reflection API](https://github.com/apple/pkl/blob/0.33.0/stdlib/reflect.pkl)、
[Apple xcode-project-format](https://github.com/apple/xcode-project-format)。
