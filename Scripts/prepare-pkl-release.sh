#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pkl_exec="${PKL_EXEC:-pkl}"
output_path=""
tag=""

usage() {
  cat <<'USAGE'
Usage: Scripts/prepare-pkl-release.sh pkl/X.Y.Z [--pkl PATH] [-o DIRECTORY]

Build and stage package.zip, package.zip.sha256, xcproj@X.Y.Z, and
xcproj@X.Y.Z.sha256 for an existing GitHub Release. Runs package API tests.

The tag must have exactly three numeric version components without leading
zeroes. The version is passed to Pkl without modifying the checkout.

  --pkl PATH                Pkl executable (default: PKL_EXEC or PATH)
  -o, --output-path DIR     New output directory (must not already exist)
  -h, --help                Show this help

Default output: dist/pkl-release/X.Y.Z/
This script neither creates releases nor uploads assets.
USAGE
}

while (($#)); do
  case "$1" in
    --pkl|-o|--output-path)
      if (($# < 2)) || [[ -z "$2" ]]; then
        printf 'Missing value for %s\n' "$1" >&2
        exit 2
      fi
      case "$1" in
        --pkl) pkl_exec="$2" ;;
        *) output_path="$2" ;;
      esac
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -n "$tag" ]]; then
        printf 'Unexpected argument: %s\n' "$1" >&2
        exit 2
      fi
      tag="$1"
      shift
      ;;
  esac
done

if [[ ! "$tag" =~ ^pkl/(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  printf 'Invalid release tag: %s (expected pkl/X.Y.Z without leading zeroes)\n' "$tag" >&2
  exit 2
fi
version="${tag#pkl/}"
output_path="${output_path:-$repo_root/dist/pkl-release/$version}"
if [[ "$output_path" != /* ]]; then
  output_path="$PWD/$output_path"
fi
if [[ -e "$output_path" || -L "$output_path" ]]; then
  printf 'Refusing to reuse an existing release output path: %s\n' "$output_path" >&2
  exit 2
fi

temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/xcproj-pkl-release.XXXXXX")"
trap 'rm -rf "$temporary_dir"' EXIT

# Build offline before the workflow uploads assets. Existing remote assets are
# never overwritten; remove any partial upload before retrying the workflow.
bash "$repo_root/Scripts/package-pkl.sh" \
  --pkl "$pkl_exec" --version "$version" --skip-publish-check \
  --output-path "$temporary_dir/package"

mkdir "$temporary_dir/assets"
mv "$temporary_dir/package/xcproj@$version.zip" "$temporary_dir/assets/package.zip"
mv "$temporary_dir/package/xcproj@$version.zip.sha256" "$temporary_dir/assets/package.zip.sha256"
mv "$temporary_dir/package/xcproj@$version" "$temporary_dir/assets/xcproj@$version"
mv "$temporary_dir/package/xcproj@$version.sha256" "$temporary_dir/assets/xcproj@$version.sha256"

if [[ -e "$output_path" || -L "$output_path" ]]; then
  printf 'Release output path was created while packaging: %s\n' "$output_path" >&2
  exit 2
fi
mkdir -p "$(dirname "$output_path")"
mv "$temporary_dir/assets" "$output_path"
printf 'Prepared release assets: %s\n' "$output_path"
