# Continuous integration and Pkl releases

Pull requests and pushes to `main` run five workflows. Each also supports manual execution with `workflow_dispatch`.

| Workflow | Checks |
| --- | --- |
| Build and test xcprojgen | Builds the CLI and runs every Swift test with `PKL_EXEC` set, including Pkl integration and package-consumption tests. |
| swift-format | Runs strict `swift format` lint on Ubuntu with the official Swift 6.4.2 container, using the repository's four-space configuration. |
| Pkl tests | Runs the public API tests and prepares release assets without uploading them. |
| Examples smoke tests | Validates, generates, and builds Tool, Workspace, iOS, Advanced, and MixedWorkspace sequentially in one macOS job, reusing the CLI build outputs. |
| Pkl API documentation | Generates pkldoc and uploads a Pages artifact. Deploys on pushes to `main` and manual runs on `main`. |

CLI integration tests and Examples use the ARM64 `xcode-27` runner and explicitly select `/Applications/Xcode_27.2.app/Contents/Developer`. Xcode 27.2 is required for the JSON project tools used during generation. See the [official runner image inventory](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md). Pkl tests, package preparation, Pkl API documentation, and swift-format run on Ubuntu 24.04. The formatter uses the [official Swift container](https://www.swift.org/install/linux/ubuntu/24_04/).

The local `setup-pkl` action requires a `version` input. Workflows currently select Pkl 0.33.0:

```yaml
- uses: ./.github/actions/setup-pkl
  with:
    version: '0.33.0'
```

The action downloads the official native executable for that version, verifies its SHA-256 digest from the GitHub release asset metadata, and sets both `PATH` and `PKL_EXEC`. Set `pkldoc: 'true'` to also install pkldoc from the same release, with the same checksum verification. A missing or invalid digest fails installation. It uses the built-in GitHub token to read release metadata; no additional secret is needed. To upgrade Pkl, change the callers' `version` inputs. The download locations follow the [official installation guide](https://pkl-lang.org/main/current/pkl-cli/index.html#installation).

Smoke tests run unsigned macOS and iOS Simulator builds. They also compile the examples' test bundles; running those bundles and delivering push notifications are outside their scope. The tool examples execute their built binaries, Advanced verifies package linkage and script output, and MixedWorkspace builds both its generated and existing projects.

## Pkl API documentation on GitHub Pages

The `pkldoc.yml` workflow builds the checked-out sources using [pkldoc](https://pkl-lang.org/main/current/pkl-doc/index.html). It includes `Project`, `Workspace`, and the model modules that define inherited types such as `Target`, `Settings`, and `Scheme`. The documented modules' names match their file paths so generated source links resolve correctly. Documentation metadata lives in `Pkl/xcproj/doc-package-info.pkl` and `Docs/pkldoc/docsite-info.pkl`; the package descriptor is excluded from distributed packages and CLI resources.

This site follows `main`, rather than retaining published release versions. Pkldoc version `0.0.0` denotes unversioned documentation, and source links point to the exact commit being built. The `--no-symlinks` option makes `current` a real directory, as required by [GitHub Pages artifacts](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).

Pull requests only build and upload the `github-pages` artifact. Deployment runs after a successful build on `main`, using the `github-pages` environment and job-scoped `pages: write` and `id-token: write` permissions. Manual runs on another branch only build the documentation. Running deployments are not cancelled by newer pushes.

Before the first deployment, open **Settings → Pages → Build and deployment → Source** and select **GitHub Actions**. If the `github-pages` environment restricts deployments, allow `main`. After merging, the push to `main` deploys the site; use **Actions → Pkl API documentation → Run workflow** on `main` to retry after configuring Pages. No personal access token or Pages branch is needed. The deployment job reports the site URL, currently <https://giginet.me/xcproj.pkl/>. Pages availability and site visibility are controlled by the repository's GitHub plan and Pages settings.

To build locally with pkldoc 0.33.0 installed:

```sh
pkldoc --no-symlinks --output-dir dist/pkldoc \
  --property "sourceRef=$(git rev-parse HEAD)" \
  Docs/pkldoc/docsite-info.pkl Pkl/xcproj/doc-package-info.pkl \
  Pkl/xcproj/Project.pkl Pkl/xcproj/Workspace.pkl \
  Pkl/xcproj/Internal/{ProjectModel,SchemaTypes,SchemeModel,WorkspaceModel}.pkl
python3 -m http.server --directory dist/pkldoc 8000
```

Open `http://localhost:8000`; pkldoc's search and navigation require HTTP rather than a `file:` URL.

## Publishing a Pkl package

Publish a GitHub Release with a tag such as `0.1.0`. The Publish Pkl package workflow checks out that release's commit, derives the package version from its tag, runs packaging and API validation, and uploads:

- `package.zip`
- `package.zip.sha256`
- `xcproj@0.1.0`
- `xcproj@0.1.0.sha256`

The metadata and checksums are required alongside the ZIP for Pkl dependency resolution. See the [official Pkl packaging documentation](https://pkl-lang.org/main/current/pkl-cli/index.html#pkl-project-package).

Only exact `X.Y.Z` tags are accepted, without a prefix or leading zeroes. Other tag formats fail validation before packaging. The workflow subscribes to [`release.published`](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#release), so creating a draft or pushing a tag alone does not publish artifacts. The workflow must be included in the tagged commit.

The upload uses the repository's `GITHUB_TOKEN` with `contents: write` permission; other workflows have read-only repository contents permissions. The Pages deployment job separately has Pages and OIDC write permissions. No additional secret is needed. Existing release assets are not overwritten. If an upload only partially succeeds, remove the incomplete upload's assets before rerunning the failed workflow.

For an offline packaging check, without creating or modifying a GitHub Release:

```sh
PKL_EXEC="$(command -v pkl)" bash Scripts/prepare-pkl-release.sh 0.1.0 --output-path /tmp/xcproj-pkl-release
```

Publishing assets does not change repository visibility. Consumers need access to the release URLs; local dependencies and locally installed package caches continue to work for private development.
