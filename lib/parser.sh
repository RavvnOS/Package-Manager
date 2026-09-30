#!/usr/bin/env bash
# lib/parser.sh - jq-based manifest parsing and validation for ravpkg
set -euo pipefail

parser_check_dependency() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: 'jq' command not found. Please install jq to use ravpkg." >&2
        return 1
    fi
    return 0
}

# Validate raw JSON manifest string according to manifest-spec.md
# Outputs error message to stderr and returns 1 if invalid.
validate_manifest() {
    local json_data="$1"

    parser_check_dependency || return 1

    # Check for empty input
    local stripped
    stripped="$(echo "$json_data" | tr -d '[:space:]')"
    if [[ -z "$stripped" ]]; then
        echo "Error: manifest data is empty" >&2
        return 1
    fi

    # Check for valid JSON syntax
    if ! echo "$json_data" | jq empty >/dev/null 2>&1; then
        echo "Error: malformed manifest JSON" >&2
        return 1
    fi

    # Execute structural and semantic validation rules in jq
    local validation_error
    validation_error="$(echo "$json_data" | jq -r '
      if ((.name // "") | tostring | test("^\\s*$")) then
        "manifest missing required field: '\''name'\''"
      elif ((.version // "") | tostring | test("^\\s*$")) then
        "manifest missing required field: '\''version'\''"
      elif ((.description // "") | tostring | test("^\\s*$")) then
        "manifest missing required field: '\''description'\''"
      elif ((.checksum // "") | tostring | test("^\\s*$")) then
        "manifest missing required field: '\''checksum'\''"
      elif ((.checksum // "") | tostring | test("^[a-fA-F0-9]{64}$") | not) then
        "invalid checksum: must be a 64-character hexadecimal SHA-256 string (got \"\(.checksum)\")"
      elif (.install_paths == null or (.install_paths | type != "array") or (.install_paths | length == 0)) then
        "manifest missing required field: '\''install_paths'\'' cannot be empty"
      else
        (
          [ (.install_paths | to_entries[]) |
            if ((.value.source // "") | tostring | test("^\\s*$")) then
              "invalid install_path: install_paths[\(.key)] '\''source'\'' cannot be empty"
            elif ((.value.destination // "") | tostring | test("^\\s*$")) then
              "invalid install_path: install_paths[\(.key)] '\''destination'\'' cannot be empty"
            else empty end
          ][0] //
          [ if .dependencies != null and (.dependencies | type == "array") then
              (.dependencies | to_entries[]) |
              if ((.value.name // "") | tostring | test("^\\s*$")) then
                "manifest missing required field: dependencies[\(.key)] '\''name'\'' cannot be empty"
              else empty end
            else empty end
          ][0] //
          [ if .conflicts != null then
              if (.conflicts | type != "array") then
                "invalid 'conflicts': must be an array of strings"
              else
                (.conflicts | to_entries[]) |
                if ((.value // "") | tostring | test("^\\s*$")) then
                  "invalid conflict: conflicts[\(.key)] cannot be empty"
                else empty end
              end
            else empty end
          ][0] //
          [ if .provides != null then
              if (.provides | type != "array") then
                "invalid 'provides': must be an array of strings"
              else
                (.provides | to_entries[]) |
                if ((.value // "") | tostring | test("^\\s*$")) then
                  "invalid provide: provides[\(.key)] cannot be empty"
                else empty end
              end
            else empty end
          ][0] //
          [ if .signature != null then
              if ((.signature | type != "string") or ((.signature // "") | test("^\\s*$"))) then
                "invalid signature: 'signature' must be a non-empty string"
              else empty end
            else empty end
          ][0] //
          "OK"
        )
      end
    ')"

    if [[ "$validation_error" != "OK" ]]; then
        echo "Error: $validation_error" >&2
        return 1
    fi

    return 0
}

# Read and validate manifest file
# Outputs validated JSON to stdout
parse_manifest_file() {
    local file_path="$1"

    parser_check_dependency || return 1

    if [[ ! -f "$file_path" ]]; then
        echo "Error: unable to read manifest file at \"$file_path\": No such file" >&2
        return 1
    fi

    local content
    content="$(cat "$file_path")"

    if ! validate_manifest "$content"; then
        return 1
    fi

    echo "$content"
}

# Helpers to extract fields from validated manifest JSON
manifest_get_name() {
    echo "$1" | jq -r '.name'
}

manifest_get_version() {
    echo "$1" | jq -r '.version'
}

manifest_get_description() {
    echo "$1" | jq -r '.description'
}

manifest_get_checksum() {
    echo "$1" | jq -r '.checksum'
}

manifest_get_installed_files() {
    echo "$1" | jq -c '[.install_paths[].destination]'
}

manifest_get_conflicts() {
    echo "$1" | jq -c '.conflicts // []'
}

manifest_get_provides() {
    echo "$1" | jq -c '.provides // []'
}

manifest_get_signature() {
    echo "$1" | jq -r '.signature // empty'
}

