#!/usr/bin/env bash
# repo/generate-index.sh - Scans manifest files and generates repository index JSON
set -euo pipefail

DEFAULT_URL_PREFIX="https://repo.ravynos.com/packages"

show_help() {
    cat <<EOF
Usage: repo/generate-index.sh [options] [manifests-dir]

Scans a directory of package manifests (.json) and generates a repository index JSON.

Options:
  -o, --output <file>         Write index JSON to file instead of stdout
  -u, --url-prefix <prefix>   Base URL prefix for package download URLs
                              (default: $DEFAULT_URL_PREFIX)
  -h, --help                  Show this help message

Index Format:
  An array of objects with fields:
  - name (string)
  - version (string)
  - description (string)
  - download_url (string)
  - checksum (string)
EOF
}

MANIFESTS_DIR=""
OUTPUT_FILE=""
URL_PREFIX="$DEFAULT_URL_PREFIX"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output)
            if [[ $# -lt 2 ]]; then
                echo "Error: --output requires an argument" >&2
                exit 1
            fi
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --output=*)
            OUTPUT_FILE="${1#*=}"
            shift
            ;;
        -u|--url-prefix)
            if [[ $# -lt 2 ]]; then
                echo "Error: --url-prefix requires an argument" >&2
                exit 1
            fi
            URL_PREFIX="$2"
            shift 2
            ;;
        --url-prefix=*)
            URL_PREFIX="${1#*=}"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            if [[ -z "$MANIFESTS_DIR" ]]; then
                MANIFESTS_DIR="$1"
                shift
            else
                echo "Error: unexpected argument: $1" >&2
                show_help >&2
                exit 1
            fi
            ;;
    esac
done

if [[ -z "$MANIFESTS_DIR" ]]; then
    MANIFESTS_DIR="."
fi

if [[ ! -d "$MANIFESTS_DIR" ]]; then
    echo "Error: directory does not exist: $MANIFESTS_DIR" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: 'jq' command is required to generate repository index" >&2
    exit 1
fi

# Collect all .json files in manifests directory
manifest_files=()
while IFS= read -r -d $'\0' f; do
    manifest_files+=("$f")
done < <(find "$MANIFESTS_DIR" -maxdepth 2 -name "*.json" ! -name "index.json" -type f -print0 2>/dev/null || true)

if [[ ${#manifest_files[@]} -eq 0 ]]; then
    # Return empty array if no manifests found
    index_json="[]"
else
    # Parse each manifest and construct index entries
    entries=()
    for mf in "${manifest_files[@]}"; do
        # Validate that the file is valid JSON
        if ! jq empty "$mf" 2>/dev/null; then
            echo "Warning: skipping invalid JSON file: $mf" >&2
            continue
        fi

        # Check required fields: name, version, checksum
        local_name="$(jq -r '.name // empty' "$mf" 2>/dev/null | tr -d '\r')"
        local_version="$(jq -r '.version // empty' "$mf" 2>/dev/null | tr -d '\r')"
        local_checksum="$(jq -r '.checksum // empty' "$mf" 2>/dev/null | tr -d '\r')"
        local_description="$(jq -r '.description // ""' "$mf" 2>/dev/null | tr -d '\r')"
        local_download_url="$(jq -r '.download_url // empty' "$mf" 2>/dev/null | tr -d '\r')"
        local_deps="$(jq -c '.dependencies // []' "$mf" 2>/dev/null || echo "[]")"
        local_conflicts="$(jq -c '.conflicts // []' "$mf" 2>/dev/null || echo "[]")"
        local_provides="$(jq -c '.provides // []' "$mf" 2>/dev/null || echo "[]")"

        if [[ -z "$local_name" || -z "$local_version" || -z "$local_checksum" ]]; then
            echo "Warning: skipping incomplete manifest (missing name/version/checksum): $mf" >&2
            continue
        fi

        if [[ ! "$local_checksum" =~ ^[0-9a-fA-F]{64}$ ]]; then
            echo "Warning: skipping manifest with invalid SHA-256 checksum format: $mf" >&2
            continue
        fi

        if [[ -z "$local_download_url" ]]; then
            local_download_url="${URL_PREFIX%/}/${local_name}-${local_version}.rav"
        fi

        # Generate a single entry JSON
        entry="$(jq -n \
            --arg name "$local_name" \
            --arg version "$local_version" \
            --arg desc "$local_description" \
            --arg dl "$local_download_url" \
            --arg cs "$local_checksum" \
            --argjson deps "$local_deps" \
            --argjson conflicts "$local_conflicts" \
            --argjson provides "$local_provides" \
            '{name: $name, version: $version, description: $desc, download_url: $dl, checksum: $cs, dependencies: $deps, conflicts: $conflicts, provides: $provides}')"

        entries+=("$entry")
    done

    if [[ ${#entries[@]} -eq 0 ]]; then
        index_json="[]"
    else
        # Combine all entries into sorted JSON array
        index_json="$(printf '%s\n' "${entries[@]}" | jq -s 'sort_by(.name, .version)')"
    fi
fi

if [[ -n "$OUTPUT_FILE" ]]; then
    mkdir -p "$(dirname "$OUTPUT_FILE")" 2>/dev/null || true
    echo "$index_json" > "$OUTPUT_FILE"
    echo "Generated repository index with $(echo "$index_json" | jq 'length') package(s) -> $OUTPUT_FILE" >&2
else
    echo "$index_json"
fi
