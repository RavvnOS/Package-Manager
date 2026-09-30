# ravpkg

`ravpkg` is a minimal-viable package manager designed for **ravynOS** (a macOS-compatible open-source operating system built on Darwin/FreeBSD userland).

This repository contains the **Phase 1–2 scaffolding** implemented in pure **Bash**, utilizing `sqlite3` for local database package tracking and `jq` for manifest parsing and validation.

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
├── bin/
│   └── ravpkg                  # Main executable script, argument parser & command routing
├── lib/
│   ├── db.sh                   # sqlite3 wrapper functions (installed_packages table)
│   └── parser.sh               # jq-based manifest JSON parser and validator
├── schema/
│   └── schema.sql              # SQLite table definitions (installed_packages)
├── tests/
│   ├── fixtures/
│   │   ├── valid-manifest.json          # Example valid package manifest
│   │   ├── with-deps-manifest.json      # Manifest with dependencies & multiple paths
│   │   ├── missing-fields-manifest.json # Invalid manifest (missing required fields)
│   │   └── bad-checksum-manifest.json   # Invalid manifest (malformed SHA256)
│   ├── test_parser.bats        # bats tests for parser & validation rules
│   ├── test_db.bats            # bats tests for SQLite CRUD operations
│   └── run_tests.sh            # Standalone test runner (bats or native bash fallback)
├── docs/
│   └── manifest-spec.md        # Formal specification for package manifest schema
├── .gitignore                  # Git ignore rules for SQLite databases, temporary files
├── install.sh                  # Installation script (copies ravpkg to /usr/local/bin)
├── Makefile                    # Targets for test, install, clean
└── README.md                   # Project documentation
```

---

## Prerequisites

- **Bash** (v4.0 or newer)
- **sqlite3**
- **jq** (for JSON manifest parsing and validation)
- *(Optional)* **bats-core** (for running test suites)

---

## Installation & Setup

No compilation or build step is required.

### Quick Run
Make `bin/ravpkg` executable and run it directly:
```bash
chmod +x bin/ravpkg
./bin/ravpkg --help
```

### System Installation
Run the install script to copy `ravpkg` to `/usr/local/bin` and libraries to `/usr/local/lib/ravpkg`:
```bash
sudo ./install.sh
# or using Make
sudo make install
```

---

## Running Tests

Run the test suite via the test runner:
```bash
# Using Makefile
make test

# Or directly with bash
bash tests/run_tests.sh

# Or using bats directly (if installed)
bats tests/test_*.bats
```

---

## Usage Examples

```bash
# Show command help
./bin/ravpkg --help

# List installed packages
./bin/ravpkg list

# View package info
./bin/ravpkg info ravterm

# Specify a custom database path (useful for testing)
./bin/ravpkg --db ./test.db list

# Stubs
./bin/ravpkg install ./sample-package.rav
./bin/ravpkg remove sample-package
./bin/ravpkg search editor
```

---

## Specification Reference

See [`docs/manifest-spec.md`](docs/manifest-spec.md) for the full JSON schema and field constraints.
