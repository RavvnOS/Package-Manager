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

# Helper: Finds an installed package matching by name or by "provides"
# Outputs package JSON record if found, returns 0; otherwise returns 1.
_find_installed_provider() {
    local db_path="$1"
    local dep_name="$2"
    local root_prefix="${3:-}"

    # 1. Exact name match in DB
    local pkg_json
    if pkg_json="$(db_get_package "$db_path" "$dep_name" 2>/dev/null)"; then
        echo "$pkg_json"
        return 0
    fi

    # 2. Check if any installed package provides dep_name
    local all_pkgs_json
    if ! all_pkgs_json="$(db_list_packages "$db_path" 2>/dev/null)"; then
        return 1
    fi

    local count
    count="$(echo "$all_pkgs_json" | jq 'length' 2>/dev/null || echo 0)"
    [[ "$count" -eq 0 ]] && return 1

    local p
    for ((p=0; p<count; p++)); do
        local inst_manifest
        inst_manifest="$(echo "$all_pkgs_json" | jq -r ".[$p].manifest_path" | tr -d '\r')"
        if [[ ! -f "$inst_manifest" && -n "$root_prefix" && -f "${root_prefix%/}$inst_manifest" ]]; then
            inst_manifest="${root_prefix%/}$inst_manifest"
        fi

        if [[ -f "$inst_manifest" ]]; then
            local has_prov
            has_prov="$(jq --arg dep "$dep_name" '
                [(.provides // [])[] | select(. == $dep)] | length
            ' "$inst_manifest" 2>/dev/null || echo 0)"
            if [[ "$has_prov" -gt 0 ]]; then
                echo "$all_pkgs_json" | jq -c ".[$p]"
                return 0
            fi
        fi
    done

    return 1
}

# Checks whether a package conflicts with any currently installed packages
# (both if this package declares conflicts with an installed package/capability,
# or if an installed package declares conflicts with this package/capability)
check_package_conflicts() {
    local manifest_json="$1"
    local db_path="$2"
    local root_prefix="${3:-}"

    local pkg_name
    pkg_name="$(echo "$manifest_json" | jq -r '.name // empty' | tr -d '\r')"

    local conflicts_json
    conflicts_json="$(echo "$manifest_json" | jq -c '.conflicts // []' 2>/dev/null || echo "[]")"
    local conflicts_count
    conflicts_count="$(echo "$conflicts_json" | jq 'length' 2>/dev/null || echo 0)"

    local provides_json
    provides_json="$(echo "$manifest_json" | jq -c '.provides // []' 2>/dev/null || echo "[]")"
    local provides_count
    provides_count="$(echo "$provides_json" | jq 'length' 2>/dev/null || echo 0)"

    local all_pkgs_json
    if ! all_pkgs_json="$(db_list_packages "$db_path" 2>/dev/null)"; then
        return 0
    fi
    local installed_count
    installed_count="$(echo "$all_pkgs_json" | jq 'length' 2>/dev/null || echo 0)"
    [[ "$installed_count" -eq 0 ]] && return 0

    local -a detected_conflicts=()

    # Direction 1: This package's conflicts list vs installed packages
    if [[ "$conflicts_count" -gt 0 ]]; then
        local c
        for ((c=0; c<conflicts_count; c++)); do
            local conflict_target
            conflict_target="$(echo "$conflicts_json" | jq -r ".[$c]" | tr -d '\r')"
            [[ -z "$conflict_target" ]] && continue

            # Check if installed package matches name
            local inst_pkg
            if inst_pkg="$(db_get_package "$db_path" "$conflict_target" 2>/dev/null)"; then
                local inst_ver
                inst_ver="$(echo "$inst_pkg" | jq -r '.version' | tr -d '\r')"
                detected_conflicts+=("conflicts with installed package '$conflict_target' (version $inst_ver)")
            else
                # Check if an installed package provides conflict_target
                local p
                for ((p=0; p<installed_count; p++)); do
                    local other_name other_manifest
                    other_name="$(echo "$all_pkgs_json" | jq -r ".[$p].name" | tr -d '\r')"
                    other_manifest="$(echo "$all_pkgs_json" | jq -r ".[$p].manifest_path" | tr -d '\r')"
                    if [[ ! -f "$other_manifest" && -n "$root_prefix" && -f "${root_prefix%/}$other_manifest" ]]; then
                        other_manifest="${root_prefix%/}$other_manifest"
                    fi
                    if [[ -f "$other_manifest" ]]; then
                        local has_prov
                        has_prov="$(jq --arg ct "$conflict_target" '[(.provides // [])[] | select(. == $ct)] | length' "$other_manifest" 2>/dev/null || echo 0)"
                        if [[ "$has_prov" -gt 0 ]]; then
                            detected_conflicts+=("conflicts with installed package '$other_name' which provides virtual capability '$conflict_target'")
                        fi
                    fi
                done
            fi
        done
    fi

    # Direction 2: Installed packages' conflicts list vs this package
    local p
    for ((p=0; p<installed_count; p++)); do
        local other_name other_ver other_manifest
        other_name="$(echo "$all_pkgs_json" | jq -r ".[$p].name" | tr -d '\r')"
        [[ "$other_name" == "$pkg_name" ]] && continue
        other_ver="$(echo "$all_pkgs_json" | jq -r ".[$p].version" | tr -d '\r')"
        other_manifest="$(echo "$all_pkgs_json" | jq -r ".[$p].manifest_path" | tr -d '\r')"
        if [[ ! -f "$other_manifest" && -n "$root_prefix" && -f "${root_prefix%/}$other_manifest" ]]; then
            other_manifest="${root_prefix%/}$other_manifest"
        fi
        if [[ -f "$other_manifest" ]]; then
            # Does other package list $pkg_name in its conflicts?
            local conflicts_with_us
            conflicts_with_us="$(jq --arg name "$pkg_name" '[(.conflicts // [])[] | select(. == $name)] | length' "$other_manifest" 2>/dev/null || echo 0)"
            if [[ "$conflicts_with_us" -gt 0 ]]; then
                detected_conflicts+=("installed package '$other_name' (version $other_ver) conflicts with '$pkg_name'")
            fi

            # Does other package list any capability we provide in its conflicts?
            if [[ "$provides_count" -gt 0 ]]; then
                local pr
                for ((pr=0; pr<provides_count; pr++)); do
                    local prov_name
                    prov_name="$(echo "$provides_json" | jq -r ".[$pr]" | tr -d '\r')"
                    local conf_prov
                    conf_prov="$(jq --arg pv "$prov_name" '[(.conflicts // [])[] | select(. == $pv)] | length' "$other_manifest" 2>/dev/null || echo 0)"
                    if [[ "$conf_prov" -gt 0 ]]; then
                        detected_conflicts+=("installed package '$other_name' (version $other_ver) conflicts with provided capability '$prov_name'")
                    fi
                done
            fi
        fi
    done

    if [[ ${#detected_conflicts[@]} -gt 0 ]]; then
        echo "Error: package '$pkg_name' cannot be installed due to package conflicts:" >&2
        for dc in "${detected_conflicts[@]}"; do
            echo "  - $dc" >&2
        done
        return 1
    fi

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
        if ! pkg_json="$(_find_installed_provider "$db_path" "$dep_name" "$root_prefix")"; then
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
# First checks for exact name matches, then falls back to matching packages via "provides"
_find_highest_satisfying_candidate() {
    local index_cache="$1"
    local pkg_name="$2"
    local constraint="${3:-*}"

    if [[ ! -f "$index_cache" || ! -r "$index_cache" ]]; then
        return 1
    fi

    # 1. Search for exact name matches
    local matching_json
    matching_json="$(jq -c --arg name "$pkg_name" '[.[] | select(.name == $name)]' "$index_cache" 2>/dev/null || echo "[]")"
    local count
    count="$(echo "$matching_json" | jq 'length' 2>/dev/null || echo 0)"

    local best_entry=""
    local best_ver=""

    if [[ "$count" -gt 0 ]]; then
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
    fi

    # 2. If no satisfying exact name candidate was found, search by "provides"
    if [[ -z "$best_entry" ]]; then
        matching_json="$(jq -c --arg name "$pkg_name" '
            [.[] | select((.provides // []) | index($name) != null)]
        ' "$index_cache" 2>/dev/null || echo "[]")"
        count="$(echo "$matching_json" | jq 'length' 2>/dev/null || echo 0)"

        if [[ "$count" -gt 0 ]]; then
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
        fi
    fi

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

    # Check conflicts on root target package before planning
    if ! check_package_conflicts "$root_manifest_json" "$db_path" "$root_prefix"; then
        return 1
    fi

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

            # 1. Skip if already resolved and scheduled in the plan (deduplicates diamond and virtual dependencies)
            local already_resolved=0
            local pl
            for ((pl=0; pl<${#PLAN_ENTRIES[@]}; pl++)); do
                local pl_item="${PLAN_ENTRIES[pl]}"
                local pl_name pl_ver
                pl_name="$(echo "$pl_item" | jq -r '.name' | tr -d '\r')"
                pl_ver="$(echo "$pl_item" | jq -r '.version' | tr -d '\r')"
                if [[ "$pl_name" == "$dep_name" ]]; then
                    already_resolved=1
                    break
                fi
                local pl_has_prov
                pl_has_prov="$(echo "$pl_item" | jq --arg dn "$dep_name" '[(.provides // [])[] | select(. == $dn)] | length' 2>/dev/null || echo 0)"
                if [[ "$pl_has_prov" -gt 0 ]]; then
                    if semver_satisfies "$pl_ver" "$dep_constraint"; then
                        already_resolved=1
                        break
                    fi
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

            # 3. Check if dependency is already installed in local database (exact name or provides)
            local pkg_json
            if pkg_json="$(_find_installed_provider "$db_path" "$dep_name" "$root_prefix")"; then
                local installed_ver inst_pkg_name
                inst_pkg_name="$(echo "$pkg_json" | jq -r '.name' | tr -d '\r')"
                installed_ver="$(echo "$pkg_json" | jq -r '.version' | tr -d '\r')"
                if semver_satisfies "$installed_ver" "$dep_constraint"; then
                    # Satisfied by existing installation
                    continue
                else
                    # Installed but does not satisfy constraint
                    echo "Error: dependency '$dep_name' (provided by '$inst_pkg_name') is already installed at version $installed_ver, which does not satisfy constraint '$dep_constraint' (required by '$current_pkg')." >&2
                    echo "Upgrades and side-by-side installations are not supported; please remove or update '$inst_pkg_name' first." >&2
                    return 1
                fi
            fi

            # 4. Search repository index for highest satisfying version (exact name or provides)
            local cand_entry
            if ! cand_entry="$(_find_highest_satisfying_candidate "$index_cache" "$dep_name" "$dep_constraint")"; then
                echo "Error: cannot resolve dependency '$dep_name' (constraint: $dep_constraint) required by '$current_pkg'." >&2
                echo "No satisfying package version found in repository index." >&2
                return 1
            fi

            # 5. Check if candidate conflicts with any installed packages
            if ! check_package_conflicts "$cand_entry" "$db_path" "$root_prefix"; then
                return 1
            fi

            # 6. Check if candidate conflicts with already planned packages in this transaction
            local cand_pkg_name
            cand_pkg_name="$(echo "$cand_entry" | jq -r '.name' | tr -d '\r')"
            local pl
            for ((pl=0; pl<${#PLAN_ENTRIES[@]}; pl++)); do
                local pl_item="${PLAN_ENTRIES[pl]}"
                local pl_pkg_name
                pl_pkg_name="$(echo "$pl_item" | jq -r '.name' | tr -d '\r')"
                local c1 c2
                c1="$(echo "$cand_entry" | jq --arg n "$pl_pkg_name" '[(.conflicts // [])[] | select(. == $n)] | length' 2>/dev/null || echo 0)"
                c2="$(echo "$pl_item" | jq --arg n "$cand_pkg_name" '[(.conflicts // [])[] | select(. == $n)] | length' 2>/dev/null || echo 0)"
                if [[ "$c1" -gt 0 || "$c2" -gt 0 ]]; then
                    echo "Error: conflict detected in transaction plan between '$cand_pkg_name' and '$pl_pkg_name'." >&2
                    return 1
                fi
            done

            # 7. Recursively resolve sub-dependencies of this candidate
            if ! _resolve_deps_recursive "$cand_pkg_name" "$cand_entry" "$active_chain"; then
                return 1
            fi

            # 8. Post-order scheduling: append after all its dependencies have been scheduled
            local already_added=0
            local r
            for r in "${RESOLVED_PKGS[@]:-}"; do
                if [[ "$r" == "$cand_pkg_name" ]]; then
                    already_added=1
                    break
                fi
            done
            if [[ "$already_added" -eq 0 ]]; then
                RESOLVED_PKGS+=("$cand_pkg_name")
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
