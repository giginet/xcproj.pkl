# xcproj Pkl package

Typed authoring schemas for `xcproj-pkl` (schema version 2, Pkl 0.33+).

- `Project.pkl`: project module class; exports `Target`, `Settings`, `Source`, and `Dependency`.
- `Workspace.pkl`: workspace module class, collecting local Project modules.
- `Internal/`: implementation dependencies required by the public modules and Swift CLI renderer; not a stable public API.
- `PklProject`: package identity, version, artifact URL, and API tests.

Consumer example, once the artifacts have been published:

```pkl
// PklProject
amends "pkl:Project"
dependencies {
  ["xcproj"] {
    uri = "package://github.com/giginet/xcproj.pkl/releases/download/v0.1.0/xcproj@0.1.0"
  }
}
```

Resolve dependencies with `pkl project resolve`. Then define a local Project.pkl:

```pkl
amends "@xcproj/Project.pkl"
name = "Tool"
targets {
  ["hello"] {
    name = "Hello"
    type = "tool"
    platform = "macOS"
    sources { new { path = "Sources" } }
  }
}
```

Use `import "@xcproj/Project.pkl" as X` to define reusable classes extending `X.Target` and reusable `X.Settings` objects. Workspace.pkl can amend `@xcproj/Workspace.pkl` and import local Project modules. Run the resulting local entry through the matching Swift CLI; evaluating the public schemas produces an intermediate Snapshot, not the final Xcode project.

For checkout-based development, a consumer may use a local dependency instead:

```pkl
amends "pkl:Project"
dependencies {
  ["xcproj"] = import("/path/to/xcproj.pkl/Pkl/xcproj/PklProject")
}
```

From the repository root:

```sh
# API tests, archive, metadata, and checksums.
Scripts/package-pkl.sh

# Local/offline packaging (no published-version lookup).
Scripts/package-pkl.sh --skip-publish-check
```

The output is `dist/pkl/xcproj@0.1.0/` with four files: `xcproj@0.1.0.zip`, `xcproj@0.1.0`, and their `.sha256` sidecars. The ZIP contains package-root modules and README; tests and project manifests are excluded. Swift sources and application-specific examples are outside this package directory.

Publication layout is configured for GitHub Releases tag `v0.1.0`. Upload all four artifacts to that release: the package URI's HTTPS equivalent serves metadata, and `packageZipUrl` serves the archive. No upload or release creation is performed here. These URLs describe a future accessible GitHub Release. The repository is currently private and hosting has not been configured; choose metadata and ZIP URLs that consumers can actually retrieve before publishing. Local cache installation and local dependencies do not require publishing.

Official specifications:

- [Creating a package and local dependencies](https://pkl-lang.org/main/current/language-reference/index.html#creating-a-package)
- [pkl project package](https://pkl-lang.org/main/current/pkl-cli/index.html#pkl-project-package)
- [Package metadata, exclusions, and API tests](https://pkl-lang.org/package-docs/pkl/current/Project/Package.html)
