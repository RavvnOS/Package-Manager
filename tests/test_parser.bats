#!/usr/bin/env bats
# tests/test_parser.bats - Parser and validation tests for ravpkg

setup() {
    DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    LIB_DIR="$(dirname "$DIR")/lib"
    FIXTURES_DIR="$DIR/fixtures"
    source "$LIB_DIR/parser.sh"
}

@test "parser: valid manifest parses successfully" {
    run parse_manifest_file "$FIXTURES_DIR/valid-manifest.json"
    [ "$status" -eq 0 ]
    
    name="$(manifest_get_name "$output")"
    version="$(manifest_get_version "$output")"
    desc="$(manifest_get_description "$output")"
    files="$(manifest_get_installed_files "$output")"

    [ "$name" = "ravterm" ]
    [ "$version" = "1.0.0" ]
    [ "$desc" = "Terminal emulator for ravynOS" ]
    
    count="$(echo "$files" | jq 'length')"
    [ "$count" -eq 2 ]
}

@test "parser: manifest with dependencies parses successfully" {
    run parse_manifest_file "$FIXTURES_DIR/with-deps-manifest.json"
    [ "$status" -eq 0 ]
    
    name="$(manifest_get_name "$output")"
    [ "$name" = "ravfetch" ]

    dep_count="$(echo "$output" | jq '.dependencies | length')"
    [ "$dep_count" -eq 2 ]
}

@test "parser: missing required fields returns error" {
    run parse_manifest_file "$FIXTURES_DIR/missing-fields-manifest.json"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "missing required field" ]]
}

@test "parser: bad checksum format returns error" {
    run parse_manifest_file "$FIXTURES_DIR/bad-checksum-manifest.json"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "invalid checksum" ]]
}

@test "parser: empty manifest returns error" {
    run validate_manifest ""
    [ "$status" -ne 0 ]
    [[ "$output" =~ "manifest data is empty" ]]
}

@test "parser: malformed JSON returns error" {
    run validate_manifest "{not valid json}"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "malformed manifest JSON" ]]
}

@test "parser: empty install_paths returns error" {
    json='{"name":"pkg","version":"1.0","description":"test","checksum":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855","install_paths":[]}'
    run validate_manifest "$json"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "install_paths" ]]
}

@test "parser: empty source in install_paths returns error" {
    json='{"name":"pkg","version":"1.0","description":"test","checksum":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855","install_paths":[{"source":"","destination":"/usr/bin/pkg"}]}'
    run validate_manifest "$json"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "source" ]]
}

@test "parser: empty destination in install_paths returns error" {
    json='{"name":"pkg","version":"1.0","description":"test","checksum":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855","install_paths":[{"source":"bin/pkg","destination":""}]}'
    run validate_manifest "$json"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "destination" ]]
}
