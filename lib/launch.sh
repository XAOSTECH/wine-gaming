#!/bin/bash
# lib/launch.sh — App and external-exe launch via Proton/Wine
# Sourced by setup; do not execute directly.
# Depends on: lib/config.sh, lib/utils.sh, lib/registry.sh

# Parse `--profile NAME` out of an argv stream regardless of position.
# Sets globals WG_PARSED_PROFILE and WG_PARSED_ARGS (array of leftovers).
# Usage: _parse_profile_flag "$@"
_parse_profile_flag() {
    WG_PARSED_PROFILE=""
    WG_PARSED_ARGS=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --profile)        WG_PARSED_PROFILE="$2"; shift 2 ;;
            --profile=*)      WG_PARSED_PROFILE="${1#--profile=}"; shift ;;
            *)                WG_PARSED_ARGS+=("$1"); shift ;;
        esac
    done
}

# Launch a registered launcher via Proton (Wine fallback if Proton absent).
# Usage: launch_app [--verbose|-v] [--profile NAME] <app-key>
launch_app() {
    # Strip --verbose/-v before the profile parser sees it
    local _verbose=0 _pre=()
    for _a in "$@"; do
        case "$_a" in --verbose|-v) _verbose=1 ;; *) _pre+=("$_a") ;; esac
    done
    set -- "${_pre[@]}"

    _parse_profile_flag "$@"
    local app_key="${WG_PARSED_ARGS[0]:-}"
    local profile_override="${WG_PARSED_PROFILE}"

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

    # Sensible defaults — overridable by the loaded profile.
    export DXVK_HUD=0
    export VKD3D_SHADER_VERBOSE=0
    export WINEDLLOVERRIDES="winemenubuilder.exe=d"
    export MESA_GL_VERSION_OVERRIDE=4.5
    export __GL_SHADER_DISK_CACHE=1
    export __GL_THREADED_OPTIMIZATION=1

    # Apply default + per-app profile (FPS cap, HUD, FSR, NVAPI, …).
    # If --profile was supplied, that named profile replaces the per-app one.
    if [ -n "$profile_override" ]; then
        load_profile "$profile_override"
        print_info "Profile override: $profile_override"
    else
        load_profile "$app_key"
    fi

    if [ -x "$PROTON_DIR/proton" ]; then
        export STEAM_COMPAT_DATA_PATH="$WINEPREFIX"
        export STEAM_COMPAT_CLIENT_INSTALL_PATH="$WINE_DIR/steam-root"
        export PROTON_LOG="${PROTON_LOG:-1}"
        export PROTON_LOG_DIR="$WINE_DIR"
        export WINEESYNC="${WINEESYNC:-1}" WINEFSYNC="${WINEFSYNC:-1}"
        mkdir -p "$WINEPREFIX"
        _sandbox_z_drive
        _map_external_drives

        cd "$exe_dir"
        local _args="${APP_LAUNCH_ARGS[$app_key]:-}"
        local _env_str="${APP_LAUNCH_ENV[$app_key]:+${APP_LAUNCH_ENV[$app_key]} }"
        if [ "$_verbose" -eq 1 ]; then
            print_info "Verbose mode — Ctrl-C to stop (DXVK capability blocks suppressed)"
            eval "${WG_LAUNCH_PREFIX}${_env_str}\"\$PROTON_DIR/proton\" run \"\$exe_bin\" ${_args}" 2>&1 \
                | awk '
                    /^info:  (Enabled (features|extensions)|Memory:|Descriptor sizes|Creating (sampler|resource descriptor))/{
                        suppressed++; in_block=1; next }
                    in_block && /^info:    /{ suppressed++; next }
                    in_block && !/^info:    /{ in_block=0 }
                    suppressed>0 && !in_block{
                        printf "[note] %d DXVK capability lines suppressed\n", suppressed; suppressed=0 }
                    { print }
                    END{ if(suppressed>0) printf "[note] %d DXVK capability lines suppressed\n", suppressed }
                ' \
                | tee "$WINE_DIR/${app_key}.log"
            print_success "$APP_NAME exited"
            # Auto-show application log on exit so crash reasons are immediately visible
            local _app_log_dir
            case "$app_key" in
                epic-games) _app_log_dir="$WINEPREFIX/pfx/drive_c/users/steamuser/AppData/Local/EpicGamesLauncher/Saved/Logs" ;;
                gog-galaxy) _app_log_dir="$WINEPREFIX/pfx/drive_c/ProgramData/GOG.com/Galaxy/logs" ;;
                ea-desktop) _app_log_dir="$WINEPREFIX/pfx/drive_c/users/steamuser/AppData/Local/Electronic Arts/EA Desktop/Logs" ;;
            esac
            if [ -n "${_app_log_dir:-}" ]; then
                local _latest; _latest=$(ls -t "$_app_log_dir/"*.log 2>/dev/null | head -1)
                if [ -n "$_latest" ]; then
                    print_info "--- $(basename "$_latest") (last 40 lines) ---"
                    tail -40 "$_latest"
                fi
            fi
            return 0
        fi
        eval "${WG_LAUNCH_PREFIX}${_env_str}\"\$PROTON_DIR/proton\" run \"\$exe_bin\" ${_args}" >"$WINE_DIR/${app_key}.log" 2>&1 &
        # Proton wineboot recreates Z:→/ on prefix version upgrades; re-sandbox after it completes.
        ( sleep 2; _sandbox_z_drive ) &
    else
        print_warning "Proton not available, using Wine fallback"
        export WINEDEBUG="${WINEDEBUG:--all}"
        export WINEPREFIX="$WINEPREFIX/pfx"
        cd "$exe_dir"
        if [ "$_verbose" -eq 1 ]; then
            print_info "Verbose mode — Ctrl-C to stop"
            eval "${WG_LAUNCH_PREFIX}wine \"\$exe_bin\"" 2>&1 | tee "$WINE_DIR/${app_key}.log"
            print_success "$APP_NAME exited"
            return 0
        fi
        eval "${WG_LAUNCH_PREFIX}wine \"\$exe_bin\"" >"$WINE_DIR/${app_key}.log" 2>&1 &
    fi

    print_success "$APP_NAME launched (PID: $!) — log: $WINE_DIR/${app_key}.log"
    # Emit diagnostic log paths for apps that have known per-app log directories.
    if [ "$app_key" = "epic-games" ]; then
        local _egl_logs="$WINEPREFIX/pfx/drive_c/users/steamuser/AppData/Local/EpicGamesLauncher/Saved/Logs"
        print_info "Live output : tail -f $WINE_DIR/${app_key}.log"
        print_info "Epic logs   : $_egl_logs"
    fi
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
        mkdir -p "$WINEPREFIX"
        "$PROTON_DIR/proton" run "$exe_path" &
    else
        print_warning "Proton not available, using Wine fallback"
        export WINEDEBUG=-all
        export WINEPREFIX="$WINEPREFIX/pfx"
        wine "$exe_path" &
    fi

    print_success "External launch started (PID: $!)"
}
