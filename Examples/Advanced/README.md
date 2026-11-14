# Swift Package・ビルドスクリプト・共有 Scheme

`Main.pkl` はローカル Swift Package のライブラリをリンクする macOS コマンドラインツールを生成します。`../Shared/Templates.pkl` の `MacTool` を継承するため、Swift 6 の設定やソースディレクトリの指定も共通化しています。

```sh
swift run xcprojgen generate Examples/Advanced --output-dir /tmp/xcprojgen-advanced
xcodebuild -project /tmp/xcprojgen-advanced/Advanced.xcodeproj \
  -scheme AdvancedTool -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/xcprojgen-advanced/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
/tmp/xcprojgen-advanced/DerivedData/Build/Products/Debug/AdvancedTool
```

`PKL_EXEC` または CLI の `--pkl` で Pkl 実行ファイルを指定できます。出力先を移動しても、ローカル Package とソースへの参照は元のディレクトリを指します。

名前の使い分けを確認できるよう、以下は意図的に異なる値にしています。

| 用途 | 名前 |
| --- | --- |
| Pkl の依存指定用 alias | `support` |
| Package のディレクトリ | `LocalSupport` |
| `Package.name` | `AdvancedSupportPackage` |
| リンクする library product | `AdvancedSupport` |
| Swift で import する module | `SupportCore` |

`preBuildScripts` は通常のビルドフェーズより前にマーカーファイルを書き込みます。`postBuildScripts` はそのファイルと生成済み実行ファイルを確認してから、別のマーカーを書き込みます。入出力を宣言し、ビルドの依存関係に組み込んでいます。マーカーは `DERIVED_FILE_DIR` 内に生成されます。

`schemes` は `AdvancedTool` という共有 Scheme を生成します。Run・Profile・Analyze・Archive の設定を含み、`xcshareddata/xcschemes/AdvancedTool.xcscheme` として出力されます。

生成・バリデーション・ビルド・実行・スクリプトの結果をまとめて確認するには、リポジトリルートで次を実行してください。

```sh
PKL_EXEC=/path/to/pkl Scripts/advanced-smoke-test.sh
```

この例は外部の Swift Package をダウンロードしません。
