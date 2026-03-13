#!/bin/bash
# lib/registry.sh — APP_REGISTRY query helpers and installer discovery
# Sourced by setup; do not execute directly.
# Depends on: lib/config.sh (APP_REGISTRY, WINEPREFIX), lib/utils.sh

# Parse app registry entry into global variables.
# Usage: parse_app_config "app-key"
# Sets: APP_NAME, APP_EXE, APP_URL, APP_UNINSTALL_PATHS
parse_app_config() {
    local app_key="$1"

    if [ -z "${APP_REGISTRY[$app_key]}" ]; then
        print_error "Unknown app: $app_key"
        return 1
    fi

    IFS='|' read -r APP_NAME APP_EXE APP_URL APP_UNINSTALL_PATHS <<< "${APP_REGISTRY[$app_key]}"
    return 0
}

# Locate the app executable inside the Wine prefix.
# Usage: find_app_exe "app-key"
# Returns: absolute path to exe, or empty string if not found.
find_app_exe() {
    local app_key="$1"
    parse_app_config "$app_key" || return 1

    local exe_filename
    exe_filename=$(basename "$APP_EXE")
    local primary_path="$WINEPREFIX/pfx/drive_c/$APP_EXE"

    if [ -f "$primary_path" ]; then
        echo "$primary_path"
        return 0
    fi

    # Fallback: broad search inside drive_c
    local found
    found=$(find "$WINEPREFIX/pfx/drive_c" -name "$exe_filename" -type f 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        echo "$found"
        return 0
    fi

    return 1
}

# Print all registered launchers with their install status.
list_apps() {
    print_info "Registered Game Launchers:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local count=0
    local installed=0
    for app_key in "${!APP_REGISTRY[@]}"; do
        parse_app_config "$app_key" || continue
        ((count++))
        if find_app_exe "$app_key" >/dev/null 2>&1; then
            echo "✓ $app_key           - $APP_NAME (INSTALLED)"
            ((installed++))
        else
            echo "✗ $app_key           - $APP_NAME"
        fi
    done

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Total registered apps: $count | Installed: $installed | Remaining: $((count - installed))"
}

# Find a matching installer in ./installers/ for the given app key.
# Usage: find_local_installer "app-key"
# Returns: path to installer, or empty if not found.
find_local_installer() {
    local app_key="$1"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    local installers_dir="$script_dir/installers"
    local result=""

    [ -d "$installers_dir" ] || return 1

    case "$app_key" in
        ea-desktop)
            result=$(find "$installers_dir" -maxdepth 1 \( -iname "*EAapp*.exe" -o -iname "*origin*.exe" \) 2>/dev/null | head -1)
            ;;
        gog-galaxy)
            result=$(find "$installers_dir" -maxdepth 1 -iname "*galaxy*.exe" 2>/dev/null | head -1)
            ;;
        epic-games)
            result=$(find "$installers_dir" -maxdepth 1 \( -iname "*epic*.msi" -o -iname "*epic*.exe" \) 2>/dev/null | head -1)
            ;;
        ubisoft-connect)
            result=$(find "$installers_dir" -maxdepth 1 \( -iname "*ubisoft*.exe" -o -iname "*upc*.exe" \) 2>/dev/null | head -1)
            ;;
        amazon-games)
            result=$(find "$installers_dir" -maxdepth 1 -iname "*amazon*.exe" 2>/dev/null | head -1)
            ;;
        legacy-games)
            result=$(find "$installers_dir" -maxdepth 1 -iname "*legacy*.exe" 2>/dev/null | head -1)
            ;;
        *)
            return 1
            ;;
    esac

    [ -n "$result" ] && echo "$result" && return 0
    return 1
}

# List all .exe/.msi files present in ./installers/.
list_installers() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    local installers_dir="$script_dir/installers"

    if [ ! -d "$installers_dir" ]; then
        print_warning "No ./installers directory found"
        return 1
    fi

    local count
    count=$(find "$installers_dir" -maxdepth 1 -type f \( -iname "*.exe" -o -iname "*.msi" \) 2>/dev/null | wc -l)

    if [ "$count" -eq 0 ]; then
        print_warning "No installers found in ./installers"
        return 1
    fi

    print_info "Available installers in ./installers:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    find "$installers_dir" -maxdepth 1 -type f \( -iname "*.exe" -o -iname "*.msi" \) 2>/dev/null \
        | while read -r file; do echo "  $(basename "$file")"; done
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Total: $count installer(s)"
}
