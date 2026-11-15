#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-}"
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  printf 'Usage: Scripts/prepare-cli-release.sh X.Y.Z [--output-path DIRECTORY]\n' >&2
  exit 2
fi
shift
output_path="$repo_root/dist/cli-release/$version"
if (($#)); then
  if [[ $# != 2 || "$1" != --output-path || -z "$2" ]]; then
    printf 'Expected --output-path DIRECTORY\n' >&2
    exit 2
  fi
  output_path="$2"
fi
if [[ "$output_path" != /* ]]; then output_path="$PWD/$output_path"; fi
if [[ -e "$output_path" || -L "$output_path" ]]; then
  printf 'Refusing to reuse an existing release output path: %s\n' "$output_path" >&2
  exit 2
fi

temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/xcproj-cli-release.XXXXXX")"
trap 'rm -rf "$temporary_dir"' EXIT
cd "$repo_root"
build_options=(--configuration release --product xcprojgen --arch arm64 --arch x86_64)
swift build "${build_options[@]}"
binary_dir="$(swift build "${build_options[@]}" --show-bin-path)"
stage="$temporary_dir/stage"
mkdir "$stage"
cp "$binary_dir/xcprojgen" "$stage/"
cp -R "$binary_dir/xcprojgen_PklRuntimeResources.bundle" "$stage/"
cp "$repo_root/LICENSE" "$stage/"
mkdir "$stage/Licenses"
cp "$repo_root/.build/checkouts/swift-argument-parser/LICENSE.txt" "$stage/Licenses/swift-argument-parser.txt"
cp "$repo_root/.build/checkouts/xcode-project-format/LICENSE.txt" "$stage/Licenses/xcode-project-format.txt"

# Stamp only the staged resource bundle. Source and SwiftPM build outputs stay unchanged.
printf '%s\n' "$version" > "$stage/xcprojgen_PklRuntimeResources.bundle/Contents/Resources/Internal/Version.txt"
architectures="$(xcrun lipo -archs "$stage/xcprojgen")"
for architecture in arm64 x86_64; do
  if [[ " $architectures " != *" $architecture "* ]]; then
    printf 'Release binary is missing architecture: %s\n' "$architecture" >&2
    exit 1
  fi
done
codesign --force --sign - "$stage/xcprojgen"
codesign --verify --strict "$stage/xcprojgen"

# Exercise the relocated executable and its embedded renderer before packaging.
cd "$temporary_dir"
test "$("$stage/xcprojgen" --version)" = "$version"
"$stage/xcprojgen" init "$temporary_dir/Example" --type project
grep -Fq "/$version/xcproj@$version" "$temporary_dir/Example/PklProject"
"$stage/xcprojgen" validate "$repo_root/Examples/Tool"
"$stage/xcprojgen" skills export "$temporary_dir/skills"
test -f "$temporary_dir/skills/xcprojgen/SKILL.md"

mkdir "$temporary_dir/assets"
archive="xcprojgen-$version-macos-universal.tar.gz"
COPYFILE_DISABLE=1 tar -czf "$temporary_dir/assets/$archive" -C "$stage" \
  xcprojgen xcprojgen_PklRuntimeResources.bundle LICENSE Licenses
cd "$temporary_dir/assets"
shasum -a 256 "$archive" > "$archive.sha256"
mkdir -p "$(dirname "$output_path")"
mv "$temporary_dir/assets" "$output_path"
printf 'Prepared CLI release assets: %s\n' "$output_path"
