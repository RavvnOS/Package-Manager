# Comparative Analysis: ravpkg vs. DNF and YUM

This document provides an architectural and operational comparison between **ravpkg** (the minimal package manager for ravynOS) and the established RPM-based package managers **DNF** and **YUM** (used across Fedora, RHEL, CentOS, Rocky Linux, and AlmaLinux).

---

## 1. Overview Table

The table below contrasts the package managers across core functional dimensions. **ravpkg** is assessed strictly according to its current Phase 1–2 scaffolding implementation.

| Dimension | YUM (Legacy) | DNF (Current Standard) | ravpkg (Phase 1–2 Scaffolding) |
| :--- | :--- | :--- | :--- |
| **Package Format** | RPM (`.rpm`): cpio payload with lead, signature header, and tags | RPM (`.rpm`): cpio payload with rich metadata and weak dependencies | Archive payload (`.rav` / `.tar.zst`) with JSON manifest (`manifest.json`) |
| **Dependency Resolution** | Heuristic, greedy iterative solver (Python-based; slow on large graphs) | Boolean Satisfiability (SAT) solver via `libsolv` (C-based; deterministic and fast) | **Not yet implemented** (Schema-only declarations in `manifest.json`; resolution planned for Phase 3) |
| **Repo Format & Transport** | `repomd.xml` metadata index (XML / SQLite cache) over HTTP/HTTPS/FTP | `repomd.xml` with zchunk compression, metalink/mirrorlists over HTTP/HTTPS | **Not yet implemented / Stub** (Repository index and remote search planned for Phase 4) |
| **Local Package Database** | Berkeley DB / SQLite (`/var/lib/rpm`, `/var/cache/yum`) | SQLite rpmdb (`/var/lib/rpm`) + transaction history (`/var/lib/dnf/history.sqlite`) | SQLite schema (`schema/schema.sql`, table `installed_packages`) via `lib/db.sh` |
| **Transaction / Rollback** | Basic transaction history (`yum history undo/rollback`) | Full transaction journaling and rollbacks (`dnf history undo/rollback`) | **Not yet implemented** (No transaction journals or rollback mechanisms) |
| **Signing & Verification** | GPG signatures on RPM headers and `repomd.xml.asc` | GPG signatures on RPM packages and repository metadata | Payload SHA-256 checksum format verification only; GPG/cryptographic signing **Not yet implemented** |
| **Language / Runtime** | Python 2 / Python 3 with C extensions (`rpm-python`) | C / C++ (`libdnf`, `libsolv`) with Python CLI (or pure C++ in DNF5) | Pure Bash (`bash` 4.0+) utilizing standard `sqlite3` and `jq` CLI utilities |
| **Target OS / Platform** | Linux (RHEL, CentOS, Fedora) | Linux (Fedora, RHEL 8+, CentOS Stream) | **ravynOS** (Darwin / FreeBSD userland with macOS compatibility) |
| **Maturity & Ecosystem** | Legacy / Retired (>20 years old, battle-tested) | Production Standard (>10 years old, millions of systems) | **Early Prototype** (Phase 1–2 scaffolding; `list` and `info` functional, others stubbed) |

---

## 2. Architecture Comparison

### Dependency Resolution
- **YUM**: Relied on a custom Python-based dependency resolution engine. It inspected package requires/provides tags iteratively. While functional for straightforward dependency graphs, it suffered from combinatorial slowdowns, high memory utilization, and occasional failure to find valid solutions when handling complex multi-repository dependency rings.
- **DNF**: Addressed YUM's core resolver bottlenecks by adopting **`libsolv`**, an external Boolean Satisfiability (SAT) solver library originally developed by openSUSE. `libsolv` translates dependencies into a propositional formula and uses SAT algorithms to determine satisfiability deterministically and rapidly, while generating clear conflict explanations.
- **ravpkg**: Currently has **no dependency resolution logic implemented**. In Phase 1–2, dependency handling is strictly limited to schema validation: the manifest parser ensures that the `dependencies` array conforms to the schema (`name` and optional version `constraint`). Resolving dependencies against a package repository graph is planned for Phase 3.

---

## 3. What ravpkg Does Differently by Design

A 1:1 comparison with RPM-based package managers does not capture `ravpkg`'s deliberate architectural deviations. `ravpkg` is purpose-built for ravynOS rather than generic Linux distributions:

1. **macOS-Style Application Bundle First-Class Support**:
   Linux package managers assume the standard Linux Filesystem Hierarchy Standard (FHS), distributing application assets across `/usr/bin`, `/usr/lib64`, `/usr/share/applications`, and `/usr/share/icons`. ravynOS targets macOS desktop compatibility where graphical applications are packaged as self-contained bundles (`/Applications/AppName.app`). `ravpkg`'s `install_paths` mapping abstraction allows bundle directories and individual command-line tools to be mapped directly to appropriate target paths without complex RPM post-install script hooks.

2. **Explicit Source-to-Destination Path Mappings**:
   Instead of baking predefined directory layouts into package generation macros, `ravpkg` manifests explicitly declare file mappings via `install_paths`:
   ```json
   "install_paths": [
     { "source": "Applications/RavFetch.app", "destination": "/Applications/RavFetch.app" },
     { "source": "bin/ravfetch", "destination": "/usr/local/bin/ravfetch" }
   ]
   ```
   This gives packagers clean control when bridging FreeBSD system tools, Darwin Mach-O frameworks, and Cocoa-style application bundles.

3. **Ultra-Lightweight Base System Footprint**:
   DNF and YUM bring heavy dependency chains—Python runtimes, large shared libraries (`libdnf`, `libsolv`, `librepo`), and complex RPM databases. In contrast, `ravpkg` executes directly as a Bash script leveraging `sqlite3` and `jq`, requiring zero compiled runtimes or heavy interpreters in the initial bootstrap environment.

---

## 4. What ravpkg Is Missing (Honest Gap List)

Compared to production package managers like DNF and YUM, `ravpkg` is in its foundational scaffolding stage. The following features are currently absent:

### Planned for Later Phases
- **Filesystem Installation & Extraction (Phase 2)**: Unpacking `.rav` / `.tar.zst` payload archives, copying files according to `install_paths`, and cleanly removing uninstalled files from the filesystem.
- **Dependency Resolution Engine (Phase 3)**: Directed acyclic graph (DAG) or SAT solver to calculate dependency trees, handle version constraint operators (`>=`, `^`, `~`), and prevent circular dependency locks.
- **Remote Repository Indexing & Synchronization (Phase 4)**: Remote metadata fetching, local caching, mirror handling, and remote search capabilities (`ravpkg search`).
- **Cryptographic Package Signing**: Verifying repository metadata and package integrity using public key cryptography (e.g., GPG, signify, or minisign) rather than only verifying the SHA-256 checksum format.
- **Daemon & launchd Integration**: Triggering system daemon reloads or launchd plist registration when services or background jobs are installed.

### Out of Scope (By Design or Unplanned)
- **Delta / Binary Diff Updates (`drpm`)**: Generating and applying binary diffs between package revisions.
- **Extensible Plugin Ecosystem**: DNF includes Python/C hook plugins (e.g., `dnf-plugins-core`, copr, download-only). `ravpkg` currently favors a single, self-contained shell core.
- **Multi-Architecture / Multilib Coexistence**: DNF allows concurrent installation of 32-bit and 64-bit libraries (`x86_64` and `i686`). `ravpkg` does not plan multilib support.
- **Module Streams & AppStreams**: DNF's modularity features allowing multiple concurrent runtime streams (e.g., nodejs:18 vs nodejs:20) are out of scope.

---

## 5. Why Not Just Use DNF/YUM Directly?

Porting DNF or YUM to ravynOS is fundamentally mismatched with the operating system's design goals. ravynOS is built on a FreeBSD kernel with a Darwin/Mach userland and Mach-O binary ecosystem, designed to look, feel, and behave like macOS. DNF and YUM are deeply coupled with the RPM ecosystem, Linux Filesystem Hierarchy Standards (FHS), ELF binary linkers, systemd/SysV services, and an extensive Python/C++ dependency tree. Forcing RPM onto ravynOS would introduce foreign Linux conventions, ignore macOS-style self-contained App Bundles (`.app`), require managing a secondary `rpmdb` alongside the native system userland, and conflict with ravynOS's goal of providing a clean, coherent Darwin-compatible operating environment.
