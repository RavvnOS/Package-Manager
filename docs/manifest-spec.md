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
| `dependencies` | `array[object]` | No | List of prerequisite packages with version constraints. |
| `conflicts` | `array[string]` | No | List of package identifiers or virtual names this package cannot coexist with. |
| `provides` | `array[string]` | No | List of virtual package names or features this package satisfies (e.g. `vim` provided by `vim-gtk`). |
| `signature` | `string` | No | Optional filename or reference to detached GPG signature file (`.sig`) expected alongside the package. |

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

### 2.4. `conflicts` Array

Specifies packages or virtual capabilities with which this package cannot coexist. Installation will be rejected if any package named in `conflicts` (or providing a conflicting virtual name) is already installed, or if an installed package lists this package in its `conflicts`:

```json
"conflicts": [
  "vim-tiny",
  "vi"
]
```

- **Type:** `array[string]` (optional).
- Each item must be a non-empty string.

---

### 2.5. `provides` Array

Specifies virtual package names or abstract capabilities satisfied by this package. When resolving dependencies, `ravpkg` checks both package names and `provides` declarations:

```json
"provides": [
  "editor",
  "vim"
]
```

- **Type:** `array[string]` (optional).
- Each item must be a non-empty string.

---

### 2.6. `signature` Field

Specifies the expected filename or relative path to a detached GPG signature file (`.sig`) distributed alongside the package archive:

```json
"signature": "ravterm-1.0.0.rav.sig"
```

- **Type:** `string` (optional).
- If omitted, `ravpkg` defaults to checking for `<package-file>.sig`.
- When present, must be a non-empty string.

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
  ],
  "conflicts": [
    "ravterm-legacy"
  ],
  "provides": [
    "terminal-emulator"
  ],
  "signature": "ravterm-1.0.0.rav.sig"
}
```

---

## 4. Error Conditions

The manifest parser (`lib/parser.sh`) enforces these rules:
1. **Missing Required Field:** Returns an error specifying which required key (`name`, `version`, `description`, `checksum`, `install_paths`) is absent or empty.
2. **Invalid Checksum:** Returns an error if the checksum is not a valid 64-character hexadecimal SHA-256 string.
3. **Empty Install Paths:** Returns an error if `install_paths` is empty or if any item has an empty `source` or `destination`.
4. **Invalid Conflicts:** Returns an error if `conflicts` is present but is not an array of non-empty strings.
5. **Invalid Provides:** Returns an error if `provides` is present but is not an array of non-empty strings.
6. **Invalid Signature:** Returns an error if `signature` is present but is empty or not a string.
7. **Malformed Syntax:** Returns a parse error if JSON is structurally malformed.
