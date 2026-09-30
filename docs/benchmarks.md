# ravpkg Performance Benchmarks (Phase 1–2)

**Document Version:** 1.0.0  
**Target System:** ravynOS (Darwin/FreeBSD userland)  
**Implementation:** Pure Bash + SQLite 3 + jq  
**Test Suite:** `tests/benchmark.sh`

---

## 1. Test Environment & Verification Notice

> [!IMPORTANT]
> **Environment Note:**  
> The benchmarks below were measured on **2026-09-30**, using **Bash 5.2.37**, **SQLite 3.53.4**, and **jq 1.8.2** on a Windows/MSYS2 development machine.  
> These numbers reflect real measured data under the local development environment and are **not representative of native ravynOS hardware**. On native POSIX operating systems (FreeBSD/Darwin), process fork/exec overhead is substantially lower than under Windows emulation layers.

All figures below are direct measurements from running `tests/benchmark.sh` across 10 iterations per benchmark scenario.

---

## 2. Measured Benchmark Results

| Benchmark Operation | Scale / Dataset | Min | Max | Mean | Median |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Manifest parse** | Single valid manifest (`valid-manifest.json`) | 186.14 ms | 224.39 ms | 203.82 ms | 204.25 ms |
| **Manifest parse** | Batch validation (100 synthetic manifests) | 18,677.20 ms | 25,922.04 ms | 22,880.16 ms | 23,296.78 ms |
| **`ravpkg info <pkg>`** | 10 packages in SQLite DB | 647.08 ms | 903.93 ms | 732.17 ms | 700.38 ms |
| **`ravpkg info <pkg>`** | 100 packages in SQLite DB | 677.63 ms | 970.35 ms | 797.58 ms | 778.39 ms |
| **`ravpkg info <pkg>`** | 1,000 packages in SQLite DB | 737.57 ms | 1,114.79 ms | 906.12 ms | 895.73 ms |
| **`ravpkg info <pkg>`** | 10,000 packages in SQLite DB | 651.06 ms | 850.63 ms | 722.08 ms | 707.17 ms |
| **`ravpkg list`** | 10 packages in SQLite DB | 308.28 ms | 364.65 ms | 336.33 ms | 330.82 ms |
| **`ravpkg list`** | 100 packages in SQLite DB | 339.27 ms | 438.45 ms | 388.22 ms | 389.54 ms |
| **`ravpkg list`** | 1,000 packages in SQLite DB | 502.82 ms | 661.82 ms | 574.05 ms | 568.10 ms |
| **`ravpkg list`** | 10,000 packages in SQLite DB | 1,890.34 ms | 2,456.03 ms | 2,144.52 ms | 2,130.66 ms |

### Architectural Observations from Measured Data
1. **O(log N) Indexed Lookup for `info`**:
   The execution time for `ravpkg info` remains virtually flat (~700–900 ms) regardless of whether the database contains 10 packages or 10,000 packages. Because `name` is the primary key in SQLite, the query cost is negligible; the observed latency is almost entirely consumed by script initialization, Bash process forks, and `jq` text processing.
2. **Linear Growth for `list`**:
   `ravpkg list` scales linearly with the size of the database. At 10 rows, execution takes ~330 ms; at 1,000 rows, it takes ~570 ms; at 10,000 rows, it takes ~2.1 seconds. The bottleneck is the tabular line formatting and subshell pipe processing in shell script rather than SQLite query execution.
3. **External Validator Overhead in Batch Parsing**:
   Validating 100 manifests individually takes ~22.8 seconds (~228 ms per file). Because `lib/parser.sh` spawns `jq` to validate each file, process invocation overhead dominates.

---

## 3. Implemented vs. DNF/YUM Comparison

This comparison analyzes the architecture and operational profile of the operations currently implemented in `ravpkg` against equivalent commands in DNF and YUM.

### A. Package Query / Listing (`ravpkg list` vs. `dnf list installed`)
- **DNF**:
  `dnf list installed` queries the local RPM database (`rpmdb`, historically Berkeley DB, modern Fedora/RHEL uses SQLite/ndb in `/var/lib/rpm`). DNF must initialize the Python interpreter (in DNF 4) or `libdnf` runtime, inspect local repository caches, and deserialize binary RPM header records. For systems with 2,000–3,000 installed packages, DNF typically experiences an initial startup latency (often 1–2 seconds) attributable to library loading and cache checks, but subsequent record scans are fast native C operations.
- **ravpkg**:
  `ravpkg list` executes a single SQL query (`SELECT ... FROM installed_packages ORDER BY name ASC`) via `sqlite3 -json` and streams the records through `jq` and `printf`. There are no external repository metadata checks or heavy interpreter start-up penalties, making small-to-medium listings lightweight, though shell text formatting becomes the rate-limiting factor at very large scale (10,000+ packages).

### B. Single Package Metadata Query (`ravpkg info <pkg>` vs. `dnf info <pkg>`)
- **DNF**:
  `dnf info <pkg>` searches the local `rpmdb` indices. If remote repos are configured and cache metadata is stale, DNF may attempt network checks or repository metadata cache synchronization before displaying package info, introducing variable network-dependent latency unless `--cacheonly` is passed.
- **ravpkg**:
  `ravpkg info` operates exclusively on the local SQLite database via indexed B-tree lookup on `name TEXT PRIMARY KEY`. It executes deterministically in constant time relative to database size.

### C. Package Header / Manifest Parsing (JSON Manifest vs. RPM Lead/Header)
- **DNF / RPM**:
  RPM packages store metadata in a compact binary header structure (contiguous tag-value arrays). Parsing an RPM header involves reading a fixed-size header struct and indexing tag offsets directly in memory using native C (`rpmReadPackageHeader`). This requires virtually no text parsing and executes in sub-millisecond time.
- **ravpkg**:
  `ravpkg` uses JSON manifests (`manifest.json`), prioritizing human readability, transparent inspectability, and ease of tooling. However, JSON parsing requires tokenization and syntax validation via `jq`, which is computationally heavier than direct binary struct offsets and incurs process execution overhead per manifest.

---

## 4. Not Yet Benchmarkable (Honest Gap List)

The following core package management operations are **not yet benchmarkable** because their underlying engine components are deferred to subsequent development phases:

| Feature / Operation | Implementation Status | Reason Not Yet Benchmarkable |
| :--- | :--- | :--- |
| **Package Installation Speed** | Stub (Phase 2) | Filesystem archive extraction (`.rav` / `.tar.zst`), file mapping, and permission preservation are not yet implemented. |
| **Package Removal Speed** | Stub (Phase 2) | Filesystem unlinking of installed files and clean-up of empty parent directories are not yet implemented. |
| **Dependency Resolution Speed** | Schema-only (Phase 3) | SAT or DAG dependency solver algorithm is not yet built; only manifest schema validation exists. |
| **Repository Sync & Search** | Stub (Phase 4) | Remote repository metadata downloads, local cache indices, and network transport are not yet built. |
| **Transaction Rollback Speed** | Unplanned | Transaction journaling, snapshot integration (ZFS), and rollback capabilities do not exist. |

---

## 5. Planned Benchmark Methodology

When Phases 2, 3, and 4 are implemented, they will be evaluated using the following benchmark methodology:

### 1. Installation Speed
- **Metric:** Wall-clock time from `ravpkg install <file>` invocation to payload files present on disk with correct permissions, and metadata committed to SQLite.
- **Test Matrix:**
  - Small package: 1 MB payload, 5 files (typical CLI tool).
  - Medium package: 25 MB payload, 200 files (shared library / utility suite).
  - Large package: 150 MB payload, 5,000 files (full graphical macOS-style `.app` bundle).
- **Measurement Breakdown:** Archive decompression time, I/O write throughput, and SQLite transaction commit time.

### 2. Removal Speed
- **Metric:** Wall-clock time from `ravpkg remove <pkg>` invocation to all target files unlinked from disk and DB record removed.
- **Test Matrix:** Evaluated across packages with 10, 500, and 5,000 installed files.
- **Measurement Breakdown:** File deletion I/O time vs. DB record removal time.

### 3. Dependency Resolution Speed
- **Metric:** Time and peak memory consumed by the resolver to compute an installation plan.
- **Test Matrix:**
  - Linear dependency chain (depth 5, 20, 50).
  - Diamond dependency graph (shared dependencies with version constraints).
  - Large repository simulation (5,000 synthetic packages with inter-dependencies).
  - Unsatisfiable dependency conflicts (time taken to fail with a clear explanation).

### 4. Repository Synchronization & Search Speed
- **Metric:** Time to fetch, decompress, and parse repository index files; search query latency against local repository cache indices (`ravpkg search <term>`).
