#!/bin/bash
# lib/shortcuts.sh — Desktop shortcut creation and removal
# Sourced by setup; do not execute directly.
# Depends on: lib/config.sh, lib/utils.sh, lib/registry.sh

# Extract the best available icon from a Windows .exe for use in a GNOME desktop shortcut.
# Strategy: PNG via icotool (preferred — crisp, works for multi-frame .ico files that
# confuse gdk-pixbuf), falling back to raw .ico (works for apps like EA Desktop whose
# .ico icotool refuses to parse but gdk-pixbuf renders from the first valid frame).
# Usage: extract_exe_icon "app-key" "exe_path"
# Outputs: absolute path to the extracted icon (.png or .ico), or nothing on failure.
# Requires: icoutils (wrestool + icotool).
extract_exe_icon() {
    local app_key="$1"
    local exe_path="$2"

    local icon_dir="${HOME}/.local/share/icons/wine-gaming"
    local png_out="${icon_dir}/wine-gaming-${app_key}.png"
    local ico_out="${icon_dir}/wine-gaming-${app_key}.ico"

    mkdir -p "$icon_dir"

    if ! command -v wrestool &>/dev/null; then
        print_warning "icoutils not installed — skipping icon extraction (run: sudo apt install icoutils)"
        return 1
    fi

    local work_dir
    work_dir=$(mktemp -d) || return 1

    # Extract the largest RT_GROUP_ICON resource (type=14)
    if ! wrestool -x -t 14 --output="$work_dir" "$exe_path" 2>/dev/null; then
        rm -rf "$work_dir"
        return 1
    fi

    local best_ico="" best_size=0
    while IFS= read -r -d '' f; do
        local sz
        sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
        if (( sz > best_size )); then
            best_size=$sz
            best_ico="$f"
        fi
    done < <(find "$work_dir" -name "*.ico" -print0 2>/dev/null)

    if [ -z "$best_ico" ]; then
        rm -rf "$work_dir"
        return 1
    fi

    # Prefer PNG: icotool handles multi-frame .ico correctly and gdk-pixbuf renders
    # complex files (17+ frames) as cosmic noise. Fall back to .ico for apps whose
    # .ico is corrupt enough that icotool refuses it but gdk-pixbuf handles anyway.
    if command -v icotool &>/dev/null && icotool -x -o "$work_dir" "$best_ico" 2>/dev/null; then
        local best_png="" best_png_size=0
        while IFS= read -r -d '' f; do
            local sz
            sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
            if (( sz > best_png_size )); then
                best_png_size=$sz
                best_png="$f"
            fi
        done < <(find "$work_dir" -name "*.png" -print0 2>/dev/null)

        if [ -n "$best_png" ]; then
            cp "$best_png" "$png_out"
            rm -rf "$work_dir"
            echo "$png_out"
            return 0
        fi
    fi

    # icotool unavailable or failed — use .ico directly
    cp "$best_ico" "$ico_out"
    rm -rf "$work_dir"
    echo "$ico_out"
    return 0
}

# Create a .desktop shortcut and a wrapper launcher script for an app.
# Usage: create_shortcut [--profile NAME] <app-key> [display_name]
# When --profile is given, the shortcut is suffixed (key-profile.desktop) so
# multiple profile-specific shortcuts can coexist for one app.
create_shortcut() {
    _parse_profile_flag "$@"
    local app_key="${WG_PARSED_ARGS[0]:-}"
    local display_name="${WG_PARSED_ARGS[1]:-}"
    local profile_name="${WG_PARSED_PROFILE}"

    parse_app_config "$app_key" || return 1

    local exe_path
    exe_path=$(find_app_exe "$app_key")
    if [ -z "$exe_path" ]; then
        print_warning "$APP_NAME not installed yet, skipping shortcut creation"
        return 1
    fi

    display_name="${display_name:-$APP_NAME}"
    [ -n "$profile_name" ] && display_name="$display_name ($profile_name)"

    # Attempt to extract the app icon from the installed exe for a better desktop shortcut.
    local app_icon="application-x-ms-dos-executable"
    local extracted_icon
    extracted_icon=$(extract_exe_icon "$app_key" "$exe_path")
    if [ -n "$extracted_icon" ]; then
        app_icon="$extracted_icon"
        print_info "Extracted app icon: $(basename "$extracted_icon")"
    else
        print_warning "Icon extraction failed — using default icon. Re-run after: sudo apt install icoutils"
    fi

    local file_suffix=""
    [ -n "$profile_name" ] && file_suffix="-${profile_name}"
    local launcher="$BIN_DIR/${app_key}${file_suffix}"
    local desktop="$APPS_DIR/${app_key}${file_suffix}.desktop"
    local setup_script_path
    setup_script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/setup"

    # PROFILE_OVERRIDE is baked into the wrapper so the .desktop loads the named profile.
    local profile_export=""
    [ -n "$profile_name" ] && profile_export="WG_PROFILE_OVERRIDE=\"$profile_name\""

    # Generate a standalone wrapper script that sources this project's libs.
    cat > "$launcher" <<'LAUNCHER_EOF'
#!/bin/bash
# Auto-generated launcher for Wine Proton app — do not edit manually.
APP_KEY="%APP_KEY%"
WG_PROFILE_OVERRIDE="%PROFILE_OVERRIDE%"
WINE_DIR="%WINE_DIR%"
WINEPREFIX="%WINEPREFIX%"
PROTON_DIR="%PROTON_DIR%"
SETUP_SCRIPT="%SETUP_SCRIPT%"
SCRIPT_DIR="$(cd "$(dirname "$SETUP_SCRIPT")" && pwd)"

export STEAM_COMPAT_DATA_PATH="$WINEPREFIX"
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$WINE_DIR/steam-root"
export PROTON_LOG=1
export PROTON_LOG_DIR="$WINE_DIR"
export DXVK_HUD=0
export WINEDLLOVERRIDES="winemenubuilder.exe=d"
export VKD3D_SHADER_VERBOSE=0

# Source lib modules to get parse_app_config / find_app_exe / load_profile
for _lib in config utils registry profile user_registry; do
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/lib/${_lib}.sh"
done
unset _lib

parse_app_config "$APP_KEY" || exit 1

# Apply default + per-app profile (FPS cap, HUD, FSR, NVAPI, gamemode, …)
# If WG_PROFILE_OVERRIDE was baked in by --profile, that named profile wins.
if [ -n "$WG_PROFILE_OVERRIDE" ]; then
    load_profile "$WG_PROFILE_OVERRIDE"
else
    load_profile "$APP_KEY"
fi

EXE_PATH=$(find_app_exe "$APP_KEY")
if [ -z "$EXE_PATH" ]; then
    echo "Error: $APP_KEY not found in prefix" >&2
    exit 1
fi

EXE_DIR=$(dirname "$EXE_PATH")
EXE_BIN=$(basename "$EXE_PATH")

cd "$EXE_DIR" || { echo "Error: Cannot cd to $EXE_DIR" >&2; exit 1; }

LOG_FILE="$WINE_DIR/${APP_KEY}${WG_PROFILE_OVERRIDE:+-$WG_PROFILE_OVERRIDE}.log"
if [ -x "$PROTON_DIR/proton" ]; then
    eval "${WG_LAUNCH_PREFIX}\"\$PROTON_DIR/proton\" run \"\$EXE_BIN\"" >"$LOG_FILE" 2>&1 &
else
    eval "${WG_LAUNCH_PREFIX}wine \"\$EXE_BIN\"" >"$LOG_FILE" 2>&1 &
fi
LAUNCHER_EOF

    sed -i "s|%APP_KEY%|$app_key|g"              "$launcher"
    sed -i "s|%PROFILE_OVERRIDE%|$profile_name|g" "$launcher"
    sed -i "s|%WINE_DIR%|$WINE_DIR|g"            "$launcher"
    sed -i "s|%WINEPREFIX%|$WINEPREFIX|g"        "$launcher"
    sed -i "s|%PROTON_DIR%|$PROTON_DIR|g"        "$launcher"
    sed -i "s|%SETUP_SCRIPT%|$setup_script_path|g" "$launcher"
    chmod +x "$launcher"

    cat > "$desktop" <<DESKTOP_EOF
[Desktop Entry]
Name=$display_name
Exec=$launcher
Type=Application
Categories=Game;
Terminal=false
StartupNotify=true
Icon=$app_icon
DESKTOP_EOF

    chmod 644 "$desktop"
    command -v update-desktop-database &>/dev/null \
        && update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true

    print_success "Shortcut created: $display_name"
    return 0
}

# Remove a launcher's desktop shortcut and wrapper script.
# Usage: remove_shortcut "app-key"
remove_shortcut() {
    local app_key="$1"

    parse_app_config "$app_key" || return 1

    local launcher="$BIN_DIR/$app_key"
    local desktop="$APPS_DIR/${app_key}.desktop"
    local removed=0

    [ -f "$launcher" ] && rm -f "$launcher" && ((removed++))
    [ -f "$desktop"  ] && rm -f "$desktop"  && ((removed++))

    if [ "$removed" -gt 0 ]; then
        print_success "Shortcut removed: $APP_NAME"
        command -v update-desktop-database &>/dev/null \
            && update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
    fi

    return 0
}

# Recreate shortcuts for every installed launcher.
# Skips apps not currently present in the prefix.
create_all_shortcuts() {
    print_info "Recreating shortcuts for all installed launchers..."
    local created=0 skipped=0
    for app_key in "${!APP_REGISTRY[@]}"; do
        if find_app_exe "$app_key" >/dev/null 2>&1; then
            create_shortcut "$app_key" && ((created++)) || true
        else
            ((skipped++))
        fi
    done
    print_success "Shortcuts created: $created  (skipped, not installed: $skipped)"
}

# Remove shortcuts for every registered launcher.
remove_all_shortcuts() {
    print_info "Removing shortcuts for all registered launchers..."
    local removed=0
    for app_key in "${!APP_REGISTRY[@]}"; do
        remove_shortcut "$app_key" >/dev/null 2>&1 && ((removed++)) || true
    done
    print_success "Shortcuts removed: $removed"
}
