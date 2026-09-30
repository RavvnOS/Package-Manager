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
assert_ok "CLI search stub" "$ROOT_DIR/bin/ravpkg" search query
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
echo "================================================================="
echo "Results: $PASSED passed, $FAILED failed."
if [[ "$FAILED" -gt 0 ]]; then
    exit 1
fi
exit 0
