---
name: release
description: Publish a new xcprojgen and xcproj Pkl package release for this repository. Use when asked to release, cut a version, publish to Homebrew, or check or recover a release run.
---

# Releasing xcprojgen and the xcproj Pkl package

The CLI and the Pkl package ship together under one unprefixed `X.Y.Z` tag.
Publishing a GitHub Release triggers `.github/workflows/pkl-release.yml`, which
builds and uploads both packages, then commits `Formula/xcprojgen.rb` to `main`.
[Docs/CI.md](../../../Docs/CI.md#releasing-cli-and-pkl-together) is the reference;
read it when a step below does not go as described.

Publishing is public and cannot be undone: a version that users may have
downloaded is never replaced. Always get the maintainer's explicit confirmation
of the version and commit immediately before step 5.

## 1. Check the release commit

```sh
git fetch origin --tags
git status -sb                     # clean, on main, not behind origin/main
gh run list --commit "$(git rev-parse origin/main)" --json name,conclusion
```

Every workflow for the commit must have concluded `success`. If CI is still
running or failed, stop and report.

## 2. Choose the version

```sh
gh release list --limit 5
git log --oneline "$(git describe --tags --abbrev=0 2>/dev/null)"..origin/main
```

- Breaking change to the CLI or the public Pkl API (`Project.pkl`, `Workspace.pkl`):
  major, or minor while the version is below 1.0.
- Compatible addition: minor. Compatible fix: patch.
- The tag is exactly `X.Y.Z`: no `v` prefix, no leading zeroes, no pre-release
  suffix. Pre-releases are skipped by the workflow.

Propose the version with a short summary of the changes and wait for confirmation.

## 3. Prepare the release commit

The release workflow stamps the tag into the archive it builds, but the sources
keep their own copy of the version. Update it before tagging so that the tagged
commit, source builds, and the API reference all report the version being
released.

1. `Pkl/xcproj/Internal/Version.txt`: set to `X.Y.Z`. Source builds read it for
   `xcprojgen --version`, for the package that `xcprojgen init` pins, and as the
   default version of the Pkl package.
2. `Pkl/xcproj/doc-package-info.pkl`: set `version = "X.Y.Z"`. The API reference
   site is built from `main` and shows this value.
3. Regenerate the Examples' lock file, which records the package version:

   ```sh
   pkl project resolve Examples
   ```

4. `Pkl/xcproj/README.md`: update the version in the consumer example's package
   URI and in the packaging output paths.

Do not edit `Formula/xcprojgen.rb`; the workflow generates it from the published
archive. The example versions in `Docs/CI.md` and the version argument in
`.github/workflows/pkl-tests.yml` are placeholders and stay as they are.

Check the result, then commit:

```sh
swift run xcprojgen --version      # prints X.Y.Z
git grep -n '<previous version>'   # only placeholders and Formula/ should remain
git commit -am "Prepare X.Y.Z"
```

Land the commit on `main`, directly or through a pull request as the maintainer
prefers. Then repeat step 1 for it: the release is published from this commit,
after its CI has passed.

## 4. Check packaging locally (optional)

Worth doing when the release scripts, `Package.swift` resources, or the formula
template changed since the last release. Requires Xcode 27.2+ and Pkl. Use an
output directory that does not exist yet:

```sh
out="$(mktemp -d)"
bash Scripts/prepare-pkl-release.sh X.Y.Z --output-path "$out/pkl"
bash Scripts/prepare-cli-release.sh X.Y.Z --output-path "$out/cli"
python3 Scripts/update-homebrew-formula.py X.Y.Z \
  "$out/cli/xcprojgen-X.Y.Z-macos-universal.tar.gz" --output "$out/xcprojgen.rb"
```

These neither upload nor commit anything.

## 5. Publish

After confirmation, publish a stable release from the checked commit:

```sh
gh release create X.Y.Z --target "$(git rev-parse origin/main)" --generate-notes
```

Use the maintainer's own `gh` session. A release created with a workflow's
`GITHUB_TOKEN` does not start the release workflow, and neither does a draft or
a pushed tag.

## 6. Watch the workflow and verify

```sh
gh run list --workflow pkl-release.yml --limit 1
gh run watch <run-id> --exit-status
gh release view X.Y.Z --json assets --jq '.assets[].name'
git pull --ff-only && grep -n 'version\|sha256' Formula/xcprojgen.rb
```

A complete release has six assets:

- `xcprojgen-X.Y.Z-macos-universal.tar.gz` and its `.sha256`
- `package.zip` and `package.zip.sha256`
- `xcproj@X.Y.Z` and `xcproj@X.Y.Z.sha256`

and a commit `Update xcprojgen formula to X.Y.Z` on `main` by
`github-actions[bot]`. Installation works only after both exist.

The **Pkl API documentation** workflow for the release commit deploys the site;
check that <https://giginet.me/xcproj.pkl/> shows `X.Y.Z`. Report the release
URL and what was verified.

## Recovery

- **`publish` failed before uploading**: fix the cause on `main`. The tag still
  points at the old commit, so delete the release and tag only if nothing was
  uploaded, then start again from step 1. Ask before deleting.
- **Upload partly succeeded**: remove only the assets from the incomplete run,
  then rerun the workflow. Existing assets are never overwritten.
- **Only `update-formula` failed** (for example `main` moved during the push):
  rerun failed jobs only with `gh run rerun <run-id> --failed`. It reuses the
  published archive.
- **A published version is wrong**: publish a new patch version. Do not replace
  assets or move the tag.
- **The formula push was rejected by branch rules**: report it; the repository
  rules must allow the workflow token to push to `main`.
