#!/usr/bin/env bash
# lib/repo.sh - Repository index caching and package search engine
set -euo pipefail

DEFAULT_REPO_URL="https://repo.ravynos.com/index.json"

# Resolve default repository cache file location
repo_get_default_cache_path() {
    if [[ -n "${RAVPKG_REPO_CACHE:-}" ]]; then
        echo "$RAVPKG_REPO_CACHE"
        return
    fi

    local root_prefix="${RAVPKG_ROOT:-}"
    if [[ -n "$root_prefix" ]]; then
        echo "${root_prefix%/}/var/cache/ravpkg/index.json"
        return
    fi

    if [[ -w "/var/cache" || -d "/var/cache/ravpkg" ]]; then
        echo "/var/cache/ravpkg/index.json"
    elif [[ -d "/var" && "$EUID" -eq 0 ]]; then
        echo "/var/cache/ravpkg/index.json"
    else
        local user_cache="${XDG_CACHE_HOME:-$HOME/.cache}"
        echo "${user_cache}/ravpkg/index.json"
    fi
}

# Fetch repository index from local file or remote URL and cache it locally
repo_fetch_index() {
    local source="${1:-}"
    local target_cache="${2:-}"

    if [[ -z "$source" ]]; then
        source="${RAVPKG_REPO_URL:-$DEFAULT_REPO_URL}"
    fi

    if [[ -z "$target_cache" ]]; then
        target_cache="$(repo_get_default_cache_path)"
    fi

    # Strip file:// prefix if present
    if [[ "$source" == file://* ]]; then
        source="${source#file://}"
    fi

    local target_dir
    target_dir="$(dirname "$target_cache")"
    mkdir -p "$target_dir" 2>/dev/null || true

    # Local file path
    if [[ "$source" != http://* && "$source" != https://* ]]; then
        if [[ ! -f "$source" ]]; then
            echo "Error: repository index source not found: '$source'" >&2
            return 1
        fi
        if [[ ! -r "$source" ]]; then
            echo "Error: repository index source is not readable: '$source'" >&2
            return 1
        fi

        # Validate JSON content
        if ! jq empty "$source" 2>/dev/null; then
            echo "Error: repository index at '$source' is not valid JSON" >&2
            return 1
        fi

        if ! jq -e 'if type == "array" then true else false end' "$source" >/dev/null 2>&1; then
            echo "Error: repository index at '$source' must be a JSON array" >&2
            return 1
        fi

        cp -p "$source" "$target_cache"
        return 0
    fi

    # Remote URL (http:// or https://)
    local tmp_file
    tmp_file="$(mktemp 2>/dev/null || mktemp -t 'ravpkg-idx')"

    local fetch_ok=0
    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL "$source" -o "$tmp_file" 2>/dev/null; then
            fetch_ok=1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -qO "$tmp_file" "$source" 2>/dev/null; then
            fetch_ok=1
        fi
    else
        echo "Error: neither 'curl' nor 'wget' is available to fetch remote repository index" >&2
        rm -f "$tmp_file"
        return 1
    fi

    if [[ "$fetch_ok" -ne 1 ]]; then
        echo "Error: failed to fetch repository index from '$source'" >&2
        rm -f "$tmp_file"
        return 1
    fi

    # Validate fetched JSON
    if ! jq empty "$tmp_file" 2>/dev/null; then
        echo "Error: fetched repository index from '$source' contains invalid JSON" >&2
        rm -f "$tmp_file"
        return 1
    fi

    if ! jq -e 'if type == "array" then true else false end' "$tmp_file" >/dev/null 2>&1; then
        echo "Error: fetched repository index from '$source' is not a JSON array" >&2
        rm -f "$tmp_file"
        return 1
    fi

    mv "$tmp_file" "$target_cache"
    return 0
}

# Perform case-insensitive search against cached index JSON
repo_search() {
    local index_cache="$1"
    local query="$2"

    # Check if index cache exists
    if [[ ! -f "$index_cache" || ! -r "$index_cache" ]]; then
        echo "Error: repository index is missing or not cached ($index_cache)." >&2
        echo "Please run 'ravpkg update' or specify a valid repository using --repo." >&2
        return 1
    fi

    # Validate JSON structure
    if ! jq -e 'if type == "array" then true else false end' "$index_cache" >/dev/null 2>&1; then
        echo "Error: repository index file is corrupt or not a JSON array: $index_cache" >&2
        echo "Please run 'ravpkg update' to re-fetch the index." >&2
        return 1
    fi

    # Case-insensitive substring match against package name and description
    local matches
    matches="$(jq -c --arg q "$query" '[.[] | select(
        ((.name // "") | ascii_downcase | contains($q | ascii_downcase)) or
        ((.description // "") | ascii_downcase | contains($q | ascii_downcase))
    )]' "$index_cache")"

    local count
    count="$(echo "$matches" | jq 'length')"

    if [[ "$count" -eq 0 ]]; then
        echo "No packages found matching '$query'."
        return 0
    fi

    # Print matching results in a readable table
    printf "%-18s %-10s %s\n" "NAME" "VERSION" "DESCRIPTION"
    echo "$matches" | jq -r '.[] | [.name, .version, (.description // "-")] | @tsv' | while IFS=$'\t' read -r name ver desc; do
        name="${name//$'\r'/}"
        ver="${ver//$'\r'/}"
        desc="${desc//$'\r'/}"
        printf "%-18s %-10s %s\n" "$name" "$ver" "$desc"
    done
    return 0
}
