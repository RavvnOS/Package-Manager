#!/usr/bin/env bash
# tests/benchmark.sh - Performance benchmarking suite for ravpkg (Phase 1-2)
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
for tool in sqlite3 jq awk; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Error: prerequisite '$tool' not found." >&2
        exit 1
    fi
done

source "$ROOT_DIR/lib/parser.sh"
source "$ROOT_DIR/lib/db.sh"

BENCH_TMP="$(mktemp -d 2>/dev/null || mktemp -d -t 'ravpkg-bench')"
trap 'rm -rf "$BENCH_TMP"' EXIT

echo "=========================================================================="
echo "                   ravpkg Scaffolding Benchmark Suite                    "
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
echo "Generating synthetic databases..."
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

echo ""
echo "Running benchmarks (10 iterations per test)..."
echo "-------------------------------------------------------------------------------------------------"
printf "%-35s | %11s | %11s | %11s | %11s\n" "BENCHMARK OPERATION" "MIN" "MAX" "MEAN" "MEDIAN"
echo "-------------------------------------------------------------------------------------------------"

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
        printf "%-35s | %8.2f ms | %8.2f ms | %8.2f ms | %8.2f ms\n", test_name, min, max, mean, median
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

echo "-------------------------------------------------------------------------------------------------"
echo "Benchmark run completed successfully."
