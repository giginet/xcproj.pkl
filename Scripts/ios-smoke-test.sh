#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/xcprojgen-ios.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
cd "$repo_root"
swift build
cli="$(swift build --show-bin-path)/xcprojgen"
"$cli" validate Examples/iOS --pkl "${PKL_EXEC:-pkl}"
"$cli" generate Examples/iOS --pkl "${PKL_EXEC:-pkl}" --output-dir "$scratch/Generated"
project="$scratch/Generated/Demo.xcodeproj"
"$cli" validate "$project"
xcodebuild -quiet -project "$project" -scheme DemoApp -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$scratch/DerivedData" CODE_SIGNING_ALLOWED=NO build
app="$scratch/DerivedData/Build/Products/Debug-iphonesimulator/DemoApp.app"
for framework in DemoCore DemoNetworking DemoNotifications; do
  test -d "$app/Frameworks/$framework.framework"
done
extension="$app/PlugIns/DemoNotificationService.appex"
test -d "$extension"
extension_point="$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$extension/Info.plist")"
test "$extension_point" = 'com.apple.usernotifications.service'
xcodebuild -quiet -project "$project" -target DemoCoreTests -configuration Debug \
  -sdk iphonesimulator SYMROOT="$scratch/Products" OBJROOT="$scratch/Intermediates" \
  CLANG_MODULE_CACHE_PATH="$scratch/ModuleCache" CODE_SIGNING_ALLOWED=NO build
