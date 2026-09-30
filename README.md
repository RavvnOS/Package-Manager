# ravpkg

`ravpkg` is a minimal-viable package manager designed for **ravynOS**, a
macOS-compatible open-source operating system built on a Darwin/FreeBSD
userland.

This repository contains the **Phase 1–2 scaffolding**, implemented in pure
Bash: package manifest schema, local SQLite database tracking, a manifest
parser/validator, and CLI command routing.

---

## Status

- **Phase:** 1–3 complete (design, core engine, transactional install/remove engine, repo index search, dependency resolution & cycle detection, CLI)
- **Language:** Bash (uses `sqlite3` and `jq` as external tools — no compiled
  binary or language runtime required)
- **Functional commands:** `list`, `info`, `install`, `remove`, `search`, `update`
- **Stub commands:** none
- **Not yet implemented:** remote repository hosting/publishing (Phase 4),
  daemon/launchd service integration, GPG package signing

---

## Command Status

| Command                 | Status         | Description                                                                  | Phase   |
| ------------------------ | -------------- | ---------------------------------------------------------------------------- | ------- |
| `ravpkg list`            | **Functional** | Queries and lists all installed packages from the local SQLite DB.             | Phase 1 |
| `ravpkg info <pkg>`      | **Functional** | Displays metadata and installed file paths for a package.                      | Phase 1 |
| `ravpkg install <file>`  | **Functional** | Resolves dependencies, checks cycles, verifies checksum, transactional install. | Phase 2–3 |
| `ravpkg remove <pkg>`    | **Functional** | Warns on reverse dependents, deletes tracked files, prunes empty directories.  | Phase 2–3 |
| `ravpkg search <query>`  | **Functional** | Case-insensitive substring query against cached repository index.             | Phase 2 |
| `ravpkg update`          | **Functional** | Fetches and caches repository index from local mirror or remote URL.         | Phase 2 |

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
│   ├── remove.sh               # Filesystem package removal and pruning engine
│   ├── repo.sh                 # Repository index caching and package search engine
│   └── deps.sh                 # Semver evaluation, dependency resolution, and cycle detection
├── repo/
│   └── generate-index.sh       # Tool to scan manifests and produce repository index JSON
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
│   ├── test_search.bats         # bats tests for repository indexing & search
│   ├── test_deps.bats           # bats tests for dependency checks and cycle detection
│   └── run_tests.sh             # Standalone test runner (works with or without bats)
├── docs/
│   ├── manifest-spec.md         # Formal specification for package manifest schema
│   ├── repo-index-spec.md       # Formal specification for repository index schema
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

# Install a package from local archive or remote repository by name
./bin/ravpkg install ./sample-package.rav
./bin/ravpkg install ravterm                               # looks up in repo index, downloads, and installs
./bin/ravpkg install ravterm -y                            # non-interactive: confirm transaction plan automatically
./bin/ravpkg install ravterm --no-cache                    # force fresh index fetch
./bin/ravpkg install ./sample-package.rav --root /opt/sandbox
./bin/ravpkg install ./sample-package.rav --skip-verify    # development/testing only
./bin/ravpkg install ./sample-package.rav --no-deps        # bypass dependency checks

When installing a package with missing dependencies from the repository, `ravpkg`
automatically resolves sub-dependencies recursively, displays a Transaction Summary
table, and prompts for confirmation. If any package fails mid-transaction, a full
transaction rollback uninstalls any dependencies installed during that transaction in
reverse order, restoring the system to its pre-transaction state.

# Remove an installed package
./bin/ravpkg remove sample-package
./bin/ravpkg remove sample-package --root /opt/sandbox

# Update repository index (from remote URL or local mirror)
./bin/ravpkg update
./bin/ravpkg update --repo /path/to/index.json

# Search repository packages (case-insensitive across name and description)
./bin/ravpkg search editor
./bin/ravpkg search --repo /path/to/index.json term

# Generate repository index from directory of manifests
repo/generate-index.sh -o index.json /path/to/manifests
```

Database path resolution order: `--db <path>` / `-d <path>` flag →
`$RAVPKG_DB` environment variable → `/var/db/ravpkg/pkg.db` → `./ravpkg.db`.

---

## Specification Reference

See [`docs/manifest-spec.md`](docs/manifest-spec.md) for the full JSON
schema and field constraints. This schema is unchanged from the original
implementation.

---

