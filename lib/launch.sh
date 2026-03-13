#!/bin/bash
# lib/launch.sh — App and external-exe launch via Proton/Wine
# Sourced by setup; do not execute directly.
# Depends on: lib/config.sh, lib/utils.sh, lib/registry.sh

# Launch a registered launcher via Proton (Wine fallback if Proton absent).
# Usage: launch_app "app-key"
launch_app() {
    local app_key="$1"

    parse_app_config "$app_key" || return 1

    local exe_path
    exe_path=$(find_app_exe "$app_key")
    if [ -z "$exe_path" ]; then
        print_error "$APP_NAME not installed. Run: $0 install $app_key"
        return 1
    fi

    local exe_dir exe_bin
    exe_dir=$(dirname "$exe_path")
    exe_bin=$(basename "$exe_path")

    print_info "Launching $APP_NAME..."

    if [ -x "$PROTON_DIR/proton" ]; then
        export STEAM_COMPAT_DATA_PATH="$WINEPREFIX"
        export STEAM_COMPAT_CLIENT_INSTALL_PATH="$WINE_DIR/steam-root"
        export PROTON_LOG=1
        export PROTON_LOG_DIR="$WINE_DIR"
        export DXVK_HUD=0
        export VKD3D_SHADER_VERBOSE=0
        export WINEDLLOVERRIDES="winemenubuilder.exe=d"
        export MESA_GL_VERSION_OVERRIDE=4.5
        export __GL_SHADER_DISK_CACHE=1
        export __GL_THREADED_OPTIMIZATION=1

        cd "$exe_dir"
        "$PROTON_DIR/proton" run "$exe_bin" --no-sandbox \
            --disable-gpu-sandbox \
            --disable-software-rasterizer \
            --disable-dev-shm-usage \
            --disable-setuid-sandbox \
            --in-process-gpu &
    else
        print_warning "Proton not available, using Wine fallback"
        export WINEDEBUG=-all
        export WINEPREFIX="$WINEPREFIX/pfx"
        cd "$exe_dir"
        wine "$exe_bin" &
    fi

    print_success "$APP_NAME launched (PID: $!)"
}

# Launch any external .exe or .msi in the managed wine-gaming prefix.
# Usage: launch_external_exe "/absolute/path/to/Game.exe"
launch_external_exe() {
    local exe_input="$1"

    if [ -z "$exe_input" ]; then
        print_error "Missing file path. Usage: $0 launch-exe /path/to/Game.exe"
        return 1
    fi

    local exe_path
    exe_path=$(readlink -f "$exe_input" 2>/dev/null)

    if [ -z "$exe_path" ] || [ ! -f "$exe_path" ]; then
        print_error "File not found: $exe_input"
        return 1
    fi

    case "${exe_path,,}" in
        *.exe|*.msi) ;;
        *) print_warning "File does not end in .exe/.msi, attempting launch anyway" ;;
    esac

    print_info "Launching external Windows binary in managed prefix..."
    print_info "File: $exe_path"

    if [ -x "$PROTON_DIR/proton" ]; then
        export STEAM_COMPAT_DATA_PATH="$WINEPREFIX"
        export STEAM_COMPAT_CLIENT_INSTALL_PATH="$WINE_DIR/steam-root"
        export PROTON_LOG=1
        export PROTON_LOG_DIR="$WINE_DIR"
        mkdir -p "$WINE_DIR/steam-root"
        "$PROTON_DIR/proton" run "$exe_path" &
    else
        print_warning "Proton not available, using Wine fallback"
        export WINEDEBUG=-all
        export WINEPREFIX="$WINEPREFIX/pfx"
        wine "$exe_path" &
    fi

    print_success "External launch started (PID: $!)"
}
