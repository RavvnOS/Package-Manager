<div align="center">

<img src="https://img.shields.io/badge/-ravpkg-0A84FF?style=for-the-badge&logo=gnubash&logoColor=white" height="60" alt="ravpkg"/>

### The package manager for ravynOS

*A macOS-compatible, open-source operating system built on a Darwin/FreeBSD userland*

<br/>

![Shell](https://img.shields.io/badge/language-Bash%204%2B-4EAA25?logo=gnu-bash&logoColor=white)
![Status](https://img.shields.io/badge/status-Phase%201--3%20complete-brightgreen)
![Tests](https://img.shields.io/badge/tests-62%2B%20passing-success)
![Dependencies](https://img.shields.io/badge/runtime%20deps-sqlite3%20%7C%20jq-blue)
![License](https://img.shields.io/badge/license-MIT-lightgrey)
![PRs](https://img.shields.io/badge/PRs-welcome-orange)

<br/>

**[Quick Start](#-quick-start)** &nbsp;•&nbsp;
**[Features](#-features)** &nbsp;•&nbsp;
**[Why ravpkg](#-why-ravpkg)** &nbsp;•&nbsp;
**[Architecture](#-architecture)** &nbsp;•&nbsp;
**[Documentation](#-documentation)** &nbsp;•&nbsp;
**[Roadmap](#-roadmap)**

</div>

<br/>

---

##  Table of Contents

- [Overview](#overview)
- [Why ravpkg](#-why-ravpkg)
- [Features](#-features)
- [Status](#-status)
- [Quick Start](#-quick-start)
- [Usage](#-usage)
- [Architecture](#-architecture)
- [ravpkg vs. dnf / yum](#-ravpkg-vs-dnf--yum)
- [Documentation](#-documentation)
- [Testing](#-testing)
- [Security](#-security)
- [Roadmap](#-roadmap)
- [Contributing](#-contributing)
- [License](#-license)

---

## Overview

`ravpkg` handles package installation, removal, dependency resolution, and
repository search for **ravynOS** — implemented entirely in pure Bash, with
no compiler or language runtime dependency beyond a handful of standard
Unix tools (`bash`, `sqlite3`, `jq`).

It draws architectural inspiration from `dnf`/`yum` and FreeBSD's `pkg`
while staying lightweight, dependency-free, and fully transparent: every
operation is plain shell script backed by SQLite and JSON — auditable
line-by-line by anyone, with no hidden binary state.

<br/>

##  Why ravpkg

| | |
|---|---|
| **Transparent by design** | No compiled binary, no opaque state — every install, removal, and resolution step is a readable shell function |
| **Zero build step** | Clone it, `chmod +x`, run it. No compiler, no toolchain, no language runtime |
| **Built for ravynOS's model** | Designed around App Bundle–style installs on a Darwin/FreeBSD userland, not a 1:1 port of a Linux-centric tool |
| **Defense-in-depth integrity** | Checksums verified independently at download, index, and manifest level — never trusts a single source |
| **Fails safe** | Every install is staged and fully rolled back on any failure — the filesystem is never left half-changed |

<br/>

##  Features

<table>
<tr>
<td width="33%" valign="top">

** Installation**
- Local archive or by-name repo install
- Staged extraction
- Full transactional rollback

</td>
<td width="33%" valign="top">

** Dependencies**
- Semver constraint matching
- Circular dependency detection
- Conflicts & virtual packages (`provides`)

</td>
<td width="33%" valign="top">

** Integrity**
- SHA-256 checksums, layered
- Optional GPG signature verification
- `--require-signature` enforcement mode

</td>
</tr>
<tr>
<td width="33%" valign="top">

** Repository**
- Case-insensitive search
- Index caching
- `--no-cache` for fresh fetch

</td>
<td width="33%" valign="top">

** Removal**
- Reverse-dependency warnings
- Safe, tolerant file cleanup
- Empty-directory pruning

</td>
<td width="33%" valign="top">

** Quality**
- 62+ passing Bats tests
- Benchmarked performance
- No silent failures (`set -euo pipefail`)

</td>
</tr>
</table>

<br/>

##  Status

**Phase 1–3 complete.**

| Command | Status | Description |
|---|:---:|---|
| `ravpkg list` | ✅ | List all installed packages |
| `ravpkg info <pkg>` | ✅ | Show metadata and installed files |
| `ravpkg install <file>` | ✅ | Install from a local `.rav` archive |
| `ravpkg install <name>` | ✅ | Resolve and install by name from a repository |
| `ravpkg remove <pkg>` | ✅ | Remove an installed package |
| `ravpkg search <query>` | ✅ | Search the repository index |

>  **In progress:** automatic recursive dependency fetching with full
> transaction planning (design finalized, implementation pending).
>
>  **Deferred:** full SAT-style alternative dependencies (`A | B`),
> launchd/daemon integration — see [Roadmap](#-roadmap).

<br/>

##  Quick Start

```bash
# Clone
git clone https://github.com/<org>/Package-Manager.git ravpkg && cd ravpkg

# Install
./install.sh

# Verify
ravpkg --help
```

**Prerequisites**

| Tool | Required | Purpose |
|---|:---:|---|
| `bash` (v4+) | ✅ | Runtime |
| `sqlite3` | ✅ | Local package database |
| `jq` | ✅ | Manifest & index parsing |
| `curl` / `wget` | for remote installs | Package download |
| `gpg` | optional | Signature verification |

<br/>

##  Usage

```bash
# List installed packages
ravpkg list

# Inspect a package
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
<br/>

| Flag | Description |
|---|---|
| `--db <path>` / `-d <path>` | Use a custom database path |
| `--repo <url>` | Specify the repository index source |
| `--no-cache` | Force a fresh repository index fetch |
| `--skip-verify` | Bypass checksum verification (testing only — prints a loud warning) |
| `--require-signature` | Require a valid GPG signature to install |
| `--yes` / `-y` | Skip confirmation prompts |

</details>

Database path resolution order: `--db` flag → `$RAVPKG_DB` env variable →
`/var/db/ravpkg/pkg.db` → `./ravpkg.db`.

<br/>

## 🏗️ Architecture

```
ravpkg/
├── bin/ravpkg               CLI entrypoint & command dispatch
├── lib/
│   ├── db.sh                 SQLite CRUD (parameter-bound queries)
│   ├── parser.sh               Manifest parsing & schema validation
│   ├── install.sh               Staged extraction, checksum checks, rollback
│   ├── remove.sh                 Safe removal, dependent warnings
│   ├── deps.sh                    Dependency resolution & cycle detection
│   └── repo.sh                     Repository index fetch, cache, search
├── repo/generate-index.sh      Builds a repository index from manifests
├── schema/schema.sql             SQLite table definitions
├── docs/                           Specifications and reports
└── tests/                           Bats test suite + benchmarks
```

**Design principles**

- **Transparency over speed** — plain shell and SQLite text queries, easy
  to read and audit, at the cost of process-spawn overhead versus a
  compiled implementation
- **Fail safe, not silent** — `set -euo pipefail` throughout; every install
  is staged and rolled back on any failure before touching the real
  filesystem
- **Defense in depth** — checksum verification is layered independently at
  the download, index, and manifest level

<br/>

## ⚖️ ravpkg vs. dnf / yum

| | ravpkg | dnf / yum |
|---|---|---|
| **Language** | Bash | Python / C (libdnf) |
| **Local DB** | SQLite (via CLI) | rpmdb (Berkeley DB / SQLite / ndb) |
| **Package format** | JSON manifest + archive | Binary RPM header |
| **Dependency solver** | Constraint matching + cycle detection | Full SAT solver (libsolv) |
| **Startup overhead** | Low — no interpreter | Higher — Python/libdnf init |
| **Maturity** | New, actively developed | Decades of production use |

Full breakdown in [`docs/comparison.md`](docs/comparison.md).

<br/>

##  Documentation

| Document | Description |
|---|---|
| [`docs/manifest-spec.md`](docs/manifest-spec.md) | Package manifest JSON schema |
| [`docs/repo-index-spec.md`](docs/repo-index-spec.md) | Repository index schema |
| [`docs/comparison.md`](docs/comparison.md) | Architectural comparison against `dnf`/`yum` |
| [`docs/benchmarks.md`](docs/benchmarks.md) | Measured performance results and methodology |

<br/>

##  Testing

```bash
bats tests/              # full suite, if bats is installed
./tests/run_tests.sh     # standalone fallback runner
./tests/benchmark.sh     # performance benchmarks
```

Coverage includes manifest validation, database CRUD, transactional
install/remove with rollback, repository search and caching, dependency
resolution (chains, diamonds, cycles), and checksum/signature verification.

<br/>

##  Security

- Parameter-bound SQLite queries prevent injection from manifest field values
- Checksums verified **before** any payload is extracted to disk
- Optional GPG signature verification for an additional trust layer
- Every install is staged and fully rolled back on failure — no partial installs

<br/>

##  Roadmap

- [ ] Automatic recursive dependency fetching with full transaction planning
- [ ] Full SAT-style alternative dependencies (`A | B`)
- [ ] launchd/daemon integration *(blocked — ravynOS's launchd port is unfinished upstream)*

<br/>

##  Contributing

Issues and pull requests are welcome. Please ensure `make test` passes
before submitting a PR.

## 📄 License

MIT

<br/>

<div align="center">

Built for **ravynOS** 🐦‍⬛

</div>
