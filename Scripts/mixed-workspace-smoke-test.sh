#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/xcprojgen-mixed-workspace.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
cd "$repo_root"

swift build
cli="$(swift build --show-bin-path)/xcprojgen"

# Preserve the local Pkl dependency layout and keep Xcode's generated metadata
# away from the checked-in legacy project.
source_root="$scratch/Source"
examples="$source_root/Examples"
legacy="$examples/MixedWorkspace/Legacy.xcodeproj"
mkdir -p "$examples/Tool" "$legacy/xcshareddata/xcschemes"
cp -R Pkl "$source_root/"
cp Examples/PklProject "$examples/"
cp -R Examples/Shared "$examples/"
cp Examples/Tool/Project.pkl "$examples/Tool/"
cp -R Examples/Tool/Sources "$examples/Tool/"
cp Examples/MixedWorkspace/Project.pkl "$examples/MixedWorkspace/"
cp Examples/MixedWorkspace/Legacy.xcodeproj/project.pbxproj "$legacy/"
cp Examples/MixedWorkspace/Legacy.xcodeproj/xcshareddata/xcschemes/Legacy.xcscheme \
  "$legacy/xcshareddata/xcschemes/"

legacy_checksums="$(shasum -a 256 "$legacy/project.pbxproj" "$legacy/xcshareddata/xcschemes/Legacy.xcscheme")"
assert_legacy_unchanged() {
  test "$(shasum -a 256 "$legacy/project.pbxproj" "$legacy/xcshareddata/xcschemes/Legacy.xcscheme")" = "$legacy_checksums"
}

"$cli" validate "$examples/MixedWorkspace" --pkl "${PKL_EXEC:-pkl}"
"$cli" generate "$examples/MixedWorkspace" --pkl "${PKL_EXEC:-pkl}" --output-dir "$scratch/Generated"
workspace="$scratch/Generated/Mixed.xcworkspace"
assert_legacy_unchanged

xcodebuild -list -workspace "$workspace"
for scheme in Hello Legacy; do
  xcodebuild -quiet -workspace "$workspace" -scheme "$scheme" -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$scratch/DerivedData" CODE_SIGNING_ALLOWED=NO build
done
result="$("$scratch/DerivedData/Build/Products/Debug/Hello")"
test "$result" = 'Hello from a Pkl-generated Xcode project!'
assert_legacy_unchanged
echo 'Generated and existing projects built successfully; imported project and scheme are unchanged.'
