# Continuous integration and Pkl releases

Pull requests and pushes to `main` run four workflows. Each also supports manual execution with `workflow_dispatch`.

| Workflow | Checks |
| --- | --- |
| Build and test xcprojgen | Builds the CLI and runs every Swift test with `PKL_EXEC` set, including Pkl integration and package-consumption tests. |
| swift-format | Runs strict `xcrun swift-format` lint on every tracked Swift file using the repository's four-space configuration. |
| Pkl tests | Runs the public API tests and prepares release assets without uploading them. |
| Examples smoke tests | Generates, validates, and builds Tool, Workspace, iOS, Advanced, and MixedWorkspace in separate matrix jobs. |

The macOS workflows use the ARM64 `xcode-27` runner and explicitly select `/Applications/Xcode_27.2.app/Contents/Developer`. Xcode 27.2 is required for the JSON project format; the runner's default Xcode may be older. See the [official runner image inventory](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md). Pkl-only jobs run on Ubuntu 24.04.

The local `setup-pkl` action requires a `version` input. Workflows currently select Pkl 0.33.0:

```yaml
- uses: ./.github/actions/setup-pkl
  with:
    version: '0.33.0'
```

The action downloads the official native executable for that version, verifies its SHA-256 digest from the GitHub release asset metadata, and sets both `PATH` and `PKL_EXEC`. A missing or invalid digest fails installation. It uses the built-in GitHub token to read release metadata; no additional secret is needed. To upgrade Pkl, change the callers' `version` inputs. The download locations follow the [official installation guide](https://pkl-lang.org/main/current/pkl-cli/index.html#installation).

Smoke tests run unsigned macOS and iOS Simulator builds. They also compile the examples' test bundles; running those bundles and delivering push notifications are outside their scope. The tool examples execute their built binaries, Advanced verifies package linkage and script output, and MixedWorkspace builds both its generated and existing projects.

## Publishing a Pkl package

Publish a GitHub Release with a tag such as `0.1.0`. The Publish Pkl package workflow checks out that release's commit, derives the package version from its tag, runs packaging and API validation, and uploads:

- `package.zip`
- `package.zip.sha256`
- `xcproj@0.1.0`
- `xcproj@0.1.0.sha256`

The metadata and checksums are required alongside the ZIP for Pkl dependency resolution. See the [official Pkl packaging documentation](https://pkl-lang.org/main/current/pkl-cli/index.html#pkl-project-package).

Only exact `X.Y.Z` tags are accepted, without a prefix or leading zeroes. Other tag formats fail validation before packaging. The workflow subscribes to [`release.published`](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#release), so creating a draft or pushing a tag alone does not publish artifacts. The workflow must be included in the tagged commit.

The upload uses the repository's `GITHUB_TOKEN` with `contents: write` permission; other workflows have read-only repository permissions. No additional secret is needed. Existing release assets are not overwritten. If an upload only partially succeeds, remove the incomplete upload's assets before rerunning the failed workflow.

For an offline packaging check, without creating or modifying a GitHub Release:

```sh
PKL_EXEC="$(command -v pkl)" bash Scripts/prepare-pkl-release.sh 0.1.0 --output-path /tmp/xcproj-pkl-release
```

Publishing assets does not change repository visibility. Consumers need access to the release URLs; local dependencies and locally installed package caches continue to work for private development.
