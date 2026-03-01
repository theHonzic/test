# Automation Scripts

This directory contains shell scripts to automate building, documenting, and releasing the **MinimalPackage** project.

## Scripts Overview

| Script | Description |
| :--- | :--- |
| [`archive.sh`](./archive.sh) | Builds XCFrameworks for iOS and iOS Simulator, then bundles them into a zip archive with a checksum. |
| [`generate-docs.sh`](./generate-docs.sh) | Generates DocC documentation and transforms it into a static HTML site for GitHub Pages. |
| [`release.sh`](./release.sh) | Orchestrates the full release process, including documentation generation, archiving, and publishing to GitHub. |

---

## 🛠 `archive.sh`

Builds the framework for distribution.

### What it does:
1.  **Archives** the `MinimalPackage` target for `iOS` and `iOS Simulator`.
2.  **Creates** an `XCFramework` combining both architectures.
3.  **Zips** the result into `build/MinimalPackage.xcframework.zip`.
4.  **Computes** a SHA-256 checksum for use in `Package.swift`.

### Usage:
```bash
./scripts/archive.sh
```

---

## 📚 `generate-docs.sh`

Builds documentation using Swift DocC.

### What it does:
-  Generates a static HTML site in the `docs/` folder.
-  Supports live preview and local serving.

### Usage:
```bash
# Build static site into docs/
./scripts/generate-docs.sh

# Build and serve locally (at http://localhost:8000)
./scripts/generate-docs.sh --serve
```

---

## 🚀 `release.sh`

The primary tool for publishing a new version. **Requires `gh` CLI.**

### What it does:
1.  **Validates** the working tree is clean and the version is valid SemVer.
2.  **Generates** fresh documentation via `generate-docs.sh`.
3.  **Builds** the XCFramework archive via `archive.sh`.
4.  **Prepares** the `main` branch (as an orphan or update) containing *only* the distribution `Package.swift` (pointing to binary targets), `docs/`, and `index.html`.
5.  **Commits, tags, and pushes** the release to GitHub.
6.  **Creates** a GitHub Release and uploads the `.zip` artifact.

### Usage:
```bash
./scripts/release.sh 1.0.0
```

> [!IMPORTANT]
> This script switches branches. Ensure you have no uncommitted changes before running.
