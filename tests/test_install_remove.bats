#!/usr/bin/env bats
# tests/test_install_remove.bats - Unit and integration tests for install/remove logic

setup() {
    DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    ROOT_DIR="$(dirname "$DIR")"
    LIB_DIR="$ROOT_DIR/lib"
    SCHEMA_FILE="$ROOT_DIR/schema/schema.sql"

    source "$LIB_DIR/parser.sh"
    source "$LIB_DIR/db.sh"
    source "$LIB_DIR/install.sh"
    source "$LIB_DIR/remove.sh"

    TEST_TMP="$(mktemp -d 2>/dev/null || mktemp -d -t 'ravpkg-test-ir')"
    SANDBOX="$TEST_TMP/sandbox"
    mkdir -p "$SANDBOX"

    TEST_DB="$TEST_TMP/test.db"
    db_init "$TEST_DB" "$SCHEMA_FILE"

    PKG_DIR="$TEST_TMP/build_pkg"
    mkdir -p "$PKG_DIR/bin" "$PKG_DIR/share/doc"
    echo "#!/bin/sh" > "$PKG_DIR/bin/hello"
    echo "echo Hello" >> "$PKG_DIR/bin/hello"
    echo "Hello documentation" > "$PKG_DIR/share/doc/README"

    # Compute checksum of payload stream (all files excluding manifest.json)
    # Using tar to package files
    cd "$PKG_DIR"
    PAYLOAD_CS="$(cat bin/hello share/doc/README | _calc_sha256 -)"

    cat <<JSON > "$PKG_DIR/manifest.json"
{
  "name": "hello-tool",
  "version": "1.0.0",
  "description": "A sample hello tool",
  "checksum": "$PAYLOAD_CS",
  "install_paths": [
    { "source": "bin/hello", "destination": "/usr/local/bin/hello" },
    { "source": "share/doc/README", "destination": "/usr/local/share/doc/hello/README" }
  ]
}
JSON

    VALID_PKG="$TEST_TMP/hello-tool-1.0.0.rav"
    tar -czf "$VALID_PKG" manifest.json bin/hello share/doc/README
    cd "$DIR"
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "install: successful install creates files and db record" {
    export RAVPKG_ROOT="$SANDBOX"
    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$TEST_DB" install "$VALID_PKG"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Successfully installed: hello-tool 1.0.0" ]]

    # Verify files exist in sandbox
    [ -f "$SANDBOX/usr/local/bin/hello" ]
    [ -f "$SANDBOX/usr/local/share/doc/hello/README" ]

    # Verify db record
    run db_get_package "$TEST_DB" "hello-tool"
    [ "$status" -eq 0 ]
    name="$(echo "$output" | jq -r '.name')"
    [ "$name" = "hello-tool" ]
}

@test "install: bad checksum rejected, nothing written" {
    BAD_PKG="$TEST_TMP/bad-checksum.rav"
    BAD_DIR="$TEST_TMP/bad_build"
    mkdir -p "$BAD_DIR/bin"
    echo "bad" > "$BAD_DIR/bin/bad"
    cat <<JSON > "$BAD_DIR/manifest.json"
{
  "name": "bad-tool",
  "version": "1.0.0",
  "description": "Bad tool",
  "checksum": "0000000000000000000000000000000000000000000000000000000000000000",
  "install_paths": [
    { "source": "bin/bad", "destination": "/usr/local/bin/bad" }
  ]
}
JSON
    (cd "$BAD_DIR" && tar -czf "$BAD_PKG" manifest.json bin/bad)

    export RAVPKG_ROOT="$SANDBOX"
    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$TEST_DB" install "$BAD_PKG"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "checksum mismatch" ]]

    # Verify nothing was written to filesystem
    [ ! -f "$SANDBOX/usr/local/bin/bad" ]

    # Verify nothing written to DB
    run db_get_package "$TEST_DB" "bad-tool"
    [ "$status" -ne 0 ]
}

@test "install: reject when already installed" {
    export RAVPKG_ROOT="$SANDBOX"
    # First install
    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$TEST_DB" install "$VALID_PKG"
    [ "$status" -eq 0 ]

    # Second install attempt should fail
    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$TEST_DB" install "$VALID_PKG"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "already installed" ]]
}

@test "install: reject path traversal in destination" {
    TRAVERSAL_PKG="$TEST_TMP/traversal.rav"
    T_DIR="$TEST_TMP/traversal_build"
    mkdir -p "$T_DIR/bin"
    echo "evil" > "$T_DIR/bin/evil"
    cat <<JSON > "$T_DIR/manifest.json"
{
  "name": "evil-tool",
  "version": "1.0.0",
  "description": "Evil tool",
  "checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "install_paths": [
    { "source": "bin/evil", "destination": "/usr/local/bin/../../etc/shadow" }
  ]
}
JSON
    (cd "$T_DIR" && tar -czf "$TRAVERSAL_PKG" manifest.json bin/evil)

    export RAVPKG_ROOT="$SANDBOX"
    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$TEST_DB" install "$TRAVERSAL_PKG"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "path traversal" ]]
}

@test "install: partial failure triggers rollback (no orphaned files)" {
    FAIL_PKG="$TEST_TMP/fail.rav"
    F_DIR="$TEST_TMP/fail_build"
    mkdir -p "$F_DIR/files"
    echo "one" > "$F_DIR/files/file1"
    echo "two" > "$F_DIR/files/file2"
    
    # Calculate checksum for payload
    CS="$(cat "$F_DIR/files/file1" "$F_DIR/files/file2" | _calc_sha256 -)"

    cat <<JSON > "$F_DIR/manifest.json"
{
  "name": "fail-tool",
  "version": "1.0.0",
  "description": "Fail tool",
  "checksum": "$CS",
  "install_paths": [
    { "source": "files/file1", "destination": "/usr/local/test/file1" },
    { "source": "files/file2", "destination": "/usr/local/test/file2/subfile" }
  ]
}
JSON
    (cd "$F_DIR" && tar -czf "$FAIL_PKG" manifest.json files/file1 files/file2)

    # Make destination parent directory for file2 an existing regular file so mkdir -p / cp deterministically fails
    mkdir -p "$SANDBOX/usr/local/test"
    touch "$SANDBOX/usr/local/test/file2"

    export RAVPKG_ROOT="$SANDBOX"
    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$TEST_DB" install "$FAIL_PKG"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "ROLLBACK" ]]

    # Verify file1 was rolled back and deleted
    [ ! -f "$SANDBOX/usr/local/test/file1" ]

    # Verify DB record was NOT created
    run db_get_package "$TEST_DB" "fail-tool"
    [ "$status" -ne 0 ]
}

@test "remove: successfully removes files and db record" {
    export RAVPKG_ROOT="$SANDBOX"
    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$TEST_DB" install "$VALID_PKG"
    [ "$status" -eq 0 ]
    [ -f "$SANDBOX/usr/local/bin/hello" ]

    # Remove package
    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$TEST_DB" remove "hello-tool"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Successfully removed: hello-tool" ]]

    # Verify files deleted
    [ ! -f "$SANDBOX/usr/local/bin/hello" ]
    [ ! -f "$SANDBOX/usr/local/share/doc/hello/README" ]

    # Verify DB record gone
    run db_get_package "$TEST_DB" "hello-tool"
    [ "$status" -ne 0 ]
}

@test "remove: non-existent package fails clearly" {
    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$TEST_DB" remove "non-existent"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "is not installed" ]]
}

@test "remove: continues and warns when a tracked file is already missing" {
    export RAVPKG_ROOT="$SANDBOX"
    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$TEST_DB" install "$VALID_PKG"
    [ "$status" -eq 0 ]

    # Intentionally delete one of the installed files manually
    rm -f "$SANDBOX/usr/local/bin/hello"

    # Remove should succeed, warning about missing file
    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$TEST_DB" remove "hello-tool"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Warning: tracked file does not exist" ]]
    [[ "$output" =~ "1 missing file(s) skipped" ]]

    # Remaining file should be deleted
    [ ! -f "$SANDBOX/usr/local/share/doc/hello/README" ]

    # DB record should be removed
    run db_get_package "$TEST_DB" "hello-tool"
    [ "$status" -ne 0 ]
}
