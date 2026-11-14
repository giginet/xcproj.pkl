#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_dir="$repo_root/Pkl/xcproj"
pkl_exec="${PKL_EXEC:-pkl}"
output_path="$repo_root/dist/pkl/%{name}@%{version}"
package_options=(project package)

usage() {
  cat <<'USAGE'
Usage: Scripts/package-pkl.sh [--pkl PATH] [-o DIRECTORY] [pkl project package options]

Build the xcproj Pkl package, including metadata and SHA-256 sidecars.
The package version and download URLs are defined in Pkl/xcproj/PklProject.

  --pkl PATH                Pkl executable (default: PKL_EXEC or PATH)
  -o, --output-path DIR     Output directory; supports %{name} and %{version}
  -h, --help                Show this help

Other options are passed to pkl project package, including:
  --skip-publish-check      Offline/local packaging; skip the published-version check
  --install                Install the package into Pkl's package cache
  --cache-dir DIR          Select the cache directory

Default output: dist/pkl/%{name}@%{version}/
No release is uploaded by this script.
USAGE
}

while (($#)); do
  case "$1" in
    --pkl|-o|--output-path)
      if (($# < 2)); then
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
    *) package_options+=("$1"); shift ;;
  esac
done

if [[ "$output_path" != /* ]]; then
  output_path="$PWD/$output_path"
fi

# Use Pkl's packager, which checks imports/API tests and produces its wire metadata.
# An ordinary zip command would omit the metadata needed by package: imports.
exec "$pkl_exec" "${package_options[@]}" \
  --output-path "$output_path" \
  "$project_dir"
