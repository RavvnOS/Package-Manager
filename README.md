# ravpkg

`ravpkg` is a minimal-viable package manager designed for **ravynOS** (a macOS-compatible open-source operating system built on a Darwin/FreeBSD userland).

This repository contains the **Phase 1–2 scaffolding**: package manifest schema, local SQLite database tracking, manifest parser with validation, and CLI command routing.

---

## Command Status

| Command | Status | Description | Phase |
| :--- | :--- | :--- | :--- |
| `ravpkg list` | **Functional** | Queries and lists all installed packages from local SQLite DB. | Phase 1 |
| `ravpkg info <pkg>` | **Functional** | Displays metadata and installed file paths for a package. | Phase 1 |
| `ravpkg install <file>` | **Stub** | Unpack and filesystem install logic (deferred to Phase 2). | Phase 2 |
| `ravpkg remove <pkg>` | **Stub** | Filesystem file removal logic (deferred to Phase 2). | Phase 2 |
| `ravpkg search <query>` | **Stub** | Remote repository index query (deferred to Phase 4). | Phase 4 |

> [!NOTE]
> Dependency resolution and launchd/daemon service integration are deferred to subsequent phases.

---

## Project Structure

```text
ravpkg/
├── cmd/
│   └── ravpkg/
│       └── main.go             # CLI entrypoint with Cobra command routing
├── internal/
│   ├── db/
│   │   ├── db.go               # SQLite CRUD operations (installed_packages table)
│   │   └── db_test.go          # Unit tests using in-memory SQLite (:memory:)
│   ├── model/
│   │   └── manifest.go         # Manifest, InstalledPackage, and Dependency structs
│   └── parser/
│       ├── parser.go           # Manifest JSON parser and validator
│       └── parser_test.go      # Unit tests for parser and error validation
├── repo/
│   ├── repo.go                 # Phase 4 repository/index tooling stub
│   └── README.md               # Overview of future remote repository index
├── tests/
│   └── fixtures/
│       ├── valid-manifest.json          # Example valid package manifest
│       ├── with-deps-manifest.json      # Manifest with dependencies & multiple paths
│       ├── missing-fields-manifest.json # Invalid manifest (missing required fields)
│       └── bad-checksum-manifest.json   # Invalid manifest (malformed SHA256)
├── docs/
│   └── manifest-spec.md        # Formal specification for package manifest schema
├── .gitignore                  # Build artifacts, SQLite files, OS files
├── Makefile                    # Build, test, lint, and cross-compilation targets
├── go.mod                      # Go module definition
├── go.sum                      # Checksums for dependencies
└── README.md                   # Project documentation
```

---

## Requirements

- **Go 1.21+** (Go 1.27+ tested)
- No C compiler or CGO required (uses pure-Go SQLite via `modernc.org/sqlite`)

---

## Build & Test Instructions

### Building the CLI
```bash
# Using Go directly
go build -o ravpkg ./cmd/ravpkg

# Using Makefile
make build
```

### Running Unit Tests
```bash
# Run all unit tests with verbose output
go test -v ./...

# Using Makefile
make test
```

### Cross-Compiling for ravynOS
```bash
# Target Darwin (amd64 / arm64)
make build-darwin

# Target FreeBSD userland (amd64)
make build-freebsd
```

---

## Usage Examples

```bash
# Show command help
./ravpkg --help

# List installed packages
./ravpkg list

# View package info
./ravpkg info ravterm

# Specify a custom database path (useful for testing)
./ravpkg --db ./test.db list

# Stubs
./ravpkg install ./sample-package.rav
./ravpkg remove sample-package
./ravpkg search editor
```

---

## Specification Reference

See [`docs/manifest-spec.md`](docs/manifest-spec.md) for the full JSON schema and field constraints.
