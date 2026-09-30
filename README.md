# ravpkg

`ravpkg` is a minimal-viable package manager designed for **ravynOS**, a
macOS-compatible open-source operating system built on a Darwin/FreeBSD
userland.

This repository contains the **Phase 1–2 scaffolding**, implemented in pure
Bash: package manifest schema, local SQLite database tracking, a manifest
parser/validator, and CLI command routing.

---

## Status

- **Phase:** 1–2 complete (design, core engine, CLI skeleton)
- **Language:** Bash (uses `sqlite3` and `jq` as external tools — no compiled
  binary or language runtime required)
- **Functional commands:** `list`, `info`
- **Stub commands:** `install`, `remove`, `search` (deferred to later phases)
- **Not yet implemented:** dependency resolution, filesystem install/remove
  logic, remote repository tooling, daemon/launchd integration, signing

---

## Command Status

| Command                 | Status         | Description                                                        | Phase   |
| ------------------------ | -------------- | -------------------------------------------------------------------- | ------- |
| `ravpkg list`            | **Functional** | Queries and lists all installed packages from the local SQLite DB.   | Phase 1 |
| `ravpkg info <pkg>`      | **Functional** | Displays metadata and installed file paths for a package.            | Phase 1 |
| `ravpkg install <file>`  | Stub           | Unpack and filesystem install logic.                                 | Phase 2 |
| `ravpkg remove <pkg>`    | Stub           | Filesystem file removal logic.                                       | Phase 2 |
| `ravpkg search <query>`  | Stub           | Remote repository index query.                                       | Phase 4 |

> Dependency resolution and launchd/daemon service integration are deferred
> to subsequent phases.

---

## Project Structure

```
ravpkg/
├── bin/
│   └── ravpkg                  # Main executable script; argument parsing & subcommand dispatch
├── lib/
│   ├── db.sh                   # sqlite3 wrapper functions (init, add, remove, get, list)
│   └── parser.sh               # jq-based manifest parsing & schema validation functions
├── schema/
│   └── schema.sql               # SQLite table definitions (installed_packages)
├── tests/
│   ├── fixtures/                # JSON manifest fixtures
│   │   ├── valid-manifest.json
│   │   ├── with-deps-manifest.json
│   │   ├── missing-fields-manifest.json
│   │   └── bad-checksum-manifest.json
│   ├── test_parser.bats         # bats tests for parser & validation rules
│   ├── test_db.bats             # bats tests for SQLite CRUD operations
│   └── run_tests.sh             # Standalone test runner (works with or without bats)
├── docs/
│   └── manifest-spec.md         # Formal specification for package manifest schema
├── install.sh                   # Installer script; checks sqlite3/jq, installs to /usr/local/bin
├── Makefile                     # Targets: test, install, clean
└── README.md                    # Project documentation
```

---

## Requirements

- **bash** v4+
- **sqlite3** (CLI)
- **jq**

No compiler or language runtime is required — `ravpkg` is a plain shell
script plus supporting library files.

---

## Build & Test Instructions

### Installing

```bash
./install.sh
# or
make install
```

This checks for `sqlite3` and `jq` on `PATH`, then installs `bin/ravpkg` to
`${PREFIX:-/usr/local}/bin` and the library files to
`${PREFIX:-/usr/local}/lib/ravpkg`.

### Running Unit Tests

```bash
# With bats installed
bats tests/

# Without bats
./tests/run_tests.sh

# Using Makefile
make test
```

---

## Usage Examples

```bash
./bin/ravpkg --help

# List installed packages
./bin/ravpkg list --db ./test.db

# View package info
./bin/ravpkg info ravterm --db ./test.db

# Stubs (not yet implemented)
./bin/ravpkg install ./sample-package.rav
./bin/ravpkg remove sample-package
./bin/ravpkg search editor
```

Database path resolution order: `--db <path>` / `-d <path>` flag →
`$RAVPKG_DB` environment variable → `/var/db/ravpkg/pkg.db` → `./ravpkg.db`.

---

## Specification Reference

See [`docs/manifest-spec.md`](docs/manifest-spec.md) for the full JSON
schema and field constraints. This schema is unchanged from the original
implementation.

---

