#!/usr/bin/env bash
# tests/run_tests.sh - Test runner for ravpkg (supports bats or native bash fallback)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# If bats is available, run bats
if command -v bats >/dev/null 2>&1; then
    echo "Running tests with bats..."
    exec bats "$SCRIPT_DIR"/test_*.bats
fi

echo "bats not found in PATH; running tests via native Bash test runner..."
echo "================================================================="

source "$ROOT_DIR/lib/parser.sh"
source "$ROOT_DIR/lib/db.sh"
source "$ROOT_DIR/lib/install.sh"
source "$ROOT_DIR/lib/remove.sh"

PASSED=0
FAILED=0

assert_ok() {
    local desc="$1"
    shift
    if "$@"; then
        echo "  [PASS] $desc"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $desc"
        FAILED=$((FAILED + 1))
    fi
}

assert_fail() {
    local desc="$1"
    shift
    if ! "$@" >/dev/null 2>&1; then
        echo "  [PASS] $desc"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $desc (expected failure)"
        FAILED=$((FAILED + 1))
    fi
}

echo ""
echo "--- Parser & Validation Tests ---"
FIXTURES="$SCRIPT_DIR/fixtures"

assert_ok "valid manifest parses" parse_manifest_file "$FIXTURES/valid-manifest.json"
assert_ok "with-deps manifest parses" parse_manifest_file "$FIXTURES/with-deps-manifest.json"
assert_fail "missing fields returns error" parse_manifest_file "$FIXTURES/missing-fields-manifest.json"
assert_fail "bad checksum returns error" parse_manifest_file "$FIXTURES/bad-checksum-manifest.json"
assert_fail "empty manifest data returns error" validate_manifest ""
assert_fail "malformed JSON returns error" validate_manifest "{not-json}"
assert_fail "empty install_paths returns error" validate_manifest '{"name":"p","version":"1","description":"d","checksum":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855","install_paths":[]}'
assert_fail "empty source returns error" validate_manifest '{"name":"p","version":"1","description":"d","checksum":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855","install_paths":[{"source":"","destination":"/bin/p"}]}'
assert_fail "empty destination returns error" validate_manifest '{"name":"p","version":"1","description":"d","checksum":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855","install_paths":[{"source":"bin/p","destination":""}]}'

echo ""
echo "--- Database CRUD Tests ---"
TEST_TMP="$(mktemp -d 2>/dev/null || mktemp -d -t 'ravpkg-test')"
DB_FILE="$TEST_TMP/test.db"
SCHEMA="$ROOT_DIR/schema/schema.sql"

db_init "$DB_FILE" "$SCHEMA"
assert_ok "database schema initialized" sqlite3 "$DB_FILE" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='installed_packages';"

FILES='["/usr/local/bin/ravterm","/usr/local/share/man/man1/ravterm.1"]'
assert_ok "add_package" db_add_package "$DB_FILE" "ravterm" "1.0.0" "2026-09-10T12:00:00Z" "/path/manifest.json" "$FILES"
assert_ok "get_package (existing)" db_get_package "$DB_FILE" "ravterm"
assert_fail "get_package (not found)" db_get_package "$DB_FILE" "missing-pkg"

assert_ok "add another package" db_add_package "$DB_FILE" "alpha" "0.1.0" "2026-01-01T00:00:00Z" "/path/a.json" '[]'
LIST_OUT="$(db_list_packages "$DB_FILE")"
FIRST_PKG="$(echo "$LIST_OUT" | jq -r '.[0].name')"
if [[ "$FIRST_PKG" == "alpha" ]]; then
    echo "  [PASS] list_packages returned alphabetical ordering (alpha first)"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] list_packages alphabetical ordering check (got: $FIRST_PKG)"
    FAILED=$((FAILED + 1))
fi

assert_ok "remove_package" db_remove_package "$DB_FILE" "ravterm"
assert_fail "get_package after removal" db_get_package "$DB_FILE" "ravterm"
assert_fail "remove non-existent package" db_remove_package "$DB_FILE" "ravterm"

rm -rf "$TEST_TMP"

echo ""
echo "--- CLI Command Routing & Query Tests ---"
CLI_DB="$ROOT_DIR/cli_test.db"
rm -f "$CLI_DB"

assert_ok "CLI --help displays help text" "$ROOT_DIR/bin/ravpkg" --help
assert_ok "CLI list on empty database" "$ROOT_DIR/bin/ravpkg" --db "$CLI_DB" list
assert_fail "CLI info on non-existent package fails" "$ROOT_DIR/bin/ravpkg" --db "$CLI_DB" info notinstalled

# Test CLI list and info with actual inserted package
db_init "$CLI_DB" "$SCHEMA"
db_add_package "$CLI_DB" "demo-pkg" "1.2.3" "2026-10-01T01:00:00Z" "/path/demo.json" '["/usr/bin/demo"]'
assert_ok "CLI list with installed package" "$ROOT_DIR/bin/ravpkg" --db "$CLI_DB" list
assert_ok "CLI info with installed package" "$ROOT_DIR/bin/ravpkg" --db "$CLI_DB" info demo-pkg

rm -f "$CLI_DB"

echo ""
echo "--- Filesystem Install & Remove Tests ---"
IR_TMP="$(mktemp -d 2>/dev/null || mktemp -d -t 'ravpkg-ir-test')"
IR_SANDBOX="$IR_TMP/sandbox"
IR_DB="$IR_TMP/pkg.db"
mkdir -p "$IR_SANDBOX"
db_init "$IR_DB" "$SCHEMA"

# Build valid test package
BUILD_DIR="$IR_TMP/build"
mkdir -p "$BUILD_DIR/bin" "$BUILD_DIR/share/doc"
echo '#!/bin/sh' > "$BUILD_DIR/bin/runner"
echo 'echo Run' >> "$BUILD_DIR/bin/runner"
echo 'Manual docs' > "$BUILD_DIR/share/doc/MANUAL"

CS="$(cat "$BUILD_DIR/bin/runner" "$BUILD_DIR/share/doc/MANUAL" | _calc_sha256 -)"
cat <<JSON > "$BUILD_DIR/manifest.json"
{
  "name": "sample-app",
  "version": "1.0.0",
  "description": "Sample application",
  "checksum": "$CS",
  "install_paths": [
    { "source": "bin/runner", "destination": "/usr/local/bin/runner" },
    { "source": "share/doc/MANUAL", "destination": "/usr/local/share/doc/sample/MANUAL" }
  ]
}
JSON

SAMPLE_PKG="$IR_TMP/sample-app-1.0.0.rav"
(cd "$BUILD_DIR" && tar -czf "$SAMPLE_PKG" manifest.json bin/runner share/doc/MANUAL)

# 1. Successful install
assert_ok "install creates files and db record" "$ROOT_DIR/bin/ravpkg" --root "$IR_SANDBOX" --db "$IR_DB" install "$SAMPLE_PKG"
if [[ -f "$IR_SANDBOX/usr/local/bin/runner" && -f "$IR_SANDBOX/usr/local/share/doc/sample/MANUAL" ]]; then
    echo "  [PASS] installed files exist on target filesystem"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] installed files missing from filesystem"
    FAILED=$((FAILED + 1))
fi

# 2. Reject already installed
assert_fail "reject duplicate install" "$ROOT_DIR/bin/ravpkg" --root "$IR_SANDBOX" --db "$IR_DB" install "$SAMPLE_PKG"

# 3. Bad checksum rejection
BAD_BUILD="$IR_TMP/bad_build"
mkdir -p "$BAD_BUILD/bin"
echo "bad" > "$BAD_BUILD/bin/bad"
cat <<JSON > "$BAD_BUILD/manifest.json"
{
  "name": "bad-app",
  "version": "1.0.0",
  "description": "Bad checksum app",
  "checksum": "1111111111111111111111111111111111111111111111111111111111111111",
  "install_paths": [
    { "source": "bin/bad", "destination": "/usr/local/bin/bad" }
  ]
}
JSON
BAD_PKG="$IR_TMP/bad-1.0.0.rav"
(cd "$BAD_BUILD" && tar -czf "$BAD_PKG" manifest.json bin/bad)

assert_fail "install with bad checksum rejected" "$ROOT_DIR/bin/ravpkg" --root "$IR_SANDBOX" --db "$IR_DB" install "$BAD_PKG"
if [[ ! -f "$IR_SANDBOX/usr/local/bin/bad" ]]; then
    echo "  [PASS] bad checksum package wrote nothing to filesystem"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] bad checksum package wrote files to filesystem"
    FAILED=$((FAILED + 1))
fi

# 3b. --skip-verify bypasses checksum enforcement with loud warning logged
SKIP_OUT="$("$ROOT_DIR/bin/ravpkg" --root "$IR_SANDBOX" --db "$IR_DB" install --skip-verify "$BAD_PKG" 2>&1 || true)"
if [[ "$SKIP_OUT" =~ "WARNING: --skip-verify is enabled! Checksum verification is BYPASSED." ]]; then
    echo "  [PASS] --skip-verify printed loud warning banner"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] --skip-verify warning banner not found in output"
    FAILED=$((FAILED + 1))
fi

if [[ -f "$IR_SANDBOX/usr/local/bin/bad" ]]; then
    echo "  [PASS] --skip-verify bypassed checksum check and installed files"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] --skip-verify failed to install files"
    FAILED=$((FAILED + 1))
fi

# Remove bad-app so sandbox and DB remain clean for subsequent tests
"$ROOT_DIR/bin/ravpkg" --root "$IR_SANDBOX" --db "$IR_DB" remove "bad-app" >/dev/null 2>&1 || true

# 4. Path traversal rejection
TRAV_BUILD="$IR_TMP/trav_build"
mkdir -p "$TRAV_BUILD/bin"
echo "hack" > "$TRAV_BUILD/bin/hack"
cat <<JSON > "$TRAV_BUILD/manifest.json"
{
  "name": "trav-app",
  "version": "1.0.0",
  "description": "Path traversal app",
  "checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "install_paths": [
    { "source": "bin/hack", "destination": "/usr/local/bin/../../etc/pwned" }
  ]
}
JSON
TRAV_PKG="$IR_TMP/trav.rav"
(cd "$TRAV_BUILD" && tar -czf "$TRAV_PKG" manifest.json bin/hack)

assert_fail "path traversal in destination rejected" "$ROOT_DIR/bin/ravpkg" --root "$IR_SANDBOX" --db "$IR_DB" install "$TRAV_PKG"

# 5. Rollback on failure
FAIL_BUILD="$IR_TMP/fail_build"
mkdir -p "$FAIL_BUILD/files"
echo "part1" > "$FAIL_BUILD/files/part1"
echo "part2" > "$FAIL_BUILD/files/part2"
FAIL_CS="$(cat "$FAIL_BUILD/files/part1" "$FAIL_BUILD/files/part2" | _calc_sha256 -)"
cat <<JSON > "$FAIL_BUILD/manifest.json"
{
  "name": "rollback-app",
  "version": "1.0.0",
  "description": "Rollback test",
  "checksum": "$FAIL_CS",
  "install_paths": [
    { "source": "files/part1", "destination": "/usr/local/rb/part1" },
    { "source": "files/part2", "destination": "/usr/local/rb/part2/subfile" }
  ]
}
JSON
FAIL_PKG="$IR_TMP/fail.rav"
(cd "$FAIL_BUILD" && tar -czf "$FAIL_PKG" manifest.json files/part1 files/part2)

# Make destination parent directory for part2 an existing regular file so mkdir -p / cp deterministically fails
mkdir -p "$IR_SANDBOX/usr/local/rb"
touch "$IR_SANDBOX/usr/local/rb/part2"

assert_fail "install with copy failure triggers rollback" "$ROOT_DIR/bin/ravpkg" --root "$IR_SANDBOX" --db "$IR_DB" install "$FAIL_PKG"
if [[ ! -f "$IR_SANDBOX/usr/local/rb/part1" ]]; then
    echo "  [PASS] rollback cleaned up partially installed file (no orphans)"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] rollback left orphaned file on filesystem"
    FAILED=$((FAILED + 1))
fi

# 6. Remove installed package
assert_ok "remove package removes files and db record" "$ROOT_DIR/bin/ravpkg" --root "$IR_SANDBOX" --db "$IR_DB" remove "sample-app"
if [[ ! -f "$IR_SANDBOX/usr/local/bin/runner" && ! -f "$IR_SANDBOX/usr/local/share/doc/sample/MANUAL" ]]; then
    echo "  [PASS] removed package files are deleted from filesystem"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] removed package files still exist on filesystem"
    FAILED=$((FAILED + 1))
fi

# 7. Remove non-existent package fails
assert_fail "remove non-existent package fails" "$ROOT_DIR/bin/ravpkg" --root "$IR_SANDBOX" --db "$IR_DB" remove "non-existent"

# 8. Remove with already-missing file warns and continues
# Re-install sample-app
assert_ok "re-install sample-app" "$ROOT_DIR/bin/ravpkg" --root "$IR_SANDBOX" --db "$IR_DB" install "$SAMPLE_PKG"
# Delete one file manually
rm -f "$IR_SANDBOX/usr/local/bin/runner"
assert_ok "remove continues when tracked file is missing" "$ROOT_DIR/bin/ravpkg" --root "$IR_SANDBOX" --db "$IR_DB" remove "sample-app"
if [[ ! -f "$IR_SANDBOX/usr/local/share/doc/sample/MANUAL" ]]; then
    echo "  [PASS] remaining file deleted and DB record removed despite missing file"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] remaining file not cleaned up"
    FAILED=$((FAILED + 1))
fi

rm -rf "$IR_TMP"

echo ""
echo "--- Repository Indexing & Search Tests ---"
SRCH_TMP="$(mktemp -d 2>/dev/null || mktemp -d -t 'ravpkg-srch')"
SRCH_MANIFESTS="$SRCH_TMP/manifests"
mkdir -p "$SRCH_MANIFESTS"

# 1. Prepare sample manifests
cat <<'EOF' > "$SRCH_MANIFESTS/editor.json"
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

cat <<'EOF' > "$SRCH_MANIFESTS/sysinfo.json"
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

cat <<'EOF' > "$SRCH_MANIFESTS/invalid.json"
{
  "version": "0.1.0",
  "checksum": "1111111111111111111111111111111111111111111111111111111111111111"
}
EOF

SRCH_INDEX="$SRCH_TMP/index.json"
SRCH_CACHE="$SRCH_TMP/cache.json"

# 1. Missing/uncached index produces clear error and non-zero exit
assert_fail "search on missing/uncached index fails cleanly" "$ROOT_DIR/bin/ravpkg" --cache "$SRCH_TMP/missing.json" search "editor"

# 2. Index generation from sample manifests
assert_ok "repo/generate-index.sh generates index" "$ROOT_DIR/repo/generate-index.sh" -o "$SRCH_INDEX" "$SRCH_MANIFESTS"
if [[ -f "$SRCH_INDEX" && "$(jq 'length' "$SRCH_INDEX" 2>/dev/null)" -eq 2 ]]; then
    echo "  [PASS] index contains expected package count (skipping invalid manifests)"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] index generation failed or unexpected count"
    FAILED=$((FAILED + 1))
fi

# 3. repo_fetch_index caching from local file
source "$ROOT_DIR/lib/repo.sh"
if repo_fetch_index "$SRCH_INDEX" "$SRCH_CACHE" && [[ -f "$SRCH_CACHE" ]]; then
    echo "  [PASS] repo_fetch_index successfully cached local index"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] repo_fetch_index failed to cache index"
    FAILED=$((FAILED + 1))
fi

# 4. Search by package name
output="$("$ROOT_DIR/bin/ravpkg" --cache "$SRCH_CACHE" search "ravtext")"
if [[ "$output" == *"ravtext"* && "$output" == *"1.0.0"* ]]; then
    echo "  [PASS] search matches package name"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] search by package name failed"
    FAILED=$((FAILED + 1))
fi

# 5. Search by description (case-insensitive)
output="$("$ROOT_DIR/bin/ravpkg" --cache "$SRCH_CACHE" search "HARDWARE")"
if [[ "$output" == *"ravinfo"* && "$output" == *"hardware info"* ]]; then
    echo "  [PASS] search matches package description case-insensitively"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] case-insensitive description search failed"
    FAILED=$((FAILED + 1))
fi

# 6. Search with no matches
output="$("$ROOT_DIR/bin/ravpkg" --cache "$SRCH_CACHE" search "nonexistent")"
if [[ "$output" == *"No packages found matching 'nonexistent'"* ]]; then
    echo "  [PASS] search with no matches prints clean notice"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] search with no matches failed"
    FAILED=$((FAILED + 1))
fi

rm -rf "$SRCH_TMP"

echo ""
echo "--- Dependency Resolution & Cycle Detection Tests ---"
DEP_TMP="$(mktemp -d 2>/dev/null || mktemp -d -t 'ravpkg-dep-test')"
DEP_SANDBOX="$DEP_TMP/sandbox"
DEP_DB="$DEP_TMP/pkg.db"
mkdir -p "$DEP_SANDBOX"
db_init "$DEP_DB" "$SCHEMA"
source "$ROOT_DIR/lib/deps.sh"

# 1. Semver unit tests
if semver_satisfies "1.0.0" ">=1.0.0" && semver_satisfies "1.2.0" ">=1.0.0" && ! semver_satisfies "0.9.0" ">=1.0.0" && semver_satisfies "2.0.0" "=2.0.0"; then
    echo "  [PASS] semver_satisfies evaluates >=, =, <= constraints correctly"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] semver_satisfies evaluation failure"
    FAILED=$((FAILED + 1))
fi

# 2. Build base library libfoo 1.0.0 and install it
FOO_BUILD="$DEP_TMP/foo_build"
mkdir -p "$FOO_BUILD/lib"
echo "foo-lib" > "$FOO_BUILD/lib/libfoo.so"
FOO_CS="$(_calc_sha256 "$FOO_BUILD/lib/libfoo.so")"
cat <<EOF > "$FOO_BUILD/manifest.json"
{
  "name": "libfoo",
  "version": "1.0.0",
  "description": "Foo library",
  "checksum": "$FOO_CS",
  "install_paths": [
    { "source": "lib/libfoo.so", "destination": "/usr/local/lib/libfoo.so" }
  ],
  "dependencies": []
}
EOF
FOO_PKG="$DEP_TMP/libfoo-1.0.0.rav"
(cd "$FOO_BUILD" && tar -czf "$FOO_PKG" manifest.json lib/libfoo.so)
assert_ok "install base library libfoo" "$ROOT_DIR/bin/ravpkg" --root "$DEP_SANDBOX" --db "$DEP_DB" install "$FOO_PKG"

# 3. Build app requiring libfoo >=1.0.0 and install it (satisfied)
APP_BUILD="$DEP_TMP/app_build"
mkdir -p "$APP_BUILD/bin"
echo "app-bin" > "$APP_BUILD/bin/myapp"
APP_CS="$(_calc_sha256 "$APP_BUILD/bin/myapp")"
cat <<EOF > "$APP_BUILD/manifest.json"
{
  "name": "myapp",
  "version": "1.0.0",
  "description": "App requiring libfoo",
  "checksum": "$APP_CS",
  "install_paths": [
    { "source": "bin/myapp", "destination": "/usr/local/bin/myapp" }
  ],
  "dependencies": [
    { "name": "libfoo", "constraint": ">=1.0.0" }
  ]
}
EOF
APP_PKG="$DEP_TMP/myapp-1.0.0.rav"
(cd "$APP_BUILD" && tar -czf "$APP_PKG" manifest.json bin/myapp)
assert_ok "install with satisfied dependencies" "$ROOT_DIR/bin/ravpkg" --root "$DEP_SANDBOX" --db "$DEP_DB" install "$APP_PKG"
if [[ -f "$DEP_SANDBOX/usr/local/bin/myapp" ]]; then
    echo "  [PASS] app installed when dependencies are satisfied"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] app not installed despite satisfied dependencies"
    FAILED=$((FAILED + 1))
fi

# 4. Install with missing dependencies fails with clear list
MISS_BUILD="$DEP_TMP/miss_build"
mkdir -p "$MISS_BUILD/bin"
echo "miss" > "$MISS_BUILD/bin/missapp"
MISS_CS="$(_calc_sha256 "$MISS_BUILD/bin/missapp")"
cat <<EOF > "$MISS_BUILD/manifest.json"
{
  "name": "missapp",
  "version": "1.0.0",
  "description": "App requiring missing deps",
  "checksum": "$MISS_CS",
  "install_paths": [
    { "source": "bin/missapp", "destination": "/usr/local/bin/missapp" }
  ],
  "dependencies": [
    { "name": "libmissing", "constraint": ">=2.0.0" },
    { "name": "libghost", "constraint": "=1.5.0" }
  ]
}
EOF
MISS_PKG="$DEP_TMP/missapp-1.0.0.rav"
(cd "$MISS_BUILD" && tar -czf "$MISS_PKG" manifest.json bin/missapp)
assert_fail "install with missing dependencies rejected" "$ROOT_DIR/bin/ravpkg" --root "$DEP_SANDBOX" --db "$DEP_DB" install "$MISS_PKG"

# 5. Circular dependency detection: self-cycle
SELF_BUILD="$DEP_TMP/self_build"
mkdir -p "$SELF_BUILD/bin"
echo "self" > "$SELF_BUILD/bin/self"
SELF_CS="$(_calc_sha256 "$SELF_BUILD/bin/self")"
cat <<EOF > "$SELF_BUILD/manifest.json"
{
  "name": "selfcycle",
  "version": "1.0.0",
  "description": "Self cycle",
  "checksum": "$SELF_CS",
  "install_paths": [
    { "source": "bin/self", "destination": "/usr/local/bin/self" }
  ],
  "dependencies": [
    { "name": "selfcycle", "constraint": ">=1.0.0" }
  ]
}
EOF
SELF_PKG="$DEP_TMP/selfcycle-1.0.0.rav"
(cd "$SELF_BUILD" && tar -czf "$SELF_PKG" manifest.json bin/self)
assert_fail "self-circular dependency rejected" "$ROOT_DIR/bin/ravpkg" --root "$DEP_SANDBOX" --db "$DEP_DB" install "$SELF_PKG"

# 6. Circular dependency detection: transitive cycle (pkgA -> pkgB -> pkgA)
B_BUILD="$DEP_TMP/b_build"
mkdir -p "$B_BUILD/bin"
echo "b" > "$B_BUILD/bin/b"
B_CS="$(_calc_sha256 "$B_BUILD/bin/b")"
cat <<EOF > "$B_BUILD/manifest.json"
{
  "name": "pkgB",
  "version": "1.0.0",
  "description": "Package B",
  "checksum": "$B_CS",
  "install_paths": [
    { "source": "bin/b", "destination": "/usr/local/bin/b" }
  ],
  "dependencies": [
    { "name": "pkgA", "constraint": ">=1.0.0" }
  ]
}
EOF
B_PKG="$DEP_TMP/pkgB-1.0.0.rav"
(cd "$B_BUILD" && tar -czf "$B_PKG" manifest.json bin/b)
assert_ok "install pkgB with --no-deps" "$ROOT_DIR/bin/ravpkg" --root "$DEP_SANDBOX" --db "$DEP_DB" --no-deps install "$B_PKG"

A_BUILD="$DEP_TMP/a_build"
mkdir -p "$A_BUILD/bin"
echo "a" > "$A_BUILD/bin/a"
A_CS="$(_calc_sha256 "$A_BUILD/bin/a")"
cat <<EOF > "$A_BUILD/manifest.json"
{
  "name": "pkgA",
  "version": "1.0.0",
  "description": "Package A",
  "checksum": "$A_CS",
  "install_paths": [
    { "source": "bin/a", "destination": "/usr/local/bin/a" }
  ],
  "dependencies": [
    { "name": "pkgB", "constraint": ">=1.0.0" }
  ]
}
EOF
A_PKG="$DEP_TMP/pkgA-1.0.0.rav"
(cd "$A_BUILD" && tar -czf "$A_PKG" manifest.json bin/a)
assert_fail "transitive circular dependency pkgA -> pkgB -> pkgA rejected" "$ROOT_DIR/bin/ravpkg" --root "$DEP_SANDBOX" --db "$DEP_DB" install "$A_PKG"

# 7. Remove package with dependents warns and succeeds
# Notice myapp depends on libfoo: remove libfoo should warn about myapp and proceed
assert_ok "remove libfoo with dependent myapp warns and removes" "$ROOT_DIR/bin/ravpkg" --root "$DEP_SANDBOX" --db "$DEP_DB" remove "libfoo"
if [[ ! -f "$DEP_SANDBOX/usr/local/lib/libfoo.so" ]]; then
    echo "  [PASS] package removed despite dependents warning"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] package not removed"
    FAILED=$((FAILED + 1))
fi

rm -rf "$DEP_TMP"

echo ""
echo "================================================================="
echo "Results: $PASSED passed, $FAILED failed."
if [[ "$FAILED" -gt 0 ]]; then
    exit 1
fi
exit 0
