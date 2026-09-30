#!/usr/bin/env bash
# lib/db.sh - SQLite wrapper functions for ravpkg using sqlite3 -json

# Ensure sqlite3 is available
db_check_dependency() {
    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo "Error: 'sqlite3' command not found. Please install sqlite3 to use ravpkg." >&2
        return 1
    fi
    return 0
}

# Initialize database schema if not present
db_init() {
    local db_path="$1"
    local schema_file="${2:-}"

    db_check_dependency || return 1

    if [[ "$db_path" != ":memory:" ]]; then
        local db_dir
        db_dir="$(dirname "$db_path")"
        if [[ ! -d "$db_dir" ]]; then
            mkdir -p "$db_dir" || {
                echo "Error: failed to create database directory '$db_dir'" >&2
                return 1
            }
        fi
    fi

    if [[ -n "$schema_file" && -f "$schema_file" ]]; then
        sqlite3 "$db_path" < "$schema_file"
    else
        sqlite3 "$db_path" <<'SQL'
CREATE TABLE IF NOT EXISTS installed_packages (
    name TEXT PRIMARY KEY,
    version TEXT NOT NULL,
    install_date TEXT NOT NULL,
    manifest_path TEXT NOT NULL,
    installed_files TEXT NOT NULL
);
SQL
    fi
}

# Escape single quotes for SQL literals
_sql_escape() {
    local val="$1"
    echo "${val//\'/\'\'}"
}

# Add a package to the database
# Arguments: db_path, name, version, install_date, manifest_path, installed_files_json
db_add_package() {
    local db_path="$1"
    local name="$2"
    local version="$3"
    local install_date="$4"
    local manifest_path="$5"
    local installed_files="${6:-[]}"

    db_check_dependency || return 1

    if [[ -z "$name" ]]; then
        echo "Error: package name cannot be empty" >&2
        return 1
    fi

    if [[ -z "$install_date" ]]; then
        install_date="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    fi

    local esc_name esc_ver esc_date esc_man esc_files
    esc_name="$(_sql_escape "$name")"
    esc_ver="$(_sql_escape "$version")"
    esc_date="$(_sql_escape "$install_date")"
    esc_man="$(_sql_escape "$manifest_path")"
    esc_files="$(_sql_escape "$installed_files")"

    sqlite3 "$db_path" <<SQL
INSERT INTO installed_packages (name, version, install_date, manifest_path, installed_files)
VALUES ('$esc_name', '$esc_ver', '$esc_date', '$esc_man', '$esc_files');
SQL
}

# Remove a package from the database
# Arguments: db_path, name
db_remove_package() {
    local db_path="$1"
    local name="$2"

    db_check_dependency || return 1

    local esc_name
    esc_name="$(_sql_escape "$name")"

    local count
    count="$(sqlite3 "$db_path" "SELECT COUNT(*) FROM installed_packages WHERE name='$esc_name';")"

    if [[ "$count" -eq 0 ]]; then
        echo "Error: package not found in local database: $name" >&2
        return 1
    fi

    sqlite3 "$db_path" "DELETE FROM installed_packages WHERE name='$esc_name';"
}

# Get a package's record from the database
# Arguments: db_path, name
# Outputs JSON object: {"name": "...", "version": "...", "install_date": "...", "manifest_path": "...", "installed_files": "..."}
db_get_package() {
    local db_path="$1"
    local name="$2"

    db_check_dependency || return 1

    local esc_name
    esc_name="$(_sql_escape "$name")"

    local json_out
    json_out="$(sqlite3 -json "$db_path" "SELECT name, version, install_date, manifest_path, installed_files FROM installed_packages WHERE name='$esc_name';")"

    if [[ -z "$json_out" || "$json_out" == "[]" ]]; then
        echo "Error: package not found in local database: $name" >&2
        return 1
    fi

    echo "$json_out" | jq '.[0]'
}

# List all packages in alphabetical order
# Arguments: db_path
# Outputs JSON array of package objects
db_list_packages() {
    local db_path="$1"

    db_check_dependency || return 1

    local json_out
    json_out="$(sqlite3 -json "$db_path" "SELECT name, version, install_date, manifest_path, installed_files FROM installed_packages ORDER BY name ASC;")"

    if [[ -z "$json_out" ]]; then
        echo "[]"
    else
        echo "$json_out"
    fi
}
