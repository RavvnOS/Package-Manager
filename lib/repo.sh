#!/usr/bin/env bash
# lib/repo.sh - Repository index caching and package search engine
set -euo pipefail

DEFAULT_REPO_URL="https://repo.ravynos.com/index.json"

if ! declare -f _calc_sha256 >/dev/null 2>&1; then
    _calc_sha256() {
        if command -v sha256sum >/dev/null 2>&1; then
            sha256sum "$@" | awk '{print $1}'
        elif command -v shasum >/dev/null 2>&1; then
            shasum -a 256 "$@" | awk '{print $1}'
        else
            echo "Error: neither sha256sum nor shasum found" >&2
            return 1
        fi
    }
fi

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

# Look up a package by exact name in index JSON (returns JSON object for latest version)
repo_lookup_package() {
    local index_cache="$1"
    local pkg_name="$2"

    if [[ ! -f "$index_cache" || ! -r "$index_cache" ]]; then
        echo "Error: repository index is missing or unreadable: $index_cache" >&2
        return 1
    fi

    local entry
    entry="$(jq -c --arg name "$pkg_name" '[.[] | select(.name == $name)] | sort_by(.version) | reverse | .[0] // empty' "$index_cache" 2>/dev/null || true)"
    if [[ -z "$entry" || "$entry" == "null" ]]; then
        return 1
    fi
    echo "$entry"
    return 0
}

# Resolve relative download URL against base repository URL or file path
repo_resolve_url() {
    local base_url="$1"
    local dl_url="$2"

    # Absolute URL with scheme (http://, https://, file://, etc.)
    if [[ "$dl_url" == *"://"* ]]; then
        echo "$dl_url"
        return 0
    fi

    # Absolute POSIX or Windows path
    if [[ "$dl_url" == /* || "$dl_url" =~ ^[a-zA-Z]: ]]; then
        echo "$dl_url"
        return 0
    fi

    # dl_url is relative: resolve against base_url directory
    local base_dir
    if [[ "$base_url" == *"/"* ]]; then
        base_dir="${base_url%/*}"
    else
        base_dir="."
    fi

    echo "${base_dir%/}/${dl_url#/}"
}

# Download a package file to target destination (supports HTTP, HTTPS, file://, or local path)
repo_download_package() {
    local url="$1"
    local dest="$2"

    local target_dir
    target_dir="$(dirname "$dest")"
    mkdir -p "$target_dir" 2>/dev/null || true

    # Strip file:// prefix if present
    if [[ "$url" == file://* ]]; then
        local local_file="${url#file://}"
        if [[ ! -f "$local_file" || ! -r "$local_file" ]]; then
            echo "Error: package source file not found or not readable: '$local_file'" >&2
            rm -f "$dest"
            return 1
        fi
        if ! cp "$local_file" "$dest"; then
            rm -f "$dest"
            return 1
        fi
        return 0
    fi

    # Direct local file path
    if [[ "$url" != http://* && "$url" != https://* ]]; then
        if [[ ! -f "$url" || ! -r "$url" ]]; then
            echo "Error: package source file not found or not readable: '$url'" >&2
            rm -f "$dest"
            return 1
        fi
        if ! cp "$url" "$dest"; then
            rm -f "$dest"
            return 1
        fi
        return 0
    fi

    # Remote URL (http:// or https://)
    local dl_ok=0
    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL "$url" -o "$dest" 2>/dev/null; then
            dl_ok=1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -qO "$dest" "$url" 2>/dev/null; then
            dl_ok=1
        fi
    else
        echo "Error: neither 'curl' nor 'wget' is available to download package" >&2
        rm -f "$dest"
        return 1
    fi

    if [[ "$dl_ok" -ne 1 || ! -s "$dest" ]]; then
        echo "Error: failed to download package from '$url'" >&2
        rm -f "$dest"
        return 1
    fi

    return 0
}

# Verify downloaded package file against expected checksum
repo_verify_checksum() {
    local file="$1"
    local expected="$2"

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    expected="$(echo "$expected" | tr -d '\r')"
    if [[ -z "$expected" ]]; then
        return 1
    fi

    # 1. Direct archive checksum
    local file_cs
    file_cs="$(_calc_sha256 "$file" | tr -d '\r')"
    if [[ "$file_cs" == "$expected" ]]; then
        return 0
    fi

    # 2. Uncompressed payload stream (excluding manifest.json)
    local stream_cs
    stream_cs="$(tar -xf "$file" --exclude=manifest.json -O 2>/dev/null | _calc_sha256 - || echo "")"
    stream_cs="$(echo "$stream_cs" | tr -d '\r')"
    if [[ -n "$stream_cs" && "$stream_cs" == "$expected" ]]; then
        return 0
    fi

    return 1
}
