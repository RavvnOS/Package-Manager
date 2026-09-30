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

@test "deps: simple chain automatically resolves and installs in dependency order (A -> B -> C)" {
    INDEX_FILE="$TEST_TMP/chain_index.json"
    CACHE_FILE="$TEST_TMP/chain_cache.json"

    # Package C
    C_BUILD="$TEST_TMP/c_build"
    mkdir -p "$C_BUILD/bin"
    echo "bin-c" > "$C_BUILD/bin/c"
    C_CS="$(cat "$C_BUILD/bin/c" | _calc_sha256 -)"
    cat <<EOF > "$C_BUILD/manifest.json"
{
  "name": "chainC",
  "version": "1.0.0",
  "description": "Chain C",
  "checksum": "$C_CS",
  "install_paths": [
    { "source": "bin/c", "destination": "/usr/local/bin/c" }
  ],
  "dependencies": []
}
EOF
    C_PKG="$TEST_TMP/chainC-1.0.0.rav"
    (cd "$C_BUILD" && tar -czf "$C_PKG" manifest.json bin/c)

    # Package B (depends on C)
    B_BUILD="$TEST_TMP/b_build"
    mkdir -p "$B_BUILD/bin"
    echo "bin-b" > "$B_BUILD/bin/b"
    B_CS="$(cat "$B_BUILD/bin/b" | _calc_sha256 -)"
    cat <<EOF > "$B_BUILD/manifest.json"
{
  "name": "chainB",
  "version": "1.0.0",
  "description": "Chain B",
  "checksum": "$B_CS",
  "install_paths": [
    { "source": "bin/b", "destination": "/usr/local/bin/b" }
  ],
  "dependencies": [
    { "name": "chainC", "constraint": ">=1.0.0" }
  ]
}
EOF
    B_PKG="$TEST_TMP/chainB-1.0.0.rav"
    (cd "$B_BUILD" && tar -czf "$B_PKG" manifest.json bin/b)

    # Package A (depends on B)
    A_BUILD="$TEST_TMP/a_build"
    mkdir -p "$A_BUILD/bin"
    echo "bin-a" > "$A_BUILD/bin/a"
    A_CS="$(cat "$A_BUILD/bin/a" | _calc_sha256 -)"
    cat <<EOF > "$A_BUILD/manifest.json"
{
  "name": "chainA",
  "version": "1.0.0",
  "description": "Chain A",
  "checksum": "$A_CS",
  "install_paths": [
    { "source": "bin/a", "destination": "/usr/local/bin/a" }
  ],
  "dependencies": [
    { "name": "chainB", "constraint": ">=1.0.0" }
  ]
}
EOF
    A_PKG="$TEST_TMP/chainA-1.0.0.rav"
    (cd "$A_BUILD" && tar -czf "$A_PKG" manifest.json bin/a)

    cat <<EOF > "$INDEX_FILE"
[
  {
    "name": "chainC",
    "version": "1.0.0",
    "description": "Chain C",
    "download_url": "file://$C_PKG",
    "checksum": "$C_CS",
    "dependencies": []
  },
  {
    "name": "chainB",
    "version": "1.0.0",
    "description": "Chain B",
    "download_url": "file://$B_PKG",
    "checksum": "$B_CS",
    "dependencies": [
      { "name": "chainC", "constraint": ">=1.0.0" }
    ]
  },
  {
    "name": "chainA",
    "version": "1.0.0",
    "description": "Chain A",
    "download_url": "file://$A_PKG",
    "checksum": "$A_CS",
    "dependencies": [
      { "name": "chainB", "constraint": ">=1.0.0" }
    ]
  }
]
EOF

    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$TEST_DB" --repo "$INDEX_FILE" --cache "$CACHE_FILE" --no-cache -y install chainA
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Transaction Summary" ]]
    [[ "$output" =~ "Total packages to install: 3" ]]

    # Verify all 3 files installed
    [ -f "$SANDBOX/usr/local/bin/c" ]
    [ -f "$SANDBOX/usr/local/bin/b" ]
    [ -f "$SANDBOX/usr/local/bin/a" ]

    # Verify all 3 recorded in DB
    run db_get_package "$TEST_DB" "chainC"
    [ "$status" -eq 0 ]
    run db_get_package "$TEST_DB" "chainB"
    [ "$status" -eq 0 ]
    run db_get_package "$TEST_DB" "chainA"
    [ "$status" -eq 0 ]
}

@test "deps: diamond dependency installs shared dependency exactly once" {
    INDEX_FILE="$TEST_TMP/diam_index.json"
    CACHE_FILE="$TEST_TMP/diam_cache.json"

    # Base
    DBASE_BUILD="$TEST_TMP/dbase_build"
    mkdir -p "$DBASE_BUILD/bin"
    echo "dbase" > "$DBASE_BUILD/bin/dbase"
    DBASE_CS="$(cat "$DBASE_BUILD/bin/dbase" | _calc_sha256 -)"
    cat <<EOF > "$DBASE_BUILD/manifest.json"
{
  "name": "diamBase",
  "version": "1.0.0",
  "description": "Diamond Base",
  "checksum": "$DBASE_CS",
  "install_paths": [
    { "source": "bin/dbase", "destination": "/usr/local/bin/dbase" }
  ],
  "dependencies": []
}
EOF
    DBASE_PKG="$TEST_TMP/diamBase-1.0.0.rav"
    (cd "$DBASE_BUILD" && tar -czf "$DBASE_PKG" manifest.json bin/dbase)

    # Left (depends on Base)
    DLEFT_BUILD="$TEST_TMP/dleft_build"
    mkdir -p "$DLEFT_BUILD/bin"
    echo "dleft" > "$DLEFT_BUILD/bin/dleft"
    DLEFT_CS="$(cat "$DLEFT_BUILD/bin/dleft" | _calc_sha256 -)"
    cat <<EOF > "$DLEFT_BUILD/manifest.json"
{
  "name": "diamLeft",
  "version": "1.0.0",
  "description": "Diamond Left",
  "checksum": "$DLEFT_CS",
  "install_paths": [
    { "source": "bin/dleft", "destination": "/usr/local/bin/dleft" }
  ],
  "dependencies": [
    { "name": "diamBase", "constraint": ">=1.0.0" }
  ]
}
EOF
    DLEFT_PKG="$TEST_TMP/diamLeft-1.0.0.rav"
    (cd "$DLEFT_BUILD" && tar -czf "$DLEFT_PKG" manifest.json bin/dleft)

    # Right (depends on Base)
    DRIGHT_BUILD="$TEST_TMP/dright_build"
    mkdir -p "$DRIGHT_BUILD/bin"
    echo "dright" > "$DRIGHT_BUILD/bin/dright"
    DRIGHT_CS="$(cat "$DRIGHT_BUILD/bin/dright" | _calc_sha256 -)"
    cat <<EOF > "$DRIGHT_BUILD/manifest.json"
{
  "name": "diamRight",
  "version": "1.0.0",
  "description": "Diamond Right",
  "checksum": "$DRIGHT_CS",
  "install_paths": [
    { "source": "bin/dright", "destination": "/usr/local/bin/dright" }
  ],
  "dependencies": [
    { "name": "diamBase", "constraint": ">=1.0.0" }
  ]
}
EOF
    DRIGHT_PKG="$TEST_TMP/diamRight-1.0.0.rav"
    (cd "$DRIGHT_BUILD" && tar -czf "$DRIGHT_PKG" manifest.json bin/dright)

    # Top (depends on Left and Right)
    DTOP_BUILD="$TEST_TMP/dtop_build"
    mkdir -p "$DTOP_BUILD/bin"
    echo "dtop" > "$DTOP_BUILD/bin/dtop"
    DTOP_CS="$(cat "$DTOP_BUILD/bin/dtop" | _calc_sha256 -)"
    cat <<EOF > "$DTOP_BUILD/manifest.json"
{
  "name": "diamTop",
  "version": "1.0.0",
  "description": "Diamond Top",
  "checksum": "$DTOP_CS",
  "install_paths": [
    { "source": "bin/dtop", "destination": "/usr/local/bin/dtop" }
  ],
  "dependencies": [
    { "name": "diamLeft", "constraint": ">=1.0.0" },
    { "name": "diamRight", "constraint": ">=1.0.0" }
  ]
}
EOF
    DTOP_PKG="$TEST_TMP/diamTop-1.0.0.rav"
    (cd "$DTOP_BUILD" && tar -czf "$DTOP_PKG" manifest.json bin/dtop)

    cat <<EOF > "$INDEX_FILE"
[
  {
    "name": "diamBase",
    "version": "1.0.0",
    "description": "Diamond Base",
    "download_url": "file://$DBASE_PKG",
    "checksum": "$DBASE_CS",
    "dependencies": []
  },
  {
    "name": "diamLeft",
    "version": "1.0.0",
    "description": "Diamond Left",
    "download_url": "file://$DLEFT_PKG",
    "checksum": "$DLEFT_CS",
    "dependencies": [
      { "name": "diamBase", "constraint": ">=1.0.0" }
    ]
  },
  {
    "name": "diamRight",
    "version": "1.0.0",
    "description": "Diamond Right",
    "download_url": "file://$DRIGHT_PKG",
    "checksum": "$DRIGHT_CS",
    "dependencies": [
      { "name": "diamBase", "constraint": ">=1.0.0" }
    ]
  },
  {
    "name": "diamTop",
    "version": "1.0.0",
    "description": "Diamond Top",
    "download_url": "file://$DTOP_PKG",
    "checksum": "$DTOP_CS",
    "dependencies": [
      { "name": "diamLeft", "constraint": ">=1.0.0" },
      { "name": "diamRight", "constraint": ">=1.0.0" }
    ]
  }
]
EOF

    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$TEST_DB" --repo "$INDEX_FILE" --cache "$CACHE_FILE" --no-cache -y install diamTop
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Total packages to install: 4" ]]

    # Verify all 4 files exist
    [ -f "$SANDBOX/usr/local/bin/dbase" ]
    [ -f "$SANDBOX/usr/local/bin/dleft" ]
    [ -f "$SANDBOX/usr/local/bin/dright" ]
    [ -f "$SANDBOX/usr/local/bin/dtop" ]
}

@test "deps: unresolvable dependency deep in chain aborts entire operation" {
    INDEX_FILE="$TEST_TMP/ghost_index.json"
    CACHE_FILE="$TEST_TMP/ghost_cache.json"

    # Middle package requires a ghost package not in index or DB
    MID_BUILD="$TEST_TMP/ghost_mid"
    mkdir -p "$MID_BUILD/bin"
    echo "mid" > "$MID_BUILD/bin/mid"
    MID_CS="$(cat "$MID_BUILD/bin/mid" | _calc_sha256 -)"
    cat <<EOF > "$MID_BUILD/manifest.json"
{
  "name": "midPkg",
  "version": "1.0.0",
  "description": "Mid",
  "checksum": "$MID_CS",
  "install_paths": [
    { "source": "bin/mid", "destination": "/usr/local/bin/mid" }
  ],
  "dependencies": [
    { "name": "ghostDep", "constraint": ">=2.0.0" }
  ]
}
EOF
    MID_PKG="$TEST_TMP/midPkg-1.0.0.rav"
    (cd "$MID_BUILD" && tar -czf "$MID_PKG" manifest.json bin/mid)

    TOP_BUILD="$TEST_TMP/ghost_top"
    mkdir -p "$TOP_BUILD/bin"
    echo "top" > "$TOP_BUILD/bin/top"
    TOP_CS="$(cat "$TOP_BUILD/bin/top" | _calc_sha256 -)"
    cat <<EOF > "$TOP_BUILD/manifest.json"
{
  "name": "topPkg",
  "version": "1.0.0",
  "description": "Top",
  "checksum": "$TOP_CS",
  "install_paths": [
    { "source": "bin/top", "destination": "/usr/local/bin/top" }
  ],
  "dependencies": [
    { "name": "midPkg", "constraint": ">=1.0.0" }
  ]
}
EOF
    TOP_PKG="$TEST_TMP/topPkg-1.0.0.rav"
    (cd "$TOP_BUILD" && tar -czf "$TOP_PKG" manifest.json bin/top)

    cat <<EOF > "$INDEX_FILE"
[
  {
    "name": "midPkg",
    "version": "1.0.0",
    "description": "Mid",
    "download_url": "file://$MID_PKG",
    "checksum": "$MID_CS",
    "dependencies": [
      { "name": "ghostDep", "constraint": ">=2.0.0" }
    ]
  },
  {
    "name": "topPkg",
    "version": "1.0.0",
    "description": "Top",
    "download_url": "file://$TOP_PKG",
    "checksum": "$TOP_CS",
    "dependencies": [
      { "name": "midPkg", "constraint": ">=1.0.0" }
    ]
  }
]
EOF

    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$TEST_DB" --repo "$INDEX_FILE" --cache "$CACHE_FILE" --no-cache -y install topPkg
    [ "$status" -ne 0 ]
    [[ "$output" =~ "cannot resolve dependency 'ghostDep'" ]]

    # Verify zero files installed
    [ ! -f "$SANDBOX/usr/local/bin/top" ]
    [ ! -f "$SANDBOX/usr/local/bin/mid" ]
}

@test "deps: circular dependency across multi-package chain rejected before install" {
    INDEX_FILE="$TEST_TMP/cyc_index.json"
    CACHE_FILE="$TEST_TMP/cyc_cache.json"

    # A -> B -> C -> A
    cat <<EOF > "$INDEX_FILE"
[
  {
    "name": "nodeA",
    "version": "1.0.0",
    "description": "Node A",
    "download_url": "file:///tmp/dummy",
    "checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "dependencies": [
      { "name": "nodeB", "constraint": ">=1.0.0" }
    ]
  },
  {
    "name": "nodeB",
    "version": "1.0.0",
    "description": "Node B",
    "download_url": "file:///tmp/dummy",
    "checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "dependencies": [
      { "name": "nodeC", "constraint": ">=1.0.0" }
    ]
  },
  {
    "name": "nodeC",
    "version": "1.0.0",
    "description": "Node C",
    "download_url": "file:///tmp/dummy",
    "checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "dependencies": [
      { "name": "nodeA", "constraint": ">=1.0.0" }
    ]
  }
]
EOF

    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$TEST_DB" --repo "$INDEX_FILE" --cache "$CACHE_FILE" --no-cache -y install nodeA
    [ "$status" -ne 0 ]
    [[ "$output" =~ "circular dependency detected across transaction plan" ]]
}

@test "deps: mid-transaction failure triggers full transaction rollback" {
    INDEX_FILE="$TEST_TMP/rb_index.json"
    CACHE_FILE="$TEST_TMP/rb_cache.json"

    # Step 1: Base package (valid)
    RBASE_BUILD="$TEST_TMP/rbase_build"
    mkdir -p "$RBASE_BUILD/bin"
    echo "rbase" > "$RBASE_BUILD/bin/rbase"
    RBASE_CS="$(cat "$RBASE_BUILD/bin/rbase" | _calc_sha256 -)"
    cat <<EOF > "$RBASE_BUILD/manifest.json"
{
  "name": "rbBase",
  "version": "1.0.0",
  "description": "Rollback Base",
  "checksum": "$RBASE_CS",
  "install_paths": [
    { "source": "bin/rbase", "destination": "/usr/local/bin/rbase" }
  ],
  "dependencies": []
}
EOF
    RBASE_PKG="$TEST_TMP/rbBase-1.0.0.rav"
    (cd "$RBASE_BUILD" && tar -czf "$RBASE_PKG" manifest.json bin/rbase)

    # Step 2: Broken package (invalid destination path causing copy failure)
    RBROKE_BUILD="$TEST_TMP/rbroke_build"
    mkdir -p "$RBROKE_BUILD/bin"
    echo "broke" > "$RBROKE_BUILD/bin/broke"
    RBROKE_CS="$(cat "$RBROKE_BUILD/bin/broke" | _calc_sha256 -)"
    cat <<EOF > "$RBROKE_BUILD/manifest.json"
{
  "name": "rbBroke",
  "version": "1.0.0",
  "description": "Rollback Broken",
  "checksum": "$RBROKE_CS",
  "install_paths": [
    { "source": "bin/broke", "destination": "/usr/local/invalid_dir/sub/broke" }
  ],
  "dependencies": [
    { "name": "rbBase", "constraint": ">=1.0.0" }
  ]
}
EOF
    RBROKE_PKG="$TEST_TMP/rbBroke-1.0.0.rav"
    (cd "$RBROKE_BUILD" && tar -czf "$RBROKE_PKG" manifest.json bin/broke)

    # Step 3: Top package
    RTOP_BUILD="$TEST_TMP/rtop_build"
    mkdir -p "$RTOP_BUILD/bin"
    echo "top" > "$RTOP_BUILD/bin/top"
    RTOP_CS="$(cat "$RTOP_BUILD/bin/top" | _calc_sha256 -)"
    cat <<EOF > "$RTOP_BUILD/manifest.json"
{
  "name": "rbTop",
  "version": "1.0.0",
  "description": "Rollback Top",
  "checksum": "$RTOP_CS",
  "install_paths": [
    { "source": "bin/top", "destination": "/usr/local/bin/top" }
  ],
  "dependencies": [
    { "name": "rbBroke", "constraint": ">=1.0.0" }
  ]
}
EOF
    RTOP_PKG="$TEST_TMP/rbTop-1.0.0.rav"
    (cd "$RTOP_BUILD" && tar -czf "$RTOP_PKG" manifest.json bin/top)

    # Make /usr/local/invalid_dir an unwritable regular file so install of rbBroke fails
    mkdir -p "$SANDBOX/usr/local"
    touch "$SANDBOX/usr/local/invalid_dir"

    cat <<EOF > "$INDEX_FILE"
[
  {
    "name": "rbBase",
    "version": "1.0.0",
    "description": "Rollback Base",
    "download_url": "file://$RBASE_PKG",
    "checksum": "$RBASE_CS",
    "dependencies": []
  },
  {
    "name": "rbBroke",
    "version": "1.0.0",
    "description": "Rollback Broken",
    "download_url": "file://$RBROKE_PKG",
    "checksum": "$RBROKE_CS",
    "dependencies": [
      { "name": "rbBase", "constraint": ">=1.0.0" }
    ]
  },
  {
    "name": "rbTop",
    "version": "1.0.0",
    "description": "Rollback Top",
    "download_url": "file://$RTOP_PKG",
    "checksum": "$RTOP_CS",
    "dependencies": [
      { "name": "rbBroke", "constraint": ">=1.0.0" }
    ]
  }
]
EOF

    run "$ROOT_DIR/bin/ravpkg" --root "$SANDBOX" --db "$TEST_DB" --repo "$INDEX_FILE" --cache "$CACHE_FILE" --no-cache -y install rbTop
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Executing full transaction rollback" ]]
    [[ "$output" =~ "Full transaction rollback complete" ]]

    # Verify rbBase was rolled back and deleted from filesystem
    [ ! -f "$SANDBOX/usr/local/bin/rbase" ]
    [ ! -f "$SANDBOX/usr/local/bin/top" ]

    # Verify rbBase was removed from SQLite DB
    run db_get_package "$TEST_DB" "rbBase"
    [ "$status" -ne 0 ]
}
