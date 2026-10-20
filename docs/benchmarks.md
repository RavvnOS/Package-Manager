# ravpkg Performance Benchmarks (Phases 1–4)

**Document Version:** 2.0.0  
**Target System:** ravynOS (Darwin/FreeBSD userland)  
**Implementation:** Pure Bash + SQLite 3 + jq  
**Test Suite:** `tests/benchmark.sh`

---

## 1. Test Environment & Verification Notice

> [!IMPORTANT]
> **Environment Note:**  
> The benchmarks below were measured on **2026-10-20**, using **Bash 5.3.9**, **SQLite 3.46.1**, and **jq 1.8.1** on an x86_64 development environment.  
> All figures below are direct measurements from running `tests/benchmark.sh` across 10 iterations per benchmark scenario.

---

## 2. Measured Benchmark Results

| Benchmark Operation | Scale / Dataset | Min | Max | Mean | Median |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Manifest parse** | Single valid manifest (`valid-manifest.json`) | 30.46 ms | 41.75 ms | 33.00 ms | 31.70 ms |
| **Manifest parse** | Batch validation (100 synthetic manifests) | 1,944.49 ms | 2,161.87 ms | 2,016.16 ms | 1,990.90 ms |
| **`ravpkg info <pkg>`** | 10 packages in SQLite DB | 118.98 ms | 171.90 ms | 130.09 ms | 122.90 ms |
| **`ravpkg info <pkg>`** | 100 packages in SQLite DB | 121.54 ms | 144.97 ms | 126.16 ms | 123.66 ms |
| **`ravpkg info <pkg>`** | 1,000 packages in SQLite DB | 115.56 ms | 127.16 ms | 122.04 ms | 122.91 ms |
| **`ravpkg info <pkg>`** | 10,000 packages in SQLite DB | 116.52 ms | 127.19 ms | 121.05 ms | 120.40 ms |
| **`ravpkg list`** | 10 packages in SQLite DB | 92.15 ms | 105.61 ms | 96.09 ms | 94.85 ms |
| **`ravpkg list`** | 100 packages in SQLite DB | 98.52 ms | 162.51 ms | 107.56 ms | 102.66 ms |
| **`ravpkg list`** | 1,000 packages in SQLite DB | 156.52 ms | 167.67 ms | 161.06 ms | 160.96 ms |
| **`ravpkg list`** | 10,000 packages in SQLite DB | 804.00 ms | 904.88 ms | 835.48 ms | 829.70 ms |
| **Semver evaluation** | 50 checks (comparison + constraint check) | 562.59 ms | 636.10 ms | 599.34 ms | 590.64 ms |
| **Repo search** | 10 packages in repository index | 21.45 ms | 23.65 ms | 22.59 ms | 22.63 ms |
| **Repo search** | 100 packages in repository index | 23.93 ms | 27.33 ms | 25.48 ms | 25.51 ms |
| **Repo search** | 1,000 packages in repository index | 49.35 ms | 59.15 ms | 54.15 ms | 54.09 ms |
| **Dependency planning** | Linear chain (depth 3: A -> B -> C) | 244.23 ms | 314.98 ms | 271.88 ms | 271.89 ms |
| **Dependency planning** | Diamond graph (4 packages, deduplicated) | 428.64 ms | 455.81 ms | 435.78 ms | 433.10 ms |
| **Package install** | `.rav` extract + SHA-256 verify + SQLite write | 208.46 ms | 220.30 ms | 213.57 ms | 213.17 ms |
| **Package remove** | Unlink files + parent dir clean + DB purge | 91.13 ms | 110.64 ms | 98.26 ms | 98.05 ms |

---

## 3. Architectural Observations & Analysis

1. **O(1) Indexed Lookups for `info`**:
   The execution time for `ravpkg info` remains flat (~120–123 ms) regardless of whether the SQLite database contains 10 packages or 10,000 packages. Because `name` is indexed as the primary key in SQLite, query latency is negligible; execution time is dominated by script invocation overhead.

2. **Efficient Linear Scaling for `list`**:
   `ravpkg list` scales from ~95 ms at 10 packages to ~830 ms at 10,000 packages. Streaming through SQLite `-json` into `jq` and formatting lines preserves memory while handling large datasets smoothly.

3. **Sub-60ms Repository Search across 1,000 Packages**:
   Searching an index of 1,000 packages with case-insensitive matching across both package name and description takes only **54.09 ms** median.

4. **Fast Graph Dependency Planning**:
   Resolving a multi-tier dependency chain takes ~270 ms, while a complex diamond dependency graph (with constraint evaluation and deduplication) resolves in ~433 ms.

5. **Sub-Quarter-Second Transactional Installation**:
   Extracting an archive payload, verifying its cryptographic SHA-256 checksum, checking path safety, placing files in the target root, and committing the transaction to SQLite takes only **213.17 ms** median. Package removal completes in **98.05 ms**.

---

## 4. Comparison with DNF/YUM and FreeBSD pkg

| Dimension | `dnf` / `yum` (RPM) | FreeBSD `pkg` | `ravpkg` |
| :--- | :--- | :--- | :--- |
| **Runtime Implementation** | Python + C (`libdnf`/`hawkey`) | Native C (`libpkg` + SQLite) | Pure Bash 4+ (`sqlite3` + `jq`) |
| **Build / Compilation Step** | Requires Python, C toolchain, CMake | Requires C compiler, Clang/GCC | **Zero build step**: clone and run |
| **Metadata Format** | Binary RPM header + XML/YAML repodata | `pkg-plist` + UCL/JSON + SQLite index | Standard JSON manifest (`manifest.json`) |
| **Single Lookup Latency** | ~500–1,500 ms (interpreter start / cache check) | ~10–50 ms (native compiled C) | ~120 ms (`sqlite3` indexed query) |
| **Small Repo Search** | Variable (often checks repo freshness over net) | Fast native SQLite query (~20 ms) | ~25–54 ms (`jq` index scan) |
| **Transaction Integrity** | RPM transaction sets (`rpmdb` lock) | SQLite transaction + atomic rename | Staged extraction + automatic rollback |
| **Auditing & Transparency** | Opaque binary structs and bytecode | Compiled native ELF binary | **100% human-readable shell code** |

---

## 5. Benchmark Reproducibility

To re-run this exact benchmarking suite on any POSIX-compatible host:

```bash
# Ensure sqlite3, jq, awk, and tar are available
./tests/benchmark.sh
```
