#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/xcproj-pkl-smoke.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
cd "$repo_root"
swift build
cli="$(swift build --show-bin-path)/xcprojgen"
"$cli" validate Examples/Tool --pkl "${PKL_EXEC:-pkl}"
"$cli" generate Examples/Tool --pkl "${PKL_EXEC:-pkl}" --output-dir "$scratch"
"$cli" validate "$scratch/Tool.xcodeproj"
xcodebuild -quiet -project "$scratch/Tool.xcodeproj" -scheme Hello -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$scratch/DerivedData" CODE_SIGNING_ALLOWED=NO build
"$scratch/DerivedData/Build/Products/Debug/Hello"
