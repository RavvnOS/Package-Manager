<div align="center">

# ravpkg

**A minimal-viable package manager for ravynOS**


![Shell](https://img.shields.io/badge/language-Bash-4EAA25?logo=gnu-bash&logoColor=white)
![Status](https://img.shields.io/badge/status-Phase%201--3%20complete-brightgreen)
![License](https://img.shields.io/badge/license-MIT-blue)
![Tests](https://img.shields.io/badge/tests-passing-success)

[Overview](#overview) •
[Features](#features) •
[Installation](#installation) •
[Usage](#usage) •
[Architecture](#architecture) •
[Documentation](#documentation) •
[Roadmap](#roadmap)

</div>

---

## Overview

`ravpkg` handles package installation, removal, dependency resolution, and
repository search for ravynOS — implemented entirely in pure Bash, with no
compiler or language runtime dependency beyond a handful of standard Unix
tools.

It draws architectural inspiration from `dnf`/`yum` and `pkg` (FreeBSD)
while staying lightweight and fully transparent: every operation is plain
shell script backed by SQLite and JSON, making the entire system easy to
read, audit, and extend.

---

## Features

| | |
|---|---|
|  **Package Installation** | Install from a local archive or by name from a repository index, with staged extraction and full transactional rollback on failure |
|  **Integrity Verification** | SHA-256 checksum enforcement at every stage, plus optional GPG signature verification |
|  **Dependency Resolution** | Semver-style constraint matching, circular dependency detection, `conflicts`/`provides` (virtual package) support |
|  **Repository Search** | Case-insensitive search against a cached or remote package index |
|  **Clean Removal** | Reverse-dependency warnings, safe file cleanup, empty-directory pruning |
|  **Fully Tested** | Bats-based test suite covering parser, database, install/remove, search, and dependency resolution |
|  **Zero Runtime Dependencies** | No compiler, no language runtime — just Bash, SQLite, and jq |

---

## Status

**Phase 1–3 complete.**

| Command | Status | Description |
|---|---|---|
| `ravpkg list` | ✅ Functional | List all installed packages |
| `ravpkg info <pkg>` | ✅ Functional | Show metadata and installed files for a package |
| `ravpkg install <file>` | ✅ Functional | Install from a local `.rav` archive |
| `ravpkg install <name>` | ✅ Functional | Resolve and install by name from a repository index |
| `ravpkg remove <pkg>` | ✅ Functional | Remove an installed package |
| `ravpkg search <query>` | ✅ Functional | Search the repository index |

**In progress:** automatic recursive dependency fetching with full
transaction planning (design finalized, implementation pending).

**Out of scope (for now):** full SAT-style alternative dependencies
(`A | B`), launchd/daemon integration — see [Roadmap](#roadmap) for details.

---

## Installation

### Prerequisites

| Tool | Required | Purpose |
|---|---|---|
| `bash` (v4+) | Yes | Runtime |
| `sqlite3` | Yes | Local package database |
| `jq` | Yes | Manifest and index parsing |
| `curl` or `wget` | For remote installs | Package download |
| `gpg` | Optional | Signature verification |

### Install

```bash
git clone https://github.com/<org>/Package-Manager.git ravpkg
cd ravpkg
./install.sh
```

Or using Make:

```bash
make install
```

This installs `ravpkg` to `${PREFIX:-/usr/local}/bin` and supporting
libraries to `${PREFIX:-/usr/local}/lib/ravpkg`.

---

## Usage

```bash
# List installed packages
ravpkg list

# View package details
ravpkg info ravterm

# Install from a local archive
ravpkg install ./webapp-2.0.0.rav

# Install by name from a configured repository
ravpkg install webapp --repo ./index.json

# Search available packages
ravpkg search editor

# Remove a package
ravpkg remove webapp
```

<details>
<summary><strong>Full flag reference</strong></summary>

| Flag | Description |
|---|---|
| `--db <path>` / `-d <path>` | Use a custom database path |
| `--repo <url>` | Specify the repository index source |
| `--no-cache` | Force a fresh repository index fetch |
| `--skip-verify` | Bypass checksum verification (testing only — prints a loud warning) |
| `--require-signature` | Require a valid GPG signature to install |
| `--yes` / `-y` | Skip confirmation prompts |

</details>

Database path resolution order: `--db` flag → `$RAVPKG_DB` environment
variable → `/var/db/ravpkg/pkg.db` → `./ravpkg.db`.

---

## Architecture

```
ravpkg/
├── bin/ravpkg            # CLI entrypoint & command dispatch
├── lib/
│   ├── db.sh              # SQLite CRUD (parameter-bound queries)
│   ├── parser.sh           # Manifest parsing & schema validation
│   ├── install.sh          # Staged extraction, checksum checks, rollback
│   ├── remove.sh           # Safe removal, dependent warnings
│   ├── deps.sh              # Dependency resolution & cycle detection
│   └── repo.sh              # Repository index fetch, cache, search
├── repo/generate-index.sh  # Builds a repository index from manifests
├── schema/schema.sql         # SQLite table definitions
├── docs/                     # Specifications and reports
└── tests/                    # Bats test suite + benchmarks
```

**Design principles:**
- **Transparency over speed** — plain shell and SQLite text queries, easy
  to read and audit, at the cost of process-spawn overhead versus a
  compiled implementation
- **Fail safe, not silent** — `set -euo pipefail` throughout; every install
  is staged and rolled back on any failure before touching the real
  filesystem
- **Defense in depth** — checksum verification is layered independently at
  the download, index, and manifest level, and never trusts a single source

---

## Documentation

| Document | Description |
|---|---|
| [`docs/manifest-spec.md`](docs/manifest-spec.md) | Package manifest JSON schema |
| [`docs/repo-index-spec.md`](docs/repo-index-spec.md) | Repository index schema |
| [`docs/comparison.md`](docs/comparison.md) | Architectural comparison against `dnf`/`yum` |
| [`docs/benchmarks.md`](docs/benchmarks.md) | Measured performance results and methodology |

---

## Testing

```bash
# With bats installed
bats tests/

# Without bats
./tests/run_tests.sh

# Run benchmarks
./tests/benchmark.sh
```

Test coverage includes manifest validation, database CRUD, transactional
install/remove with rollback, repository search and caching, dependency
resolution (chains, diamonds, cycles), and checksum/signature verification.

---

## Roadmap

- [ ] Automatic recursive dependency fetching with full transaction planning
- [ ] Full SAT-style alternative dependencies (`A | B`)
- [ ] launchd/daemon integration *(blocked — ravynOS's own launchd port is unfinished upstream)*

---

## Security

- Parameter-bound SQLite queries prevent injection from manifest field values
- Checksum verification occurs before any payload is extracted to disk
- Optional GPG signature verification for an additional trust layer
- All installs are staged and fully rolled back on failure — no partial installs

---

## Contributing

Issues and pull requests are welcome. Please ensure `make test` passes
before submitting a PR.

## License

MIT
