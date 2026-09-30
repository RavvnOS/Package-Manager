#!/usr/bin/env bash
# lib/remove.sh - Filesystem package uninstallation engine
set -euo pipefail

if ! declare -f check_package_dependents_warning >/dev/null 2>&1; then
    _DEPS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "$_DEPS_LIB_DIR/deps.sh" ]]; then
        # shellcheck source=lib/deps.sh
        source "$_DEPS_LIB_DIR/deps.sh"
    fi
fi

pkg_remove() {
    local db_path="$1"
    local package_name="$2"
    local root_prefix="${RAVPKG_ROOT:-}"

    # 1. Look up package in database
    local pkg_json
    if ! pkg_json="$(db_get_package "$db_path" "$package_name" 2>/dev/null)"; then
        echo "Error: package '$package_name' is not installed" >&2
        return 1
    fi

    local version manifest_path files_raw
    version="$(echo "$pkg_json" | jq -r '.version' | tr -d '\r')"
    manifest_path="$(echo "$pkg_json" | jq -r '.manifest_path' | tr -d '\r')"
    files_raw="$(echo "$pkg_json" | jq -r '.installed_files' | tr -d '\r')"

    echo "[REMOVE] Removing package: $package_name ($version)..."

    # 1.5 Check for installed packages that depend on this package (warn, do not block)
    check_package_dependents_warning "$package_name" "$db_path" "$root_prefix"

    # 2. Parse installed files list
    local -a files_to_remove=()
    mapfile -t files_to_remove < <(echo "$files_raw" | jq -r 'if type == "string" then (fromjson? // []) else . end | .[]' 2>/dev/null | tr -d '\r' || true)

    local deleted_count=0
    local missing_count=0

    # 3. Remove each file from filesystem
    for rel_dest in "${files_to_remove[@]}"; do
        rel_dest="${rel_dest//$'\r'/}"
        [[ -z "$rel_dest" ]] && continue

        local target_path
        if [[ -n "$root_prefix" ]]; then
            target_path="${root_prefix%/}$rel_dest"
        else
            target_path="$rel_dest"
        fi
        target_path="${target_path//$'\r'/}"

        if [[ -e "$target_path" || -L "$target_path" ]]; then
            echo "[REMOVE] Deleting: $target_path"
            rm -rf "$target_path"
            deleted_count=$((deleted_count + 1))

            # Clean empty parent directories
            local pdir
            pdir="$(dirname "$target_path")"
            while [[ -n "$pdir" && "$pdir" != "/" && "$pdir" != "${root_prefix%/}" && "$pdir" != "." ]]; do
                rmdir "$pdir" 2>/dev/null || break
                pdir="$(dirname "$pdir")"
            done
        else
            echo "Warning: tracked file does not exist: $target_path (skipping)" >&2
            missing_count=$((missing_count + 1))
        fi
    done

    # 4. Remove stored manifest file
    local target_manifest
    if [[ -n "$root_prefix" ]]; then
        target_manifest="${root_prefix%/}$manifest_path"
    else
        target_manifest="$manifest_path"
    fi
    target_manifest="${target_manifest//$'\r'/}"
    if [[ -f "$target_manifest" ]]; then
        rm -f "$target_manifest" 2>/dev/null || true
    fi

    # 5. Delete database record
    if ! db_remove_package "$db_path" "$package_name"; then
        echo "Error: failed to remove package record from database" >&2
        return 1
    fi

    # 6. Print clear success summary
    echo ""
    echo "=========================================================================="
    echo "Successfully removed: $package_name ($version)"
    echo "Summary: $deleted_count file(s) deleted, $missing_count missing file(s) skipped."
    echo "=========================================================================="
    return 0
}
