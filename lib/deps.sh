#!/usr/bin/env bash
# lib/deps.sh - Dependency resolution, semantic version comparison, and cycle detection
set -euo pipefail

# Pure-Bash semantic version comparator
# Returns:
#   0 if v1 == v2
#   1 if v1 > v2
#   2 if v1 < v2
semver_compare() {
    local v1="${1#[vV]}"
    local v2="${2#[vV]}"

    [[ "$v1" == "$v2" ]] && return 0

    local -a a=() b=()
    local IFS=.
    read -r -a a <<< "$v1"
    read -r -a b <<< "$v2"

    local max=$(( ${#a[@]} > ${#b[@]} ? ${#a[@]} : ${#b[@]} ))
    for ((i=0; i<max; i++)); do
        local p1="${a[i]:-0}"
        local p2="${b[i]:-0}"

        local num1="${p1//[!0-9]*/}"
        local num2="${p2//[!0-9]*/}"
        num1="${num1:-0}"
        num2="${num2:-0}"

        if (( 10#$num1 > 10#$num2 )); then
            return 1
        elif (( 10#$num1 < 10#$num2 )); then
            return 2
        fi
    done
    return 0
}

# Checks whether an installed version satisfies a version constraint (e.g. '>=1.0.0', '=2.1.0')
semver_satisfies() {
    local installed_ver="$1"
    local constraint="${2:-*}"

    constraint="$(echo "$constraint" | tr -d ' \r')"
    installed_ver="$(echo "$installed_ver" | tr -d ' \r')"

    if [[ -z "$constraint" || "$constraint" == "*" ]]; then
        return 0
    fi

    local op=""
    local req_ver=""

    if [[ "$constraint" =~ ^(>=|<=|>|<|==|=)(.+)$ ]]; then
        op="${BASH_REMATCH[1]}"
        req_ver="${BASH_REMATCH[2]}"
    else
        op="="
        req_ver="$constraint"
    fi

    local cmp=0
    semver_compare "$installed_ver" "$req_ver" || cmp=$?

    case "$op" in
        ">=")
            [[ $cmp -eq 0 || $cmp -eq 1 ]]
            ;;
        "<=")
            [[ $cmp -eq 0 || $cmp -eq 2 ]]
            ;;
        ">")
            [[ $cmp -eq 1 ]]
            ;;
        "<")
            [[ $cmp -eq 2 ]]
            ;;
        "="|"==")
            [[ $cmp -eq 0 ]]
            ;;
        *)
            return 1
            ;;
    esac
}

# Recursively detects circular dependencies in the dependency graph
# Usage: _check_cycles <pkg_name> <db_path> <root_prefix> <visited_chain_colon_separated>
_check_cycles() {
    local pkg_name="$1"
    local manifest_json="$2"
    local db_path="$3"
    local root_prefix="$4"
    local chain="$5"

    local deps_count
    deps_count="$(echo "$manifest_json" | jq '.dependencies // [] | length')"
    [[ "$deps_count" -eq 0 ]] && return 0

    local i
    for ((i=0; i<deps_count; i++)); do
        local dep_name
        dep_name="$(echo "$manifest_json" | jq -r ".dependencies[$i].name" | tr -d '\r')"

        # Check self-dependency
        if [[ "$dep_name" == "$pkg_name" ]]; then
            echo "Error: circular dependency detected: $pkg_name -> $dep_name" >&2
            return 1
        fi

        # Check if dep_name already exists in current visitation chain
        local IFS=':'
        local -a chain_parts=($chain)
        local part
        for part in "${chain_parts[@]}"; do
            if [[ "$part" == "$dep_name" ]]; then
                echo "Error: circular dependency detected: ${chain//:/ -> } -> $dep_name" >&2
                return 1
            fi
        done

        # If dep_name is installed in database, inspect its dependencies recursively
        local dep_pkg_json
        if dep_pkg_json="$(db_get_package "$db_path" "$dep_name" 2>/dev/null)"; then
            local dep_manifest_path
            dep_manifest_path="$(echo "$dep_pkg_json" | jq -r '.manifest_path' | tr -d '\r')"
            if [[ ! -f "$dep_manifest_path" && -n "$root_prefix" && -f "${root_prefix%/}$dep_manifest_path" ]]; then
                dep_manifest_path="${root_prefix%/}$dep_manifest_path"
            fi
            if [[ -f "$dep_manifest_path" ]]; then
                local next_manifest
                if next_manifest="$(cat "$dep_manifest_path" 2>/dev/null)"; then
                    if ! _check_cycles "$dep_name" "$next_manifest" "$db_path" "$root_prefix" "${chain}:${dep_name}"; then
                        return 1
                    fi
                fi
            fi
        fi
    done
    return 0
}

# Verifies that all dependencies in a package manifest are satisfied
check_package_dependencies() {
    local manifest_json="$1"
    local db_path="$2"
    local root_prefix="${3:-}"

    local pkg_name
    pkg_name="$(echo "$manifest_json" | jq -r '.name' | tr -d '\r')"

    # 1. Circular dependency detection
    if ! _check_cycles "$pkg_name" "$manifest_json" "$db_path" "$root_prefix" "$pkg_name"; then
        return 1
    fi

    # 2. Check dependencies list
    local deps_count
    deps_count="$(echo "$manifest_json" | jq '.dependencies // [] | length')"
    [[ "$deps_count" -eq 0 ]] && return 0

    local -a missing_deps=()
    local -a unsatisfied_deps=()

    local i
    for ((i=0; i<deps_count; i++)); do
        local dep_name dep_constraint
        dep_name="$(echo "$manifest_json" | jq -r ".dependencies[$i].name" | tr -d '\r')"
        dep_constraint="$(echo "$manifest_json" | jq -r ".dependencies[$i].constraint // \"*\"" | tr -d '\r')"

        local pkg_json
        if ! pkg_json="$(db_get_package "$db_path" "$dep_name" 2>/dev/null)"; then
            missing_deps+=("$dep_name: required constraint '$dep_constraint', but package is not installed")
            continue
        fi

        local installed_ver
        installed_ver="$(echo "$pkg_json" | jq -r '.version' | tr -d '\r')"
        if ! semver_satisfies "$installed_ver" "$dep_constraint"; then
            unsatisfied_deps+=("$dep_name: installed version '$installed_ver' does not satisfy required constraint '$dep_constraint'")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 || ${#unsatisfied_deps[@]} -gt 0 ]]; then
        echo "Error: cannot install '$pkg_name' due to unsatisfied dependencies:" >&2
        for m in "${missing_deps[@]}"; do
            echo "  - $m" >&2
        done
        for u in "${unsatisfied_deps[@]}"; do
            echo "  - $u" >&2
        done
        return 1
    fi

    return 0
}

# Scans installed packages to detect any packages that depend on the package being removed
check_package_dependents_warning() {
    local target_pkg="$1"
    local db_path="$2"
    local root_prefix="${3:-}"

    local all_pkgs_json
    if ! all_pkgs_json="$(db_list_packages "$db_path" 2>/dev/null)"; then
        return 0
    fi

    local -a dependents=()
    local count
    count="$(echo "$all_pkgs_json" | jq 'length' 2>/dev/null || echo 0)"
    [[ "$count" -eq 0 ]] && return 0

    local i
    for ((i=0; i<count; i++)); do
        local other_name other_ver other_manifest
        other_name="$(echo "$all_pkgs_json" | jq -r ".[$i].name" | tr -d '\r')"
        [[ "$other_name" == "$target_pkg" ]] && continue
        other_ver="$(echo "$all_pkgs_json" | jq -r ".[$i].version" | tr -d '\r')"
        other_manifest="$(echo "$all_pkgs_json" | jq -r ".[$i].manifest_path" | tr -d '\r')"

        if [[ ! -f "$other_manifest" && -n "$root_prefix" && -f "${root_prefix%/}$other_manifest" ]]; then
            other_manifest="${root_prefix%/}$other_manifest"
        fi

        if [[ -f "$other_manifest" ]]; then
            local has_dep
            has_dep="$(jq --arg dep "$target_pkg" '
                [(.dependencies // [])[] | select(.name == $dep)] | length
            ' "$other_manifest" 2>/dev/null || echo 0)"
            if [[ "$has_dep" -gt 0 ]]; then
                dependents+=("$other_name (version $other_ver)")
            fi
        fi
    done

    if [[ ${#dependents[@]} -gt 0 ]]; then
        echo "" >&2
        echo "==========================================================================" >&2
        echo "Warning: the following installed package(s) depend on '$target_pkg':" >&2
        for d in "${dependents[@]}"; do
            echo "  - $d" >&2
        done
        echo "Removing '$target_pkg' may cause these packages to stop working properly." >&2
        echo "==========================================================================" >&2
        echo "" >&2
    fi
    return 0
}

# Helper: Finds the highest version candidate from index JSON satisfying a semver constraint
_find_highest_satisfying_candidate() {
    local index_cache="$1"
    local pkg_name="$2"
    local constraint="${3:-*}"

    if [[ ! -f "$index_cache" || ! -r "$index_cache" ]]; then
        return 1
    fi

    # Extract all candidate objects matching pkg_name
    local matching_json
    matching_json="$(jq -c --arg name "$pkg_name" '[.[] | select(.name == $name)]' "$index_cache" 2>/dev/null || echo "[]")"
    local count
    count="$(echo "$matching_json" | jq 'length' 2>/dev/null || echo 0)"
    [[ "$count" -eq 0 ]] && return 1

    local best_entry=""
    local best_ver=""

    local c
    for ((c=0; c<count; c++)); do
        local entry cand_ver
        entry="$(echo "$matching_json" | jq -c ".[$c]")"
        cand_ver="$(echo "$entry" | jq -r '.version' | tr -d '\r')"

        if semver_satisfies "$cand_ver" "$constraint"; then
            if [[ -z "$best_ver" ]]; then
                best_ver="$cand_ver"
                best_entry="$entry"
            else
                local cmp=0
                semver_compare "$cand_ver" "$best_ver" || cmp=$?
                if [[ $cmp -eq 1 ]]; then
                    best_ver="$cand_ver"
                    best_entry="$entry"
                fi
            fi
        fi
    done

    if [[ -z "$best_entry" ]]; then
        return 1
    fi

    echo "$best_entry"
    return 0
}

# Constructs a topological, deduplicated installation plan for all unsatisfied dependencies
deps_build_install_plan() {
    local root_name="$1"
    local root_manifest_json="$2"
    local db_path="$3"
    local index_cache="$4"
    local root_prefix="${5:-}"

    local -a PLAN_ENTRIES=()
    local -a RESOLVED_PKGS=()

    _resolve_deps_recursive() {
        local current_pkg="$1"
        local manifest_json="$2"
        local parent_chain="$3"

        # Check for circular dependency in active resolution chain
        if [[ -n "$parent_chain" ]]; then
            local IFS=':'
            local -a chain_parts=($parent_chain)
            local part
            for part in "${chain_parts[@]}"; do
                if [[ "$part" == "$current_pkg" ]]; then
                    echo "Error: circular dependency detected across transaction plan: ${parent_chain//:/ -> } -> $current_pkg" >&2
                    return 1
                fi
            done
        fi

        local active_chain="${parent_chain:+${parent_chain}:}${current_pkg}"

        local deps_count
        deps_count="$(echo "$manifest_json" | jq '.dependencies // [] | length' 2>/dev/null || echo 0)"

        local d
        for ((d=0; d<deps_count; d++)); do
            local dep_name dep_constraint
            dep_name="$(echo "$manifest_json" | jq -r ".dependencies[$d].name" | tr -d '\r')"
            dep_constraint="$(echo "$manifest_json" | jq -r ".dependencies[$d].constraint // \"*\"" | tr -d '\r')"

            # 1. Skip if already resolved and scheduled in the plan (deduplicates diamond dependencies)
            local already_resolved=0
            local r
            for r in "${RESOLVED_PKGS[@]:-}"; do
                if [[ "$r" == "$dep_name" ]]; then
                    already_resolved=1
                    break
                fi
            done
            if [[ "$already_resolved" -eq 1 ]]; then
                continue
            fi

            # 2. Check for cycle in active recursion chain
            local IFS=':'
            local -a chain_parts=($active_chain)
            local part
            for part in "${chain_parts[@]}"; do
                if [[ "$part" == "$dep_name" ]]; then
                    echo "Error: circular dependency detected across transaction plan: ${active_chain//:/ -> } -> $dep_name" >&2
                    return 1
                fi
            done

            # 3. Check if dependency is already installed in local database
            local pkg_json
            if pkg_json="$(db_get_package "$db_path" "$dep_name" 2>/dev/null)"; then
                local installed_ver
                installed_ver="$(echo "$pkg_json" | jq -r '.version' | tr -d '\r')"
                if semver_satisfies "$installed_ver" "$dep_constraint"; then
                    # Satisfied by existing installation
                    continue
                else
                    # Installed but does not satisfy constraint
                    echo "Error: dependency '$dep_name' is already installed at version $installed_ver, which does not satisfy constraint '$dep_constraint' (required by '$current_pkg')." >&2
                    echo "Upgrades and side-by-side installations are not supported; please remove or update '$dep_name' first." >&2
                    return 1
                fi
            fi

            # 4. Search repository index for highest satisfying version
            local cand_entry
            if ! cand_entry="$(_find_highest_satisfying_candidate "$index_cache" "$dep_name" "$dep_constraint")"; then
                echo "Error: cannot resolve dependency '$dep_name' (constraint: $dep_constraint) required by '$current_pkg'." >&2
                echo "No satisfying package version found in repository index." >&2
                return 1
            fi

            # 5. Recursively resolve sub-dependencies of this candidate
            if ! _resolve_deps_recursive "$dep_name" "$cand_entry" "$active_chain"; then
                return 1
            fi

            # 6. Post-order scheduling: append after all its dependencies have been scheduled
            local already_added=0
            local r
            for r in "${RESOLVED_PKGS[@]:-}"; do
                if [[ "$r" == "$dep_name" ]]; then
                    already_added=1
                    break
                fi
            done
            if [[ "$already_added" -eq 0 ]]; then
                RESOLVED_PKGS+=("$dep_name")
                local enriched_entry
                enriched_entry="$(echo "$cand_entry" | jq -c --arg req_by "$current_pkg" --arg req_cs "$dep_constraint" '
                    . + {required_by: $req_by, constraint: $req_cs, source: "repo"}
                ')"
                PLAN_ENTRIES+=("$enriched_entry")
            fi
        done
        return 0
    }

    if ! _resolve_deps_recursive "$root_name" "$root_manifest_json" ""; then
        return 1
    fi

    if [[ ${#PLAN_ENTRIES[@]} -eq 0 ]]; then
        echo "[]"
    else
        printf '%s\n' "${PLAN_ENTRIES[@]}" | jq -s '.'
    fi
    return 0
}
