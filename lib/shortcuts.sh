#!/bin/bash
# lib/shortcuts.sh — Desktop shortcut creation and removal
# Sourced by setup; do not execute directly.
# Depends on: lib/config.sh, lib/utils.sh, lib/registry.sh

# Extract the app icon from a Windows .exe as a .ico file.
# GNOME/gdk-pixbuf reads .ico natively — no PNG conversion needed.
# Usage: extract_exe_icon "app-key" "exe_path"
# Outputs: absolute path to the extracted .ico, or nothing on failure.
# Requires: icoutils (wrestool only).
extract_exe_icon() {
    local app_key="$1"
    local exe_path="$2"

    local icon_dir="${HOME}/.local/share/icons/wine-gaming"
    local ico_out="${icon_dir}/wine-gaming-${app_key}.ico"

    mkdir -p "$icon_dir"

    if ! command -v wrestool &>/dev/null; then
        print_warning "icoutils not installed — skipping icon extraction (run: sudo apt install icoutils)"
        return 1
    fi

    local work_dir
    work_dir=$(mktemp -d) || return 1

    # Extract the largest RT_GROUP_ICON resource (type=14) — biggest file = most frame sizes
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

    cp "$best_ico" "$ico_out"
    rm -rf "$work_dir"
    echo "$ico_out"
    return 0
}

# Create a .desktop shortcut and a wrapper launcher script for an app.
# Usage: create_shortcut "app-key" [display_name]
create_shortcut() {
    local app_key="$1"
    local display_name="${2:-}"

    parse_app_config "$app_key" || return 1

    local exe_path
    exe_path=$(find_app_exe "$app_key")
    if [ -z "$exe_path" ]; then
        print_warning "$APP_NAME not installed yet, skipping shortcut creation"
        return 1
    fi

    display_name="${display_name:-$APP_NAME}"

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

    local launcher="$BIN_DIR/$app_key"
    local desktop="$APPS_DIR/${app_key}.desktop"
    local setup_script_path
    setup_script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/setup"

    # Generate a standalone wrapper script that sources this project's libs.
    cat > "$launcher" <<'LAUNCHER_EOF'
#!/bin/bash
# Auto-generated launcher for Wine Proton app — do not edit manually.
APP_KEY="%APP_KEY%"
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

# Source lib modules to get parse_app_config / find_app_exe
for _lib in config utils registry; do
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/lib/${_lib}.sh"
done
unset _lib

parse_app_config "$APP_KEY" || exit 1

EXE_PATH=$(find_app_exe "$APP_KEY")
if [ -z "$EXE_PATH" ]; then
    echo "Error: $APP_KEY not found in prefix" >&2
    exit 1
fi

EXE_DIR=$(dirname "$EXE_PATH")
EXE_BIN=$(basename "$EXE_PATH")

cd "$EXE_DIR" || { echo "Error: Cannot cd to $EXE_DIR" >&2; exit 1; }

if [ -x "$PROTON_DIR/proton" ]; then
    "$PROTON_DIR/proton" run "$EXE_BIN" --no-sandbox \
        --disable-gpu-sandbox \
        --disable-software-rasterizer \
        --disable-dev-shm-usage \
        --disable-setuid-sandbox \
        --in-process-gpu >/dev/null 2>&1 &
else
    wine "$EXE_BIN" >/dev/null 2>&1 &
fi
LAUNCHER_EOF

    sed -i "s|%APP_KEY%|$app_key|g"              "$launcher"
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
