#!/usr/bin/env bats
# tests/test_deps.bats - Unit and integration tests for dependency resolution and cycles

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    ROOT_DIR="$TEST_DIR"
    TEST_TMP="$(mktemp -d 2>/dev/null || mktemp -d -t 'ravpkg-deps-test')"
    export PATH="$TEST_DIR/bin:$PATH"

    SANDBOX="$TEST_TMP/sandbox"
    TEST_DB="$TEST_TMP/pkg.db"
    SCHEMA_FILE="$TEST_DIR/schema/schema.sql"
    mkdir -p "$SANDBOX"

    # Source libraries
    source "$TEST_DIR/lib/db.sh"
    source "$TEST_DIR/lib/parser.sh"
    source "$TEST_DIR/lib/deps.sh"
    source "$TEST_DIR/lib/install.sh"
    source "$TEST_DIR/lib/remove.sh"

    db_init "$TEST_DB" "$SCHEMA_FILE"
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "deps: semver comparison and constraint evaluation" {
    run semver_satisfies "1.0.0" ">=1.0.0"
    [ "$status" -eq 0 ]

    run semver_satisfies "1.2.0" ">=1.0.0"
    [ "$status" -eq 0 ]

    run semver_satisfies "0.9.0" ">=1.0.0"
    [ "$status" -ne 0 ]

    run semver_satisfies "2.0.0" "<=2.0.0"
    [ "$status" -eq 0 ]

    run semver_satisfies "2.0.1" "<=2.0.0"
    [ "$status" -ne 0 ]

    run semver_satisfies "3.0.0" "=3.0.0"
    [ "$status" -eq 0 ]

    run semver_satisfies "3.0.1" "=3.0.0"
    [ "$status" -ne 0 ]

    run semver_satisfies "1.5.0" "*"
    [ "$status" -eq 0 ]
}

@test "deps: install with satisfied dependencies succeeds" {
    # 1. Build and install base library libfoo 1.0.0
    FOO_BUILD="$TEST_TMP/foo_build"
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
    FOO_PKG="$TEST_TMP/libfoo-1.0.0.rav"
    (cd "$FOO_BUILD" && tar -czf "$FOO_PKG" manifest.json lib/libfoo.so)

    export RAVPKG_ROOT="$SANDBOX"
    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$TEST_DB" install "$FOO_PKG"
    [ "$status" -eq 0 ]

    # 2. Build app depending on libfoo >=1.0.0
    APP_BUILD="$TEST_TMP/app_build"
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
    APP_PKG="$TEST_TMP/myapp-1.0.0.rav"
    (cd "$APP_BUILD" && tar -czf "$APP_PKG" manifest.json bin/myapp)

    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$TEST_DB" install "$APP_PKG"
    [ "$status" -eq 0 ]
    [ -f "$SANDBOX/usr/local/bin/myapp" ]
}

@test "deps: install with missing dependencies rejected with clear list" {
    APP_BUILD="$TEST_TMP/missing_app_build"
    mkdir -p "$APP_BUILD/bin"
    echo "missing-bin" > "$APP_BUILD/bin/missapp"
    APP_CS="$(_calc_sha256 "$APP_BUILD/bin/missapp")"
    cat <<EOF > "$APP_BUILD/manifest.json"
{
  "name": "missapp",
  "version": "1.0.0",
  "description": "App requiring missing deps",
  "checksum": "$APP_CS",
  "install_paths": [
    { "source": "bin/missapp", "destination": "/usr/local/bin/missapp" }
  ],
  "dependencies": [
    { "name": "libmissing", "constraint": ">=2.0.0" },
    { "name": "libghost", "constraint": "=1.5.0" }
  ]
}
EOF
    APP_PKG="$TEST_TMP/missapp-1.0.0.rav"
    (cd "$APP_BUILD" && tar -czf "$APP_PKG" manifest.json bin/missapp)

    export RAVPKG_ROOT="$SANDBOX"
    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$TEST_DB" install "$APP_PKG"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "unsatisfied dependencies" ]]
    [[ "$output" =~ "libmissing" ]]
    [[ "$output" =~ "libghost" ]]
    [ ! -f "$SANDBOX/usr/local/bin/missapp" ]
}

@test "deps: circular dependency detected and rejected" {
    # 1. Test direct self-dependency (A -> A)
    SELF_BUILD="$TEST_TMP/self_build"
    mkdir -p "$SELF_BUILD/bin"
    echo "self" > "$SELF_BUILD/bin/self"
    SELF_CS="$(_calc_sha256 "$SELF_BUILD/bin/self")"
    cat <<EOF > "$SELF_BUILD/manifest.json"
{
  "name": "selfcycle",
  "version": "1.0.0",
  "description": "Self-referencing package",
  "checksum": "$SELF_CS",
  "install_paths": [
    { "source": "bin/self", "destination": "/usr/local/bin/self" }
  ],
  "dependencies": [
    { "name": "selfcycle", "constraint": ">=1.0.0" }
  ]
}
EOF
    SELF_PKG="$TEST_TMP/selfcycle-1.0.0.rav"
    (cd "$SELF_BUILD" && tar -czf "$SELF_PKG" manifest.json bin/self)

    export RAVPKG_ROOT="$SANDBOX"
    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$TEST_DB" install "$SELF_PKG"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "circular dependency detected" ]]

    # 2. Test transitive cycle (pkgA -> pkgB -> pkgA)
    # Install pkgB with dependency on pkgA (using --no-deps to stage the situation)
    B_BUILD="$TEST_TMP/b_build"
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
    B_PKG="$TEST_TMP/pkgB-1.0.0.rav"
    (cd "$B_BUILD" && tar -czf "$B_PKG" manifest.json bin/b)
    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$TEST_DB" --no-deps install "$B_PKG"
    [ "$status" -eq 0 ]

    # Now attempt to install pkgA which depends on pkgB
    A_BUILD="$TEST_TMP/a_build"
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
    A_PKG="$TEST_TMP/pkgA-1.0.0.rav"
    (cd "$A_BUILD" && tar -czf "$A_PKG" manifest.json bin/a)

    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$TEST_DB" install "$A_PKG"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "circular dependency detected" ]]
    [[ "$output" =~ "pkgA -> pkgB -> pkgA" ]]
}

@test "deps: remove package with dependents displays warning and proceeds" {
    export RAVPKG_ROOT="$SANDBOX"

    # Install base libbar
    BAR_BUILD="$TEST_TMP/bar_build"
    mkdir -p "$BAR_BUILD/lib"
    echo "bar" > "$BAR_BUILD/lib/libbar.so"
    BAR_CS="$(_calc_sha256 "$BAR_BUILD/lib/libbar.so")"
    cat <<EOF > "$BAR_BUILD/manifest.json"
{
  "name": "libbar",
  "version": "1.0.0",
  "description": "Bar library",
  "checksum": "$BAR_CS",
  "install_paths": [
    { "source": "lib/libbar.so", "destination": "/usr/local/lib/libbar.so" }
  ],
  "dependencies": []
}
EOF
    BAR_PKG="$TEST_TMP/libbar-1.0.0.rav"
    (cd "$BAR_BUILD" && tar -czf "$BAR_PKG" manifest.json lib/libbar.so)
    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$TEST_DB" install "$BAR_PKG"
    [ "$status" -eq 0 ]

    # Install client app depending on libbar
    CLI_BUILD="$TEST_TMP/cli_build"
    mkdir -p "$CLI_BUILD/bin"
    echo "client" > "$CLI_BUILD/bin/client"
    CLI_CS="$(_calc_sha256 "$CLI_BUILD/bin/client")"
    cat <<EOF > "$CLI_BUILD/manifest.json"
{
  "name": "clientapp",
  "version": "1.0.0",
  "description": "Client app",
  "checksum": "$CLI_CS",
  "install_paths": [
    { "source": "bin/client", "destination": "/usr/local/bin/client" }
  ],
  "dependencies": [
    { "name": "libbar", "constraint": ">=1.0.0" }
  ]
}
EOF
    CLI_PKG="$TEST_TMP/clientapp-1.0.0.rav"
    (cd "$CLI_BUILD" && tar -czf "$CLI_PKG" manifest.json bin/client)
    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$TEST_DB" install "$CLI_PKG"
    [ "$status" -eq 0 ]

    # Now remove libbar: warning should be shown, but removal must succeed
    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$TEST_DB" remove "libbar"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Warning: the following installed package(s) depend on 'libbar'" ]]
    [[ "$output" =~ "clientapp" ]]
    [[ "$output" =~ "Successfully removed: libbar" ]]
    [ ! -f "$SANDBOX/usr/local/lib/libbar.so" ]
}
