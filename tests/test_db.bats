#!/usr/bin/env bats
# tests/test_db.bats - SQLite CRUD tests for ravpkg

setup() {
    DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    LIB_DIR="$(dirname "$DIR")/lib"
    SCHEMA_FILE="$(dirname "$DIR")/schema/schema.sql"
    source "$LIB_DIR/db.sh"

    TEST_TEMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'ravpkg-test')"
    TEST_DB="$TEST_TEMP_DIR/test.db"
    db_init "$TEST_DB" "$SCHEMA_FILE"
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

@test "db: table initialized successfully" {
    count="$(sqlite3 "$TEST_DB" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='installed_packages';")"
    [ "$count" -eq 1 ]
}

@test "db: add and get package" {
    files='["/usr/local/bin/ravterm","/usr/local/share/man/man1/ravterm.1"]'
    db_add_package "$TEST_DB" "ravterm" "1.0.0" "2026-09-10T12:00:00Z" "/var/db/ravpkg/manifests/ravterm.json" "$files"

    run db_get_package "$TEST_DB" "ravterm"
    [ "$status" -eq 0 ]

    name="$(echo "$output" | jq -r '.name')"
    version="$(echo "$output" | jq -r '.version')"
    date="$(echo "$output" | jq -r '.install_date')"
    manifest="$(echo "$output" | jq -r '.manifest_path')"
    out_files="$(echo "$output" | jq -r '.installed_files')"

    [ "$name" = "ravterm" ]
    [ "$version" = "1.0.0" ]
    [ "$date" = "2026-09-10T12:00:00Z" ]
    [ "$manifest" = "/var/db/ravpkg/manifests/ravterm.json" ]
    [ "$out_files" = "$files" ]
}

@test "db: get package not found returns error" {
    run db_get_package "$TEST_DB" "nonexistent"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "package not found in local database" ]]
}

@test "db: list packages returns empty on blank db" {
    run db_list_packages "$TEST_DB"
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "db: list packages returns alphabetical order" {
    db_add_package "$TEST_DB" "pkg-b" "2.0.0" "2026-01-01T00:00:00Z" "/path/b" '["/bin/b"]'
    db_add_package "$TEST_DB" "pkg-a" "1.0.0" "2026-01-01T00:00:00Z" "/path/a" '["/bin/a"]'

    run db_list_packages "$TEST_DB"
    [ "$status" -eq 0 ]

    first_pkg="$(echo "$output" | jq -r '.[0].name')"
    second_pkg="$(echo "$output" | jq -r '.[1].name')"

    [ "$first_pkg" = "pkg-a" ]
    [ "$second_pkg" = "pkg-b" ]
}

@test "db: remove package deletes successfully" {
    db_add_package "$TEST_DB" "pkg-to-remove" "1.0.0" "2026-01-01T00:00:00Z" "/path" '[]'

    run db_remove_package "$TEST_DB" "pkg-to-remove"
    [ "$status" -eq 0 ]

    run db_get_package "$TEST_DB" "pkg-to-remove"
    [ "$status" -ne 0 ]
}

@test "db: remove non-existent package returns error" {
    run db_remove_package "$TEST_DB" "never-existed"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "package not found in local database" ]]
}
