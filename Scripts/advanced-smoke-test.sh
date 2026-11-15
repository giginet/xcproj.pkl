#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/xcprojgen-advanced.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
cd "$repo_root"

swift build
cli="$(swift build --show-bin-path)/xcprojgen"
"$cli" validate Examples/Advanced --pkl "${PKL_EXEC:-pkl}"
"$cli" generate Examples/Advanced --pkl "${PKL_EXEC:-pkl}" --output-dir "$scratch/Generated"
project="$scratch/Generated/Advanced.xcodeproj"
test -f "$project/xcshareddata/xcschemes/AdvancedTool.xcscheme"

xcodebuild -quiet -project "$project" -scheme AdvancedTool -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$scratch/DerivedData" CODE_SIGNING_ALLOWED=NO build
result="$("$scratch/DerivedData/Build/Products/Debug/AdvancedTool")"
test "$result" = 'Hello from the local Swift package'

python3 - "$scratch/DerivedData" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
for name, expected in (
    ("advanced-pre.txt", "pre-build completed\n"),
    ("advanced-post.txt", "post-build completed\n"),
):
    markers = list(root.rglob(name))
    assert markers, f"Build script did not create {name}"
    assert all(marker.read_text() == expected for marker in markers), name
print("Local package linkage, shared scheme, and pre/post build scripts verified.")
PY
