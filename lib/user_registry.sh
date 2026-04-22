#!/bin/bash
# lib/user_registry.sh — User-defined app registry (games, standalone exes, …)
# Sourced by setup; do not execute directly.
# Depends on: lib/config.sh, lib/utils.sh, lib/profile.sh (for WG_CONFIG_DIR)
#
# Persistence: $XDG_CONFIG_HOME/wine-gaming/apps.conf  (auto-managed by add/remove,
# but hand-editable). Format mirrors APP_REGISTRY but adds an optional launcher
# field for UX grouping only — it has NO effect on profile inheritance or launch.
#
# Format: USER_APP_REGISTRY[key]="Name|LauncherKey|ExePath"
#   - LauncherKey may be empty (standalone)
#   - ExePath absolute (host filesystem) OR relative to $WINEPREFIX/pfx/drive_c

USER_APPS_FILE="${WG_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/wine-gaming}/apps.conf"
declare -A USER_APP_REGISTRY=()

# Load existing entries (if any).
if [ -f "$USER_APPS_FILE" ]; then
    # shellcheck source=/dev/null
    source "$USER_APPS_FILE"
fi

# Persist USER_APP_REGISTRY back to disk, sorted for stable diffs.
_save_user_apps() {
    mkdir -p "$(dirname "$USER_APPS_FILE")"
    {
        echo "# wine-gaming user app registry — managed by 'wig add' / 'wig remove'"
        echo "# Format: USER_APP_REGISTRY[key]=\"Name|LauncherKey|ExePath\""
        echo "# LauncherKey is optional (display grouping only)."
        echo ""
        local k
        for k in $(printf '%s\n' "${!USER_APP_REGISTRY[@]}" | sort); do
            printf 'USER_APP_REGISTRY[%s]=%q\n' "$k" "${USER_APP_REGISTRY[$k]}"
        done
    } > "$USER_APPS_FILE"
}

# Resolve a user-app exe to an absolute path (handles abs vs drive_c-relative).
# Usage: find_user_app_exe "key"  → echoes path or empty
find_user_app_exe() {
    local key="$1"
    local entry="${USER_APP_REGISTRY[$key]:-}"
    [ -z "$entry" ] && return 1

    local name launcher exe
    IFS='|' read -r name launcher exe <<< "$entry"

    if [ "${exe:0:1}" = "/" ]; then
        [ -f "$exe" ] && echo "$exe" && return 0
    else
        local p="$WINEPREFIX/pfx/drive_c/$exe"
        [ -f "$p" ] && echo "$p" && return 0
    fi
    return 1
}

# Add an entry. Usage: add_user_app KEY EXE-PATH [DISPLAY-NAME] [--launcher KEY]
add_user_app() {
    local key="$1"; shift || { print_error "Usage: wig add <key> <exe> [name] [--launcher <key>]"; return 1; }
    local exe="$1"; shift || { print_error "Missing exe path"; return 1; }
    local name="" launcher=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --launcher) launcher="$2"; shift 2 ;;
            *) [ -z "$name" ] && name="$1" || { print_error "Unexpected arg: $1"; return 1; }; shift ;;
        esac
    done

    if [ -z "$key" ] || [[ "$key" == *"|"* ]]; then
        print_error "Invalid key: '$key' (no pipes)"; return 1
    fi
    if [ -n "${APP_REGISTRY[$key]:-}" ]; then
        print_error "Key '$key' clashes with built-in launcher registry"; return 1
    fi
    if [ -n "${USER_APP_REGISTRY[$key]:-}" ]; then
        print_warning "Overwriting existing user entry: $key"
    fi

    # Resolve relative paths against CWD for the abs check, but store as given.
    local resolved="$exe"
    [ "${exe:0:1}" != "/" ] && [ -f "$exe" ] && resolved=$(readlink -f "$exe")
    if [ "${resolved:0:1}" = "/" ] && [ ! -f "$resolved" ]; then
        print_warning "Exe not found at '$resolved' — entry saved anyway"
    fi
    [ "${exe:0:1}" = "/" ] && exe="$resolved"

    [ -z "$name" ] && name=$(basename "$exe" .exe)

    if [ -n "$launcher" ] && [ -z "${APP_REGISTRY[$launcher]:-}" ]; then
        print_warning "Launcher key '$launcher' is not in APP_REGISTRY (saved anyway)"
    fi

    USER_APP_REGISTRY[$key]="${name}|${launcher}|${exe}"
    _save_user_apps
    print_success "Added: $key  →  $name${launcher:+ (under $launcher)}"
}

# Remove an entry. Usage: remove_user_app KEY
remove_user_app() {
    local key="$1"
    if [ -z "${USER_APP_REGISTRY[$key]:-}" ]; then
        print_error "No user entry: $key"; return 1
    fi
    unset 'USER_APP_REGISTRY[$key]'
    _save_user_apps
    print_success "Removed: $key"
}

# List user-registered apps grouped by launcher.
# Standalone (no launcher) entries appear under "(standalone)".
list_user_apps() {
    if [ ${#USER_APP_REGISTRY[@]} -eq 0 ]; then
        echo "  (no user apps registered — try: wig add <key> /path/to/app.exe)"
        return 0
    fi

    declare -A by_group=()
    local k name launcher exe group
    for k in "${!USER_APP_REGISTRY[@]}"; do
        IFS='|' read -r name launcher exe <<< "${USER_APP_REGISTRY[$k]}"
        group="${launcher:-(standalone)}"
        by_group[$group]+="${k}|${name}"$'\n'
    done

    local g
    for g in $(printf '%s\n' "${!by_group[@]}" | sort); do
        echo ""
        echo "  ── $g ──"
        printf '%s' "${by_group[$g]}" | sort | while IFS='|' read -r k name; do
            [ -z "$k" ] && continue
            local exe_path
            exe_path=$(find_user_app_exe "$k" 2>/dev/null)
            local mark="✓"; [ -z "$exe_path" ] && mark="✗"
            printf "    %s %-24s %s\n" "$mark" "$k" "$name"
        done
    done
}
