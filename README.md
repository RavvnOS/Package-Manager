# ravpkg

`ravpkg` is a minimal-viable package manager designed for **ravynOS**, a
macOS-compatible open-source operating system built on a Darwin/FreeBSD
userland.

This repository contains the **Phase 1–2 scaffolding**, implemented in pure
Bash: package manifest schema, local SQLite database tracking, a manifest
parser/validator, and CLI command routing.

---

## Status

- **Phase:** 1–2 complete (design, core engine, transactional install/remove engine, CLI)
- **Language:** Bash (uses `sqlite3` and `jq` as external tools — no compiled
  binary or language runtime required)
- **Functional commands:** `list`, `info`, `install`, `remove`
- **Stub commands:** `search` (deferred to Phase 4 repo tooling)
- **Not yet implemented:** dependency resolution (Phase 3), remote repository
  tooling (Phase 4), daemon/launchd integration, GPG signing

---

## Command Status

| Command                 | Status         | Description                                                                  | Phase   |
| ------------------------ | -------------- | ---------------------------------------------------------------------------- | ------- |
| `ravpkg list`            | **Functional** | Queries and lists all installed packages from the local SQLite DB.             | Phase 1 |
| `ravpkg info <pkg>`      | **Functional** | Displays metadata and installed file paths for a package.                      | Phase 1 |
| `ravpkg install <file>`  | **Functional** | Validates checksum, stages unpack, copies files, with transactional rollback. | Phase 2 |
| `ravpkg remove <pkg>`    | **Functional** | Deletes tracked files and manifest, prunes directories, cleans DB record.     | Phase 2 |
| `ravpkg search <query>`  | Stub           | Remote repository index query.                                               | Phase 4 |

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
│   ├── parser.sh               # jq-based manifest parsing & schema validation functions
│   ├── install.sh              # Filesystem installation engine with transactional rollback
│   └── remove.sh               # Filesystem package removal and pruning engine
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
│   ├── test_install_remove.bats # bats tests for install, rollback, and remove
│   └── run_tests.sh             # Standalone test runner (works with or without bats)
├── docs/
│   ├── manifest-spec.md         # Formal specification for package manifest schema
│   ├── comparison.md            # Architectural comparison against dnf and yum
│   └── benchmarks.md            # Benchmark measurements and methodology
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

# Install a package archive (with optional --root sandbox)
./bin/ravpkg install ./sample-package.rav
./bin/ravpkg install ./sample-package.rav --root /opt/sandbox

# Remove an installed package
./bin/ravpkg remove sample-package
./bin/ravpkg remove sample-package --root /opt/sandbox

# Search repository (Phase 4 stub)
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

