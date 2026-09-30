# ravpkg Repository Index Specification

**Document Version:** 1.0.0  
**Target System:** ravynOS (Darwin/FreeBSD userland)  
**Status:** Phase 4 Tooling / Phase 2 Integration

---

## 1. Overview

The `ravpkg` repository index (`index.json`) is a flat JSON catalog describing packages available from a remote repository or local mirror. Clients fetch and cache this index to perform package searches and identify available versions, download locations, and integrity checksums.

---

## 2. Schema Specification

The repository index root is a **JSON array** of package descriptor objects:

```json
[
  {
    "name": "ravterm",
    "version": "1.0.0",
    "description": "Terminal emulator for ravynOS",
    "download_url": "https://repo.ravynos.com/packages/ravterm-1.0.0.rav",
    "checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  }
]
```

### 2.1. Package Descriptor Fields

| Field | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `name` | `string` | **Yes** | Unique package identifier matching the manifest name. |
| `version` | `string` | **Yes** | Semantic version string. |
| `description` | `string` | **Yes** | Brief description of the package. |
| `download_url` | `string` | **Yes** | Absolute HTTP(S) or local file URL to download the `.rav` package archive. |
| `checksum` | `string` | **Yes** | SHA-256 digest (64 hex characters) of the package payload or archive. |
| `dependencies` | `array` | No | Array of `{name, constraint}` dependency requirements. |

---

## 3. Client Caching & Search Behavior

- **Cache Location**:
  1. `$RAVPKG_REPO_CACHE` if set.
  2. `${RAVPKG_ROOT}/var/cache/ravpkg/index.json` if `--root` is set.
  3. `/var/cache/ravpkg/index.json` if `/var/cache` is writable.
  4. `${XDG_CACHE_HOME:-$HOME/.cache}/ravpkg/index.json` (fallback).
- **Search Query Matching**:
  - `ravpkg search <query>` performs a case-insensitive substring match across both `name` and `description`.
  - Output is presented in a formatted terminal table (`NAME`, `VERSION`, `DESCRIPTION`).
- **Uncached Handling**:
  - If the cache does not exist and no `--repo` is specified, `ravpkg search` exits with code 1 and displays a helpful error pointing to `ravpkg update`.

---

## 4. Index Generation

The repository index generator tool (`repo/generate-index.sh` or `ravpkg-generate-index`) scans a directory of `.json` package manifests, validates required fields and checksums, and produces a sorted `index.json`:

```bash
repo/generate-index.sh --url-prefix https://repo.ravynos.com/packages -o index.json /path/to/manifests
```
