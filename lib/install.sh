#!/usr/bin/env bash
# lib/install.sh - Filesystem installation engine with transactional rollback
set -euo pipefail

if ! declare -f check_package_dependencies >/dev/null 2>&1; then
    _DEPS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "$_DEPS_LIB_DIR/deps.sh" ]]; then
        # shellcheck source=lib/deps.sh
        source "$_DEPS_LIB_DIR/deps.sh"
    fi
fi

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

_validate_destination_path() {
    local dest="$1"
    # Destination must be an absolute path
    if [[ "$dest" != /* ]]; then
        echo "Error: destination path must be absolute: '$dest'" >&2
        return 1
    fi

    # Disallow directory traversal (..)
    if [[ "$dest" == *"/.."* || "$dest" == *"/../"* || "$dest" == *".." ]]; then
        echo "Error: path traversal (..) forbidden in destination path: '$dest'" >&2
        return 1
    fi

    # Disallow consecutive slashes
    if [[ "$dest" == *"//"* ]]; then
        echo "Error: malformed destination path containing consecutive slashes: '$dest'" >&2
        return 1
    fi

    return 0
}

# Transactional rollback: unlinks all files placed so far and cleans up newly empty directories
_install_rollback() {
    local -a files_to_remove=("${COPIED_FILES[@]:-}")
    if [[ ${#files_to_remove[@]} -gt 0 ]]; then
        echo "[ROLLBACK] Transaction failed; reverting partial installation..." >&2
        for target in "${files_to_remove[@]}"; do
            if [[ -e "$target" || -L "$target" ]]; then
                rm -rf "$target"
                echo "[ROLLBACK] Removed: $target" >&2

                # Prune parent directories if now empty
                local pdir
                pdir="$(dirname "$target")"
                while [[ -n "$pdir" && "$pdir" != "/" && "$pdir" != "${RAVPKG_ROOT:-}" && "$pdir" != "." ]]; do
                    rmdir "$pdir" 2>/dev/null || break
                    pdir="$(dirname "$pdir")"
                done
            fi
        done
    fi
    if [[ -n "${STAGE_DIR:-}" && -d "$STAGE_DIR" ]]; then
        rm -rf "$STAGE_DIR"
    fi
}

pkg_install() {
    local db_path="$1"
    local package_file="$2"
    local root_prefix="${RAVPKG_ROOT:-}"

    # 1. Verify package file exists and is readable
    if [[ ! -f "$package_file" ]]; then
        echo "Error: package file does not exist: $package_file" >&2
        return 1
    fi
    if [[ ! -r "$package_file" ]]; then
        echo "Error: package file is not readable: $package_file" >&2
        return 1
    fi

    # Create temporary staging directory
    STAGE_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'ravpkg-stage')"
    COPIED_FILES=()

    # Trap any unexpected errors during installation to trigger rollback
    trap '_install_rollback' ERR

    echo "[INSTALL] Staging package in $STAGE_DIR..."

    # Extract manifest.json first
    if ! tar -xf "$package_file" -C "$STAGE_DIR" manifest.json 2>/dev/null; then
        echo "Error: package archive does not contain a top-level manifest.json" >&2
        rm -rf "$STAGE_DIR"
        trap - ERR
        return 1
    fi

    local manifest_path="$STAGE_DIR/manifest.json"

    # 2. Parse and validate manifest inside it
    local manifest_json
    if ! manifest_json="$(parse_manifest_file "$manifest_path")"; then
        echo "Error: invalid manifest in package archive" >&2
        rm -rf "$STAGE_DIR"
        trap - ERR
        return 1
    fi

    local pkg_name pkg_version expected_checksum
    pkg_name="$(manifest_get_name "$manifest_json" | tr -d '\r')"
    pkg_version="$(manifest_get_version "$manifest_json" | tr -d '\r')"
    expected_checksum="$(manifest_get_checksum "$manifest_json" | tr -d '\r')"

    # 3. Check if package is already installed
    if existing_pkg="$(db_get_package "$db_path" "$pkg_name" 2>/dev/null)"; then
        local existing_ver
        existing_ver="$(echo "$existing_pkg" | jq -r '.version')"
        echo "Error: package '$pkg_name' is already installed (version $existing_ver). Remove it first to re-install." >&2
        rm -rf "$STAGE_DIR"
        trap - ERR
        return 1
    fi

    # 3.5 Check package dependencies (unless --no-deps is passed)
    if [[ "${RAVPKG_NO_DEPS:-0}" != "1" ]]; then
        if ! check_package_dependencies "$manifest_json" "$db_path" "$root_prefix"; then
            rm -rf "$STAGE_DIR"
            trap - ERR
            return 1
        fi
    fi

    # 4. Verify checksum before extracting files to target filesystem
    # Extract package payload into staging directory
    if ! tar -xf "$package_file" -C "$STAGE_DIR"; then
        echo "Error: failed to extract package archive contents into staging" >&2
        rm -rf "$STAGE_DIR"
        trap - ERR
        return 1
    fi

    # Compute actual checksum of payload:
    # If payload.tar.gz or payload.tar exists in staging, hash that file;
    # otherwise hash all extracted payload files (excluding manifest.json)
    local actual_checksum
    if [[ -f "$STAGE_DIR/payload.tar.gz" ]]; then
        actual_checksum="$(_calc_sha256 "$STAGE_DIR/payload.tar.gz")"
    elif [[ -f "$STAGE_DIR/payload.tar" ]]; then
        actual_checksum="$(_calc_sha256 "$STAGE_DIR/payload.tar")"
    else
        # Stream archive payload contents excluding manifest.json
        actual_checksum="$(tar -xf "$package_file" --exclude=manifest.json -O 2>/dev/null | _calc_sha256 - || echo "")"
        if [[ -z "$actual_checksum" || "$actual_checksum" == "-"* ]]; then
            # Fallback: compute hash across all payload files
            actual_checksum="$(cd "$STAGE_DIR" && find . -type f ! -name manifest.json | sort | xargs _calc_sha256 | _calc_sha256 -)"
        fi
    fi
    actual_checksum="$(echo "$actual_checksum" | tr -d '\r')"
    actual_checksum="${actual_checksum//$'\r'/}"

    if [[ -n "$expected_checksum" && "$expected_checksum" != "$actual_checksum" ]]; then
        echo "Error: checksum mismatch for package '$pkg_name'!" >&2
        echo "  Expected: $expected_checksum" >&2
        echo "  Actual:   $actual_checksum" >&2
        rm -rf "$STAGE_DIR"
        trap - ERR
        return 1
    fi

    echo "[INSTALL] Checksum verified: $expected_checksum"

    # 5. Validate install_paths before moving any files
    local mappings_count
    mappings_count="$(echo "$manifest_json" | jq '.install_paths | length')"

    for ((i=0; i<mappings_count; i++)); do
        local src dest
        src="$(echo "$manifest_json" | jq -r ".install_paths[$i].source" | tr -d '\r')"
        dest="$(echo "$manifest_json" | jq -r ".install_paths[$i].destination" | tr -d '\r')"

        if [[ ! -e "$STAGE_DIR/$src" ]]; then
            echo "Error: manifest declares source '$src' but it does not exist in package archive" >&2
            rm -rf "$STAGE_DIR"
            trap - ERR
            return 1
        fi

        if ! _validate_destination_path "$dest"; then
            rm -rf "$STAGE_DIR"
            trap - ERR
            return 1
        fi
    done

    # 6. Copy files to final destinations with rollback tracking
    local -a actually_installed=()

    for ((i=0; i<mappings_count; i++)); do
        local src dest target_path
        src="$(echo "$manifest_json" | jq -r ".install_paths[$i].source" | tr -d '\r')"
        dest="$(echo "$manifest_json" | jq -r ".install_paths[$i].destination" | tr -d '\r')"

        if [[ -n "$root_prefix" ]]; then
            target_path="${root_prefix%/}$dest"
        else
            target_path="$dest"
        fi

        local target_dir
        target_dir="$(dirname "$target_path")"
        if [[ ! -d "$target_dir" ]]; then
            mkdir -p "$target_dir" || {
                echo "Error: failed to create destination directory '$target_dir'" >&2
                _install_rollback
                trap - ERR
                return 1
            }
        fi

        echo "[INSTALL] Deploying $src -> $target_path"
        if ! cp -p "$STAGE_DIR/$src" "$target_path" 2>/dev/null; then
            echo "Error: failed to copy '$src' to '$target_path'" >&2
            _install_rollback
            trap - ERR
            return 1
        fi

        COPIED_FILES+=("$target_path")
        actually_installed+=("$dest")
    done

    # 7. Write manifest copy to system manifests directory
    local manifests_dir="${root_prefix%/}/var/db/ravpkg/manifests"
    mkdir -p "$manifests_dir" 2>/dev/null || true
    local saved_manifest_path="$manifests_dir/${pkg_name}-${pkg_version}.json"
    cp "$manifest_path" "$saved_manifest_path" 2>/dev/null || true

    # 8. Record in SQLite database
    local files_json
    files_json="$(printf '%s\n' "${actually_installed[@]}" | jq -R . | jq -s -c .)"
    local install_date
    install_date="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    if ! db_add_package "$db_path" "$pkg_name" "$pkg_version" "$install_date" "$saved_manifest_path" "$files_json"; then
        echo "Error: failed to register package in database" >&2
        _install_rollback
        rm -f "$saved_manifest_path" 2>/dev/null || true
        trap - ERR
        return 1
    fi

    # Success: disable error trap and clean up staging
    trap - ERR
    rm -rf "$STAGE_DIR"

    # 9. Print success summary
    echo ""
    echo "=========================================================================="
    echo "Successfully installed: $pkg_name $pkg_version"
    echo "Installed files (${#actually_installed[@]}):"
    for f in "${actually_installed[@]}"; do
        echo "  - $f"
    done
    echo "=========================================================================="
    return 0
}
