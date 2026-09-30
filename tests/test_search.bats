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

@test "install-by-name: successful install from repository index" {
    PKG_BUILD="$TEST_TMP/ravtext_build"
    mkdir -p "$PKG_BUILD/bin"
    echo "#!/bin/sh" > "$PKG_BUILD/bin/ravtext"
    echo "echo Text Editor" >> "$PKG_BUILD/bin/ravtext"
    TEXT_CS="$(cat "$PKG_BUILD/bin/ravtext" | _calc_sha256 -)"

    cat <<EOF > "$PKG_BUILD/manifest.json"
{
  "name": "ravtext",
  "version": "1.0.0",
  "description": "Minimal text editor for ravynOS desktop",
  "checksum": "$TEXT_CS",
  "install_paths": [
    { "source": "bin/ravtext", "destination": "/usr/local/bin/ravtext" }
  ]
}
EOF
    RAVTEXT_PKG="$TEST_TMP/ravtext-1.0.0.rav"
    (cd "$PKG_BUILD" && tar -czf "$RAVTEXT_PKG" manifest.json bin/ravtext)

    cat <<EOF > "$INDEX_FILE"
[
  {
    "name": "ravtext",
    "version": "1.0.0",
    "description": "Minimal text editor",
    "download_url": "file://$RAVTEXT_PKG",
    "checksum": "$TEXT_CS"
  }
]
EOF

    SANDBOX="$TEST_TMP/sandbox"
    DB="$TEST_TMP/test.db"
    mkdir -p "$SANDBOX"

    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$DB" --repo "$INDEX_FILE" --cache "$CACHE_FILE" --no-cache install ravtext
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Successfully installed: ravtext 1.0.0" ]]
    [ -f "$SANDBOX/usr/local/bin/ravtext" ]
}

@test "install-by-name: index checksum mismatch fails loudly" {
    PKG_BUILD="$TEST_TMP/ravtext_build2"
    mkdir -p "$PKG_BUILD/bin"
    echo "echo Text Editor" >> "$PKG_BUILD/bin/ravtext"
    TEXT_CS="$(cat "$PKG_BUILD/bin/ravtext" | _calc_sha256 -)"

    cat <<EOF > "$PKG_BUILD/manifest.json"
{
  "name": "ravtext",
  "version": "1.0.0",
  "description": "Minimal text editor",
  "checksum": "$TEXT_CS",
  "install_paths": [
    { "source": "bin/ravtext", "destination": "/usr/local/bin/ravtext" }
  ]
}
EOF
    RAVTEXT_PKG="$TEST_TMP/ravtext2-1.0.0.rav"
    (cd "$PKG_BUILD" && tar -czf "$RAVTEXT_PKG" manifest.json bin/ravtext)

    cat <<EOF > "$INDEX_FILE"
[
  {
    "name": "ravtext",
    "version": "1.0.0",
    "description": "Minimal text editor",
    "download_url": "file://$RAVTEXT_PKG",
    "checksum": "0000000000000000000000000000000000000000000000000000000000000000"
  }
]
EOF

    SANDBOX="$TEST_TMP/sandbox2"
    DB="$TEST_TMP/test2.db"
    mkdir -p "$SANDBOX"

    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$DB" --repo "$INDEX_FILE" --cache "$CACHE_FILE" --no-cache install ravtext
    [ "$status" -ne 0 ]
    [[ "$output" =~ "checksum mismatch between downloaded package and repository index" ]]
    [ ! -f "$SANDBOX/usr/local/bin/ravtext" ]
}

@test "install-by-name: package not in index fails with clear error" {
    cat <<EOF > "$INDEX_FILE"
[]
EOF
    SANDBOX="$TEST_TMP/sandbox3"
    DB="$TEST_TMP/test3.db"

    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$DB" --repo "$INDEX_FILE" --cache "$CACHE_FILE" --no-cache install missing-app
    [ "$status" -ne 0 ]
    [[ "$output" =~ "package 'missing-app' not found in repository index" ]]
}

@test "install-by-name: network failure handled gracefully with no leftover files" {
    cat <<EOF > "$INDEX_FILE"
[
  {
    "name": "netfail-app",
    "version": "1.0.0",
    "description": "Net fail app",
    "download_url": "http://127.0.0.1:59999/nonexistent.rav",
    "checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  }
]
EOF
    SANDBOX="$TEST_TMP/sandbox4"
    DB="$TEST_TMP/test4.db"

    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$DB" --repo "$INDEX_FILE" --cache "$CACHE_FILE" --no-cache install netfail-app
    [ "$status" -ne 0 ]
    [[ "$output" =~ "failed to download package" ]]
}

@test "install-by-name: index and manifest checksum disagreement fails loudly" {
    PKG_BUILD="$TEST_TMP/disagree_build"
    mkdir -p "$PKG_BUILD/bin"
    echo "disagree" > "$PKG_BUILD/bin/disagree"
    CS1="1111111111111111111111111111111111111111111111111111111111111111"
    cat <<EOF > "$PKG_BUILD/manifest.json"
{
  "name": "disagree-app",
  "version": "1.0.0",
  "description": "Disagree app",
  "checksum": "$CS1",
  "install_paths": [
    { "source": "bin/disagree", "destination": "/usr/local/bin/disagree" }
  ]
}
EOF
    DISAGREE_PKG="$TEST_TMP/disagree.rav"
    (cd "$PKG_BUILD" && tar -czf "$DISAGREE_PKG" manifest.json bin/disagree)
    CS2="$(_calc_sha256 "$DISAGREE_PKG")"

    cat <<EOF > "$INDEX_FILE"
[
  {
    "name": "disagree-app",
    "version": "1.0.0",
    "description": "Disagree app",
    "download_url": "file://$DISAGREE_PKG",
    "checksum": "$CS2"
  }
]
EOF

    SANDBOX="$TEST_TMP/sandbox5"
    DB="$TEST_TMP/test5.db"
    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$DB" --repo "$INDEX_FILE" --cache "$CACHE_FILE" --no-cache install disagree-app
    [ "$status" -ne 0 ]
    [[ "$output" =~ "checksum disagreement between repository index and package manifest" ]]
}
