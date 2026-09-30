#!/usr/bin/env bats
# tests/test_search.bats - Unit and integration tests for repo index generator and search

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    ROOT_DIR="$TEST_DIR"
    TEST_TMP="$(mktemp -d 2>/dev/null || mktemp -d -t 'ravpkg-search-test')"
    export PATH="$TEST_DIR/bin:$PATH"

    # Source libraries
    source "$TEST_DIR/lib/repo.sh"

    # Create dummy manifests directory
    MANIFESTS_DIR="$TEST_TMP/manifests"
    mkdir -p "$MANIFESTS_DIR"

    # 1. Valid manifest: text-editor
    cat <<'EOF' > "$MANIFESTS_DIR/editor.json"
{
  "name": "ravtext",
  "version": "1.0.0",
  "description": "Minimal text editor for ravynOS desktop",
  "checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "install_paths": [
    { "source": "bin/ravtext", "destination": "/usr/local/bin/ravtext" }
  ]
}
EOF

    # 2. Valid manifest: system utility
    cat <<'EOF' > "$MANIFESTS_DIR/sysinfo.json"
{
  "name": "ravinfo",
  "version": "2.0.0",
  "description": "System hardware info inspection tool",
  "checksum": "a94a8fe5ccb19ba61c4c0873d391e987982fbbd30002b80a1c1d044673898166",
  "install_paths": [
    { "source": "bin/ravinfo", "destination": "/usr/local/bin/ravinfo" }
  ]
}
EOF

    # 3. Invalid manifest (missing name) - should be skipped
    cat <<'EOF' > "$MANIFESTS_DIR/invalid.json"
{
  "version": "0.1.0",
  "checksum": "1111111111111111111111111111111111111111111111111111111111111111"
}
EOF

    INDEX_FILE="$TEST_TMP/index.json"
    CACHE_FILE="$TEST_TMP/cache.json"
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "index-generator: generates valid index JSON from manifests directory" {
    run "$ROOT_DIR/repo/generate-index.sh" -o "$INDEX_FILE" "$MANIFESTS_DIR"
    [ "$status" -eq 0 ]
    [ -f "$INDEX_FILE" ]

    # Validate JSON array structure
    count="$(jq 'length' "$INDEX_FILE")"
    [ "$count" -eq 2 ]

    # Check fields of first entry
    first_name="$(jq -r '.[0].name' "$INDEX_FILE")"
    first_ver="$(jq -r '.[0].version' "$INDEX_FILE")"
    first_desc="$(jq -r '.[0].description' "$INDEX_FILE")"
    first_url="$(jq -r '.[0].download_url' "$INDEX_FILE")"
    first_cs="$(jq -r '.[0].checksum' "$INDEX_FILE")"

    [ "$first_name" = "ravinfo" ]
    [ "$first_ver" = "2.0.0" ]
    [[ "$first_desc" =~ "hardware info" ]]
    [ "$first_url" = "https://repo.ravynos.com/packages/ravinfo-2.0.0.rav" ]
    [ "$first_cs" = "a94a8fe5ccb19ba61c4c0873d391e987982fbbd30002b80a1c1d044673898166" ]
}

@test "repo: fetch/cache index from local file path" {
    # Generate index first
    "$ROOT_DIR/repo/generate-index.sh" -o "$INDEX_FILE" "$MANIFESTS_DIR"

    # Fetch/cache using local path
    run repo_fetch_index "$INDEX_FILE" "$CACHE_FILE"
    [ "$status" -eq 0 ]
    [ -f "$CACHE_FILE" ]

    cached_count="$(jq 'length' "$CACHE_FILE")"
    [ "$cached_count" -eq 2 ]
}

@test "repo: fetch non-existent file path fails with clear error" {
    run repo_fetch_index "$TEST_TMP/does-not-exist.json" "$CACHE_FILE"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "not found" ]]
}

@test "search: missing/uncached index produces clear error and non-zero exit" {
    run "$ROOT_DIR/bin/ravpkg" --cache "$TEST_TMP/missing-cache.json" search "editor"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "missing or not cached" ]]
}

@test "search: matches package name" {
    "$ROOT_DIR/repo/generate-index.sh" -o "$INDEX_FILE" "$MANIFESTS_DIR"

    run "$ROOT_DIR/bin/ravpkg" --cache "$CACHE_FILE" --repo "$INDEX_FILE" search "ravtext"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ravtext" ]]
    [[ "$output" =~ "1.0.0" ]]
    [[ "$output" =~ "Minimal text editor" ]]
}

@test "search: matches package description (case-insensitive)" {
    "$ROOT_DIR/repo/generate-index.sh" -o "$INDEX_FILE" "$MANIFESTS_DIR"

    # Search for uppercase "HARDWARE" matching "hardware info" in ravinfo
    run "$ROOT_DIR/bin/ravpkg" --cache "$CACHE_FILE" --repo "$INDEX_FILE" search "HARDWARE"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ravinfo" ]]
    [[ "$output" =~ "2.0.0" ]]
    [[ "$output" =~ "hardware info" ]]
}

@test "search: no matches found outputs clean notice" {
    "$ROOT_DIR/repo/generate-index.sh" -o "$INDEX_FILE" "$MANIFESTS_DIR"

    run "$ROOT_DIR/bin/ravpkg" --cache "$CACHE_FILE" --repo "$INDEX_FILE" search "nonexistentpkg"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "No packages found matching 'nonexistentpkg'" ]]
}
