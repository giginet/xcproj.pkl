#!/bin/bash
# End-to-end check of the CLI commands with the real Pkl and Xcode tools:
# doctor, skills export, and init -> validate -> generate for both scaffolds.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/xcproj-pkl-cli-smoke.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
cd "$repo_root"
pkl="$(command -v "${PKL_EXEC:-pkl}")"
swift build
cli="$(swift build --show-bin-path)/xcprojgen"

"$cli" doctor --pkl "$pkl"
"$cli" skills export "$scratch/skills"
test -f "$scratch/skills/xcprojgen/SKILL.md"

# The scaffold depends on the published package. Install the local package into a
# private cache under the same URI so that no GitHub Release is required.
bash Scripts/package-pkl.sh --pkl "$pkl" --skip-publish-check --install \
  --cache-dir "$scratch/cache" --output-path "$scratch/dist"
cat > "$scratch/pkl" <<WRAPPER
#!/bin/sh
if [ "\$1" = --version ]; then exec "$pkl" "\$@"; fi
exec "$pkl" "\$@" --cache-dir "$scratch/cache"
WRAPPER
chmod +x "$scratch/pkl"

for type in workspace project; do
  root="$scratch/My $type"
  if [[ "$type" == project ]]; then
    mkdir "$root"
    (cd "$root" && "$cli" init)
  else
    "$cli" init "$root" --type workspace
  fi
  test "$(find "$root" -type f | wc -l | tr -d ' ')" = 2
  test -f "$root/PklProject"
  test -f "$root/Project.pkl"
  "$cli" validate "$root" --pkl "$scratch/pkl"
  "$cli" generate "$root" --pkl "$scratch/pkl" --output-dir "$scratch/Output $type"
  "$cli" generate "$root" --pkl "$scratch/pkl" --output-dir "$scratch/Output $type" | grep -q '^Unchanged'
done
test -f "$scratch/Output workspace/Workspace.xcworkspace/contents.xcworkspacedata"
test -f "$scratch/My workspace/Core.xcodeproj/project.xcproj"
test -f "$scratch/Output project/Core.xcodeproj/project.xcproj"
echo "CLI smoke test passed"
