# ravpkg Package Manifest Specification

**Document Version:** 1.0.0  
**Target System:** ravynOS (Darwin/FreeBSD userland)  
**Status:** Phase 1 Scaffolding

---

## 1. Overview

The `ravpkg` manifest defines the metadata, contents, integrity checksums, and dependency declarations for a package built for the **ravynOS** operating system.

Manifests are stored in **JSON** (canonical format: `manifest.json`) or alternatively **TOML** (`manifest.toml`). The primary runtime engine parses JSON manifests packaged inside `.rav` / `.tar.zst` distribution archives.

---

## 2. Schema Specification

A valid `manifest.json` root object contains the following fields:

| Field | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `name` | `string` | **Yes** | Unique package identifier (lowercase alphanumeric with hyphens/underscores). |
| `version` | `string` | **Yes** | Semantic version string (e.g. `1.0.0`, `2.4.1-p1`). |
| `description` | `string` | **Yes** | Brief human-readable summary of the package. |
| `checksum` | `string` | **Yes** | SHA-256 hex digest (exactly 64 hexadecimal characters) of the package payload or archive. |
| `install_paths` | `array[object]` | **Yes** | List of source-to-destination file mapping definitions. Must contain at least one item. |
| `dependencies` | `array[object]` | No | List of prerequisite packages with version constraints. Schema-only in Phase 1-2. |

---

### 2.1. `install_paths` Object

Defines where files from the package archive map onto the ravynOS filesystem hierarchy:

```json
{
  "source": "bin/ravterm",
  "destination": "/usr/local/bin/ravterm"
}
```

- **`source`** (`string`, required): Relative path inside the package archive payload. Cannot be empty or point outside package archive.
- **`destination`** (`string`, required): Absolute path on the target filesystem where the file or bundle will be installed.

---

### 2.2. `dependencies` Object

Specifies package requirements. Dependency resolution logic is deferred to later phases; currently validated for schema conformity only:

```json
{
  "name": "libsystem",
  "constraint": ">=1.2.0"
}
```

- **`name`** (`string`, required): Target package identifier.
- **`constraint`** (`string`, optional): Semantic version constraint expression (e.g. `>=1.0.0`, `^2.1`, `=0.9.5`).

---

### 2.3. `checksum` Field

The `checksum` string must match standard SHA-256 formatting:
- Regex: `^[a-fA-F0-9]{64}$`
- Example: `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`

---

## 3. Example Manifest (JSON)

```json
{
  "name": "ravterm",
  "version": "1.0.0",
  "description": "Native terminal emulator for ravynOS desktop",
  "checksum": "a1b2c3d4e5f60718293a4b5c6d7e8f90123456789abcdef0123456789abcdef0",
  "install_paths": [
    {
      "source": "Applications/Terminal.app",
      "destination": "/Applications/Terminal.app"
    },
    {
      "source": "bin/ravterm",
      "destination": "/usr/local/bin/ravterm"
    }
  ],
  "dependencies": [
    {
      "name": "libcoregraphics",
      "constraint": ">=0.4.0"
    }
  ]
}
```

---

## 4. Error Conditions

The manifest parser (`internal/parser`) enforces these rules:
1. **Missing Required Field:** Returns an error specifying which required key (`name`, `version`, `description`, `checksum`, `install_paths`) is absent or empty.
2. **Invalid Checksum:** Returns an error if the checksum is not a valid 64-character hexadecimal SHA-256 string.
3. **Empty Install Paths:** Returns an error if `install_paths` is empty or if any item has an empty `source` or `destination`.
4. **Malformed Syntax:** Returns a parse error if JSON is structurally malformed.
