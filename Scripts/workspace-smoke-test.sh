#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/xcproj-pkl-workspace.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
cd "$repo_root"
swift build
cli="$(swift build --show-bin-path)/xcproj-pkl"
"$cli" validate Examples/Workspace/Workspace.pkl --pkl "${PKL_EXEC:-pkl}"
"$cli" generate Examples/Workspace/Workspace.pkl --pkl "${PKL_EXEC:-pkl}"
workspace="Examples/Workspace/Modular.xcworkspace"
"$cli" validate "$workspace"
xcodebuild -list -workspace "$workspace"
for module in Catalog DesignSystem Networking; do
  xcodebuild -quiet -workspace "$workspace" -scheme "$module" -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$scratch/DerivedData" CODE_SIGNING_ALLOWED=NO build
  # Xcode's automatic framework schemes do not include these hostless test bundles.
  xcodebuild -quiet -project "Examples/Workspace/Modules/$module/$module.xcodeproj" \
    -target "${module}Tests" -configuration Debug -sdk macosx \
    SYMROOT="$scratch/Products" OBJROOT="$scratch/Intermediates/$module" \
    CLANG_MODULE_CACHE_PATH="$scratch/ModuleCache" CODE_SIGNING_ALLOWED=NO build
done
