# Continuous integration and releases

Pull requests and pushes to `main` run five workflows. Each also supports manual execution with `workflow_dispatch`.

| Workflow | Checks |
| --- | --- |
| Build and test xcprojgen | Builds the CLI and runs every Swift test. Tests of the schema and generation evaluate real Pkl modules through `XCProjGenKit`; they fail, rather than skip, when a supported Pkl is not installed (`PKL_EXEC`, then `pkl` on `PATH`). No test launches the `xcprojgen` executable. The job also checks Universal binary packaging and formula generation without publishing. |
| swift-format | Runs strict `swift format` lint on Ubuntu with the official Swift 6.4.2 container, using the repository's four-space configuration. |
| Pkl tests | Runs the public API tests and prepares release assets without uploading them. |
| Examples smoke tests | Runs the CLI commands end to end (`doctor`, `skills export`, and `init` → `validate` → `generate`), then validates, generates, and builds Tool, Workspace, iOS, Advanced, and MixedWorkspace sequentially in one macOS job, reusing the CLI build outputs. |
| Pkl API documentation | Generates pkldoc and uploads a Pages artifact. Deploys on pushes to `main` and manual runs on `main`. |

The Swift tests and Examples use the ARM64 `xcode-27` runner and explicitly select `/Applications/Xcode_27.2.app/Contents/Developer`. Xcode 27.2 is required for the JSON project tools used during generation. See the [official runner image inventory](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md). Pkl tests, package preparation, Pkl API documentation, and swift-format run on Ubuntu 24.04. The formatter uses the [official Swift container](https://www.swift.org/install/linux/ubuntu/24_04/).

The local `setup-pkl` action requires a `version` input. Workflows currently select Pkl 0.33.0:

```yaml
- uses: ./.github/actions/setup-pkl
  with:
    version: '0.33.0'
```

The action downloads the official native executable for that version, verifies its SHA-256 digest from the GitHub release asset metadata, and sets both `PATH` and `PKL_EXEC`. Set `pkldoc: 'true'` to also install pkldoc from the same release, with the same checksum verification. A missing or invalid digest fails installation. It uses the built-in GitHub token to read release metadata; no additional secret is needed. To upgrade Pkl, change the callers' `version` inputs. The download locations follow the [official installation guide](https://pkl-lang.org/main/current/pkl-cli/index.html#installation).

Smoke tests run unsigned macOS and iOS Simulator builds. They also compile the examples' test bundles; running those bundles and delivering push notifications are outside their scope. The tool examples execute their built binaries, Advanced verifies package linkage and script output, and MixedWorkspace builds both its generated and existing projects.

## Pkl API documentation on GitHub Pages

The `pkldoc.yml` workflow builds the checked-out sources using [pkldoc](https://pkl-lang.org/main/current/pkl-doc/index.html). It documents the two public modules, `Project` and `Workspace`, which declare every public type such as `Target`, `Settings`, and `Scheme`; `Internal/` modules are not documented. Documentation metadata lives in `Pkl/xcproj/doc-package-info.pkl` and `Docs/pkldoc/docsite-info.pkl`; the package descriptor is excluded from distributed packages and CLI resources.

This site follows `main`, rather than retaining published release versions. Pkldoc version `0.0.0` denotes unversioned documentation, and source links point to the exact commit being built. The `--no-symlinks` option makes `current` a real directory, as required by [GitHub Pages artifacts](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).

Pull requests only build and upload the `github-pages` artifact. Deployment runs after a successful build on `main`, using the `github-pages` environment and job-scoped `pages: write` and `id-token: write` permissions. Manual runs on another branch only build the documentation. Running deployments are not cancelled by newer pushes.

Before the first deployment, open **Settings → Pages → Build and deployment → Source** and select **GitHub Actions**. If the `github-pages` environment restricts deployments, allow `main`. After merging, the push to `main` deploys the site; use **Actions → Pkl API documentation → Run workflow** on `main` to retry after configuring Pages. No personal access token or Pages branch is needed. The deployment job reports the site URL, currently <https://giginet.me/xcproj.pkl/>. Pages availability and site visibility are controlled by the repository's GitHub plan and Pages settings.

To build locally with pkldoc 0.33.0 installed:

```sh
pkldoc --no-symlinks --output-dir dist/pkldoc \
  --property "sourceRef=$(git rev-parse HEAD)" \
  Docs/pkldoc/docsite-info.pkl Pkl/xcproj/doc-package-info.pkl \
  Pkl/xcproj/Project.pkl Pkl/xcproj/Workspace.pkl
python3 -m http.server --directory dist/pkldoc 8000
```

Open `http://localhost:8000`; pkldoc's search and navigation require HTTP rather than a `file:` URL.

## Releasing CLI and Pkl together

CLI and Pkl package releases share one semantic version because the CLI embeds
the renderer that consumes the Pkl models. A change to either component produces
a release of both. Use a major version for breaking CLI or public Pkl API
changes, a minor version for compatible additions, and a patch for compatible
fixes. Before 1.0, use a minor version for breaking changes.

The release tag is the source of truth. The workflow passes it to the Pkl
packager and writes it into the staged CLI resource bundle. Thus `--version`,
the dependency created by `init`, package metadata, and the Homebrew formula
agree. No source version bump or formula edit is required before releasing.
`Pkl/xcproj/Internal/Version.txt` is only the default version for local builds
and local packaging; release packaging does not modify the checkout or build
outputs. Existing consumers should update their `PklProject` dependency along
with the CLI; upgrades do not edit their projects automatically.

### Maintainer steps

1. Merge the intended changes into `main` and wait for CI to pass.
2. Publish a **stable** GitHub Release from that commit using an unprefixed tag
   such as `0.1.0`. For example, with the tested commit SHA:

   ```sh
   gh release create 0.1.0 --target <tested-commit-sha> --generate-notes
   ```

3. Wait for **Release xcprojgen and Pkl** to finish. The existing
   `pkl-release.yml` workflow builds and checks both packages before uploading
   their assets. The release is visible while this runs; installation is ready
   only after the assets and formula have been published.
4. The workflow downloads the published CLI archive, verifies its checksum,
   generates `Formula/xcprojgen.rb`, and commits it directly to `main` as
   `github-actions[bot]`. Users can then run `brew update` and `brew upgrade`.

The formula must be updated **after** the binary exists: its SHA-256 describes
the actual archive. The first release creates the formula from
`Formula/xcprojgen.rb.template`; subsequent releases replace it. Edit the
template when changing installation behavior. The post-release formula commit
is deliberately not part of the release tag, and must not cause a second
release or a moved tag. An older release cannot downgrade the current formula.

Only exact `X.Y.Z` tags are accepted, without prefixes or leading zeroes.
Prereleases are skipped. The workflow subscribes to
[`release.published`](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#release),
so creating a draft or pushing a tag alone does not publish assets. The workflow
must exist in the tagged commit. Use the GitHub UI or your own authenticated
`gh` session to publish the release; an event created by another workflow's
`GITHUB_TOKEN` does not start this workflow.

### Assets and installation

Each release contains:

- `xcprojgen-X.Y.Z-macos-universal.tar.gz` and its `.sha256` sidecar.
- `package.zip` and `package.zip.sha256`.
- `xcproj@X.Y.Z` and `xcproj@X.Y.Z.sha256`.

The CLI archive contains the arm64/x86_64 executable, its
`xcprojgen_PklRuntimeResources.bundle` (the renderer, the public Pkl modules it
imports, and the agent skill), and project/dependency licenses. Packaging checks
both architectures, then runs the executable from the staging directory, away
from the build outputs: its version, scaffold dependency, agent skill export,
and Pkl evaluation using the bundled renderer. This is the only check of a
relocated installation. The binary uses ad-hoc signing; this
workflow does not perform Developer ID signing or notarization. The formula
installs the executable and resource bundle together under `libexec` and adds
a wrapper in `bin`.

The Pkl metadata and checksums must remain alongside `package.zip` for dependency
resolution. See the [official Pkl packaging documentation](https://pkl-lang.org/main/current/pkl-cli/index.html#pkl-project-package).
The tap uses ordinary public GitHub Release URLs and requires no download token.

### Permissions and recovery

The release jobs use the built-in `GITHUB_TOKEN` with `contents: write` for asset
uploads and the formula commit. Other workflows have read-only repository
contents permissions; the Pages deployment job separately has Pages and OIDC
write permissions. No additional secret is needed. Repository rules must allow this token to push to `main`.
If branch protection requires PRs or checks for every commit, configure an
authorized GitHub App and its bypass permissions before enabling direct formula
updates; `contents: write` alone does not bypass those rules. The token's push
does not start another CI run, so the release job checks formula syntax before
committing.

Existing assets are never overwritten. If packaging fails, fix the cause and
rerun the workflow. After a partial upload, remove only the incomplete run's
uploaded assets before retrying; once a version has been consumed, publish a new
version instead of replacing it. If only **update-formula** fails (for example,
`main` advanced during the push), rerun **failed jobs only**: it downloads the
existing archive and retries from current `main`, without rebuilding or
replacing any release assets. Repeating a successful formula update creates no
empty commit, and changing an existing version's checksum is rejected.

### Local packaging check

With Xcode 27.2+ and Pkl installed, use fresh output directories:

```sh
bash Scripts/prepare-pkl-release.sh 1.2.3 --output-path /tmp/xcproj-pkl-release
bash Scripts/prepare-cli-release.sh 1.2.3 --output-path /tmp/xcproj-cli-release
python3 Scripts/update-homebrew-formula.py 1.2.3 \
  /tmp/xcproj-cli-release/xcprojgen-1.2.3-macos-universal.tar.gz \
  --output /tmp/xcprojgen.rb
```

These scripts neither upload assets nor commit files. Pkl packaging runs its API
tests offline; the CLI build may fetch SwiftPM dependencies on the first run.
