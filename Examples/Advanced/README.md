# Swift Package, Build Scripts, and a Shared Scheme

`Project.pkl` generates a macOS command-line tool that links a library from a local Swift package. It extends `MacTool` from `../Shared/Templates.pkl` to reuse the Swift 6 settings and source directory configuration.

```sh
swift run xcprojgen generate Examples/Advanced --output-dir /tmp/xcprojgen-advanced
xcodebuild -project /tmp/xcprojgen-advanced/Advanced.xcodeproj \
  -scheme AdvancedTool -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/xcprojgen-advanced/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
/tmp/xcprojgen-advanced/DerivedData/Build/Products/Debug/AdvancedTool
```

Use `PKL_EXEC` or the CLI's `--pkl` option to specify the Pkl executable. References to the local package and source files continue to point to their original directories when the output directory changes.

The following names are intentionally different to demonstrate their distinct roles:

| Role | Name |
| --- | --- |
| Alias used to declare the dependency in Pkl | `support` |
| Package directory | `LocalSupport` |
| `Package.name` | `AdvancedSupportPackage` |
| Library product to link | `AdvancedSupport` |
| Module to import in Swift | `SupportCore` |

`preBuildScripts` writes a marker file before the standard build phases. `postBuildScripts` checks that marker and the built executable before writing another marker. The scripts declare their inputs and outputs so they participate in the build dependency graph. Both markers are created in `DERIVED_FILE_DIR`.

`schemes` generates a shared scheme named `AdvancedTool`, including Run, Profile, Analyze, and Archive settings. It is written to `xcshareddata/xcschemes/AdvancedTool.xcscheme`.

To verify generation, validation, building, execution, and script results together, run the following from the repository root:

```sh
PKL_EXEC=/path/to/pkl Scripts/advanced-smoke-test.sh
```

This example does not download external Swift packages.
