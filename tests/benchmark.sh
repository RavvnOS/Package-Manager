#!/usr/bin/env bash
# tests/benchmark.sh - Comprehensive performance benchmarking suite for ravpkg (Phases 1-4)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Discover jq and sqlite3 in common WinGet locations if not already in PATH
if ! command -v jq >/dev/null 2>&1; then
    for p in "$LOCALAPPDATA"/Microsoft/WinGet/Packages/jqlang.jq_*; do
        if [[ -d "$p" ]]; then PATH="$p:$PATH"; fi
    done
fi
if ! command -v sqlite3 >/dev/null 2>&1; then
    for p in "$LOCALAPPDATA"/Microsoft/WinGet/Packages/SQLite.SQLite_*; do
        if [[ -d "$p" ]]; then PATH="$p:$PATH"; fi
    done
fi

export PATH

# Verify prerequisites
for tool in sqlite3 jq awk tar; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Error: prerequisite '$tool' not found." >&2
        exit 1
    fi
done

source "$ROOT_DIR/lib/parser.sh"
source "$ROOT_DIR/lib/db.sh"
source "$ROOT_DIR/lib/deps.sh"
source "$ROOT_DIR/lib/install.sh"
source "$ROOT_DIR/lib/remove.sh"
source "$ROOT_DIR/lib/repo.sh"

BENCH_TMP="$(mktemp -d 2>/dev/null || mktemp -d -t 'ravpkg-bench')"
trap 'rm -rf "$BENCH_TMP"' EXIT

echo "=========================================================================="
echo "                   ravpkg Comprehensive Benchmark Suite                  "
echo "=========================================================================="
echo "Date:              $(date -u +"%Y-%m-%d %H:%M:%SZ")"
echo "Bash version:      $BASH_VERSION"
echo "SQLite version:    $(sqlite3 --version | cut -d' ' -f1)"
echo "jq version:        $(jq --version)"
echo "Environment:       $(uname -s -m)"
echo "Iterations/test:   10"
echo "=========================================================================="
echo ""

# Helper to populate synthetic database at specific row counts
create_bench_db() {
    local db_path="$1"
    local count="$2"

    sqlite3 "$db_path" <<SQL
CREATE TABLE IF NOT EXISTS installed_packages (
    name TEXT PRIMARY KEY,
    version TEXT NOT NULL,
    install_date TEXT NOT NULL,
    manifest_path TEXT NOT NULL,
    installed_files TEXT NOT NULL
);
BEGIN TRANSACTION;
WITH RECURSIVE cnt(x) AS (
    SELECT 1 UNION ALL SELECT x + 1 FROM cnt WHERE x < $count
)
INSERT INTO installed_packages
SELECT 
    printf('pkg-%05d', x),
    '1.0.0',
    '2026-09-10T12:00:00Z',
    printf('/var/db/ravpkg/manifests/pkg-%05d.json', x),
    '["/usr/local/bin/sample-app","/usr/local/share/man/man1/sample-app.1"]'
FROM cnt;
COMMIT;
SQL
}

# Pre-generate synthetic databases
echo "Generating synthetic databases (10, 100, 1000, 10000 rows)..."
for count in 10 100 1000 10000; do
    create_bench_db "$BENCH_TMP/db_${count}.db" "$count"
done

# Pre-generate 100 manifest files for batch parsing
BATCH_DIR="$BENCH_TMP/batch_manifests"
mkdir -p "$BATCH_DIR"
echo "Generating 100 manifest fixtures for batch validation..."
for i in $(seq -w 1 100); do
    cat <<JSON > "$BATCH_DIR/pkg-${i}.json"
{
  "name": "synthetic-pkg-${i}",
  "version": "1.0.0",
  "description": "Synthetic benchmark manifest ${i}",
  "checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "install_paths": [
    { "source": "bin/tool", "destination": "/usr/local/bin/synthetic-${i}" },
    { "source": "share/doc/info", "destination": "/usr/local/share/doc/synthetic-${i}/README" }
  ],
  "dependencies": [
    { "name": "base-runtime", "constraint": ">=1.0.0" }
  ]
}
JSON
done

# Pre-generate repository indices of different scales
echo "Generating synthetic repository indices (10, 100, 1000 packages)..."
jq -n '[range(10) | {name: ("pkg-" + (tostring)), version: "1.0.0", description: ("Package description " + (tostring)), checksum: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", download_url: "http://localhost/dummy.rav"}]' > "$BENCH_TMP/repo_10.json"
jq -n '[range(100) | {name: ("pkg-" + (tostring)), version: "1.0.0", description: ("Package description " + (tostring)), checksum: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", download_url: "http://localhost/dummy.rav"}]' > "$BENCH_TMP/repo_100.json"
jq -n '[range(1000) | {name: ("pkg-" + (tostring)), version: "1.0.0", description: ("Package description " + (tostring)), checksum: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", download_url: "http://localhost/dummy.rav"}]' > "$BENCH_TMP/repo_1000.json"

# Pre-generate fixtures for dependency resolution benchmarks
DEPS_REPO="$BENCH_TMP/deps_repo.json"
cat << 'EOF' > "$DEPS_REPO"
[
  {
    "name": "chain-c",
    "version": "1.0.0",
    "description": "Chain C base",
    "checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "download_url": "http://localhost/c.rav",
    "dependencies": []
  },
  {
    "name": "chain-b",
    "version": "1.0.0",
    "description": "Chain B middle",
    "checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "download_url": "http://localhost/b.rav",
    "dependencies": [{ "name": "chain-c", "constraint": ">=1.0.0" }]
  },
  {
    "name": "chain-a",
    "version": "1.0.0",
    "description": "Chain A top",
    "checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "download_url": "http://localhost/a.rav",
    "dependencies": [{ "name": "chain-b", "constraint": ">=1.0.0" }]
  },
  {
    "name": "diamond-common",
    "version": "2.1.0",
    "description": "Diamond Common Library",
    "checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "download_url": "http://localhost/common.rav",
    "dependencies": []
  },
  {
    "name": "diamond-left",
    "version": "1.0.0",
    "description": "Diamond Left Branch",
    "checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "download_url": "http://localhost/left.rav",
    "dependencies": [{ "name": "diamond-common", "constraint": ">=2.0.0" }]
  },
  {
    "name": "diamond-right",
    "version": "1.0.0",
    "description": "Diamond Right Branch",
    "checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "download_url": "http://localhost/right.rav",
    "dependencies": [{ "name": "diamond-common", "constraint": ">=1.5.0" }]
  },
  {
    "name": "diamond-app",
    "version": "1.0.0",
    "description": "Diamond App Root",
    "checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "download_url": "http://localhost/app.rav",
    "dependencies": [
      { "name": "diamond-left", "constraint": ">=1.0.0" },
      { "name": "diamond-right", "constraint": ">=1.0.0" }
    ]
  }
]
EOF

CHAIN_MANIFEST="$(jq -c '.[] | select(.name=="chain-a")' "$DEPS_REPO")"
DIAMOND_MANIFEST="$(jq -c '.[] | select(.name=="diamond-app")' "$DEPS_REPO")"
EMPTY_DB="$BENCH_TMP/empty_deps.db"
db_init "$EMPTY_DB" "$ROOT_DIR/schema/schema.sql"

# Pre-generate real package archive for lifecycle install/remove benchmarks
echo "Generating test package archive for install/remove benchmarks..."
LIFECYCLE_BUILD="$BENCH_TMP/lifecycle_build"
mkdir -p "$LIFECYCLE_BUILD/usr/local/bin"
echo "#!/bin/sh" > "$LIFECYCLE_BUILD/usr/local/bin/bench-app"
echo "echo 'ravpkg benchmark app'" >> "$LIFECYCLE_BUILD/usr/local/bin/bench-app"
chmod +x "$LIFECYCLE_BUILD/usr/local/bin/bench-app"
APP_CS="$(_calc_sha256 "$LIFECYCLE_BUILD/usr/local/bin/bench-app")"

cat << EOF > "$LIFECYCLE_BUILD/manifest.json"
{
  "name": "bench-app",
  "version": "1.0.0",
  "description": "Lifecycle Benchmark Package",
  "checksum": "$APP_CS",
  "install_paths": [
    { "source": "usr/local/bin/bench-app", "destination": "/usr/local/bin/bench-app" }
  ]
}
EOF

LIFECYCLE_PKG="$BENCH_TMP/bench-app-1.0.0.rav"
(cd "$LIFECYCLE_BUILD" && tar -czf "$LIFECYCLE_PKG" manifest.json usr/local/bin/bench-app)

LIFECYCLE_DB="$BENCH_TMP/lifecycle.db"
LIFECYCLE_SANDBOX="$BENCH_TMP/lifecycle_sandbox"
mkdir -p "$LIFECYCLE_SANDBOX"
db_init "$LIFECYCLE_DB" "$ROOT_DIR/schema/schema.sql"

echo ""
echo "Running benchmarks (10 iterations per test)..."
echo "-------------------------------------------------------------------------------------------------------"
printf "%-39s | %11s | %11s | %11s | %11s\n" "BENCHMARK OPERATION" "MIN" "MAX" "MEAN" "MEDIAN"
echo "-------------------------------------------------------------------------------------------------------"

# Run benchmark 10 times and calculate min, max, mean, median
run_benchmark() {
    local label="$1"
    shift
    local times=()

    for iter in {1..10}; do
        local start_ns end_ns elapsed_ns elapsed_ms
        start_ns="$(date +%s%N)"
        "$@" >/dev/null 2>&1
        end_ns="$(date +%s%N)"
        elapsed_ns=$((end_ns - start_ns))
        elapsed_ms="$(awk -v ns="$elapsed_ns" 'BEGIN { printf "%.2f", ns / 1000000 }')"
        times+=("$elapsed_ms")
    done

    awk -v test_name="$label" -v raw="${times[*]}" 'BEGIN {
        n = split(raw, arr, " ");
        for (i = 1; i <= n; i++) {
            for (j = i + 1; j <= n; j++) {
                if ((arr[i] + 0) > (arr[j] + 0)) {
                    tmp = arr[i]; arr[i] = arr[j]; arr[j] = tmp;
                }
            }
        }
        min = arr[1] + 0;
        max = arr[n] + 0;
        sum = 0;
        for (i = 1; i <= n; i++) sum += (arr[i] + 0);
        mean = sum / n;
        if (n % 2 == 1) {
            median = arr[(n + 1) / 2] + 0;
        } else {
            median = (arr[n / 2] + arr[n / 2 + 1]) / 2;
        }
        printf "%-39s | %8.2f ms | %8.2f ms | %8.2f ms | %8.2f ms\n", test_name, min, max, mean, median
    }'
}

# 1. Manifest parsing: single
run_benchmark "Manifest parse (single valid)" parse_manifest_file "$ROOT_DIR/tests/fixtures/valid-manifest.json"

# 2. Manifest parsing: batch 100
batch_parse_100() {
    for mf in "$BATCH_DIR"/*.json; do
        parse_manifest_file "$mf" >/dev/null
    done
}
run_benchmark "Manifest parse (batch 100 files)" batch_parse_100

# 3. ravpkg info <pkg> lookup at 10, 100, 1000, 10000 rows
for count in 10 100 1000 10000; do
    target_pkg="pkg-00005"
    run_benchmark "ravpkg info (${count} DB rows)" "$ROOT_DIR/bin/ravpkg" --db "$BENCH_TMP/db_${count}.db" info "$target_pkg"
done

# 4. ravpkg list at 10, 100, 1000, 10000 rows
for count in 10 100 1000 10000; do
    run_benchmark "ravpkg list (${count} DB rows)" "$ROOT_DIR/bin/ravpkg" --db "$BENCH_TMP/db_${count}.db" list
done

# 5. Semantic version evaluation (50 checks: compare + constraint check)
bench_semver_50() {
    local k
    for ((k=0; k<25; k++)); do
        semver_satisfies "1.2.3" ">=1.0.0"
        semver_satisfies "2.0.0" "<=2.0.0"
    done
}
run_benchmark "Semver evaluation (50 checks)" bench_semver_50

# 6. Repository index search
run_benchmark "Repo search (10 index entries)" repo_search "$BENCH_TMP/repo_10.json" "pkg-5"
run_benchmark "Repo search (100 index entries)" repo_search "$BENCH_TMP/repo_100.json" "pkg-50"
run_benchmark "Repo search (1,000 index entries)" repo_search "$BENCH_TMP/repo_1000.json" "pkg-500"

# 7. Dependency resolution & topological planning
bench_deps_chain() {
    deps_build_install_plan "chain-a" "$CHAIN_MANIFEST" "$EMPTY_DB" "$DEPS_REPO" "$BENCH_TMP"
}
run_benchmark "Dependency plan (linear chain A->B->C)" bench_deps_chain

bench_deps_diamond() {
    deps_build_install_plan "diamond-app" "$DIAMOND_MANIFEST" "$EMPTY_DB" "$DEPS_REPO" "$BENCH_TMP"
}
run_benchmark "Dependency plan (diamond graph 4 pkgs)" bench_deps_diamond

# 8. Package install and remove lifecycle (10 iterations)
bench_install_run() {
    local times=()
    export RAVPKG_ROOT="$LIFECYCLE_SANDBOX"

    for iter in {1..10}; do
        rm -rf "$LIFECYCLE_SANDBOX"/*
        sqlite3 "$LIFECYCLE_DB" "DELETE FROM installed_packages WHERE name='bench-app';"
        local start_ns end_ns elapsed_ns elapsed_ms
        start_ns="$(date +%s%N)"
        pkg_install "$LIFECYCLE_DB" "$LIFECYCLE_PKG" >/dev/null 2>&1
        end_ns="$(date +%s%N)"
        elapsed_ns=$((end_ns - start_ns))
        elapsed_ms="$(awk -v ns="$elapsed_ns" 'BEGIN { printf "%.2f", ns / 1000000 }')"
        times+=("$elapsed_ms")
    done

    awk -v test_name="Package install (.rav archive + DB)" -v raw="${times[*]}" 'BEGIN {
        n = split(raw, arr, " ");
        for (i = 1; i <= n; i++) {
            for (j = i + 1; j <= n; j++) {
                if ((arr[i] + 0) > (arr[j] + 0)) {
                    tmp = arr[i]; arr[i] = arr[j]; arr[j] = tmp;
                }
            }
        }
        min = arr[1] + 0;
        max = arr[n] + 0;
        sum = 0;
        for (i = 1; i <= n; i++) sum += (arr[i] + 0);
        mean = sum / n;
        if (n % 2 == 1) {
            median = arr[(n + 1) / 2] + 0;
        } else {
            median = (arr[n / 2] + arr[n / 2 + 1]) / 2;
        }
        printf "%-39s | %8.2f ms | %8.2f ms | %8.2f ms | %8.2f ms\n", test_name, min, max, mean, median
    }'
}
bench_install_run

bench_remove_run() {
    local times=()
    export RAVPKG_ROOT="$LIFECYCLE_SANDBOX"

    for iter in {1..10}; do
        # Ensure installed
        pkg_install "$LIFECYCLE_DB" "$LIFECYCLE_PKG" >/dev/null 2>&1 || true
        local start_ns end_ns elapsed_ns elapsed_ms
        start_ns="$(date +%s%N)"
        pkg_remove "$LIFECYCLE_DB" "bench-app" >/dev/null 2>&1
        end_ns="$(date +%s%N)"
        elapsed_ns=$((end_ns - start_ns))
        elapsed_ms="$(awk -v ns="$elapsed_ns" 'BEGIN { printf "%.2f", ns / 1000000 }')"
        times+=("$elapsed_ms")
    done

    awk -v test_name="Package remove (unlink + DB purge)" -v raw="${times[*]}" 'BEGIN {
        n = split(raw, arr, " ");
        for (i = 1; i <= n; i++) {
            for (j = i + 1; j <= n; j++) {
                if ((arr[i] + 0) > (arr[j] + 0)) {
                    tmp = arr[i]; arr[i] = arr[j]; arr[j] = tmp;
                }
            }
        }
        min = arr[1] + 0;
        max = arr[n] + 0;
        sum = 0;
        for (i = 1; i <= n; i++) sum += (arr[i] + 0);
        mean = sum / n;
        if (n % 2 == 1) {
            median = arr[(n + 1) / 2] + 0;
        } else {
            median = (arr[n / 2] + arr[n / 2 + 1]) / 2;
        }
        printf "%-39s | %8.2f ms | %8.2f ms | %8.2f ms | %8.2f ms\n", test_name, min, max, mean, median
    }'
}
bench_remove_run

echo "-------------------------------------------------------------------------------------------------------"
echo "Benchmark run completed successfully."
