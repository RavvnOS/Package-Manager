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
echo "--- CLI Command Routing Tests ---"
CLI_DB="$ROOT_DIR/cli_test.db"
rm -f "$CLI_DB"

assert_ok "CLI --help displays help text" "$ROOT_DIR/bin/ravpkg" --help
assert_ok "CLI list on empty database" "$ROOT_DIR/bin/ravpkg" --db "$CLI_DB" list
assert_ok "CLI install stub" "$ROOT_DIR/bin/ravpkg" install test.rav
assert_ok "CLI remove stub" "$ROOT_DIR/bin/ravpkg" remove testpkg
assert_ok "CLI search stub" "$ROOT_DIR/bin/ravpkg" search query
assert_fail "CLI info on non-existent package fails" "$ROOT_DIR/bin/ravpkg" --db "$CLI_DB" info notinstalled

# Test CLI list and info with actual inserted package
db_init "$CLI_DB" "$SCHEMA"
db_add_package "$CLI_DB" "demo-pkg" "1.2.3" "2026-10-01T01:00:00Z" "/path/demo.json" '["/usr/bin/demo"]'
assert_ok "CLI list with installed package" "$ROOT_DIR/bin/ravpkg" --db "$CLI_DB" list
assert_ok "CLI info with installed package" "$ROOT_DIR/bin/ravpkg" --db "$CLI_DB" info demo-pkg

rm -f "$CLI_DB"

echo ""
echo "================================================================="
echo "Results: $PASSED passed, $FAILED failed."
if [[ "$FAILED" -gt 0 ]]; then
    exit 1
fi
exit 0
