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
    eval "${WG_LAUNCH_PREFIX}\"\$PROTON_DIR/proton\" run \"\$EXE_BIN\" ${APP_LAUNCH_ARGS[$APP_KEY]:-}" >"$LOG_FILE" 2>&1 &
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
StartupNotify=false
StartupWMClass=$(basename "$APP_EXE" | sed 's/\.exe$//' | tr '[:upper:]' '[:lower:]')
Icon=$app_icon
Actions=Launch;

[Desktop Action Launch]
Name=Launch
Exec=$launcher
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

# Create a .desktop shortcut for any Windows .exe or .lnk outside the APP_REGISTRY.
# Usage: create_external_shortcut "/path/to/Game.exe" [display_name]
# Icon priority: goggame-*.ico in dir > largest *.ico in dir > extracted from exe PE.
create_external_shortcut() {
    local exe_input="$1"
    local display_name="${2:-}"

    local exe_path
    exe_path=$(readlink -f "$exe_input" 2>/dev/null)
    if [ -z "$exe_path" ] || [ ! -f "$exe_path" ]; then
        print_error "File not found: $exe_input"
        return 1
    fi

    local exe_dir exe_bin ext
    exe_dir=$(dirname "$exe_path")
    exe_bin=$(basename "$exe_path")
    ext="${exe_bin##*.}"

    # Derive a stable key from the parent directory; fall back to exe stem for generic dirs.
    local raw_key
    raw_key=$(basename "$exe_dir" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '-' | tr -cd 'a-z0-9-')
    case "${raw_key}" in
        bin|x64|x86|win64|win32|game|games|"")
            raw_key=$(basename "$exe_bin" ".$ext" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '-' | tr -cd 'a-z0-9-') ;;
    esac
    local app_key="ext-${raw_key:-unknown}"

    if [ -z "$display_name" ]; then
        display_name=$(basename "$exe_dir")
        case "${display_name,,}" in
            bin|x64|x86|win64|win32|game|games) display_name=$(basename "$exe_bin" ".$ext") ;;
        esac
    fi

    local icon_dir="${HOME}/.local/share/icons/wine-gaming"
    mkdir -p "$icon_dir"
    local app_icon="application-x-ms-dos-executable"
    local src_ico="" _f _sz _best_sz=0

    # 1. GOG per-game icon — every GOG install drops goggame-<id>.ico next to the exe.
    src_ico=$(find "$exe_dir" -maxdepth 1 -name "goggame-*.ico" -print 2>/dev/null | head -1)

    # 2. Largest *.ico in the same directory (other publishers, Steam, etc.)
    if [ -z "$src_ico" ]; then
        while IFS= read -r -d '' _f; do
            _sz=$(stat -c%s "$_f" 2>/dev/null || echo 0)
            (( _sz > _best_sz )) && { _best_sz=$_sz; src_ico="$_f"; }
        done < <(find "$exe_dir" -maxdepth 1 -name "*.ico" -print0 2>/dev/null)
    fi

    if [ -n "$src_ico" ]; then
        local work_dir; work_dir=$(mktemp -d)
        if command -v icotool &>/dev/null && icotool -x -o "$work_dir" "$src_ico" 2>/dev/null; then
            local best_png="" best_png_sz=0
            while IFS= read -r -d '' _f; do
                _sz=$(stat -c%s "$_f" 2>/dev/null || echo 0)
                (( _sz > best_png_sz )) && { best_png_sz=$_sz; best_png="$_f"; }
            done < <(find "$work_dir" -name "*.png" -print0 2>/dev/null)
            if [ -n "$best_png" ]; then
                cp "$best_png" "${icon_dir}/${app_key}.png"
                app_icon="${icon_dir}/${app_key}.png"
            fi
        fi
        rm -rf "$work_dir"
        if [ "$app_icon" = "application-x-ms-dos-executable" ]; then
            cp "$src_ico" "${icon_dir}/${app_key}.ico"
            app_icon="${icon_dir}/${app_key}.ico"
        fi
    fi

    # 3. Fall back to extracting the icon from the exe's PE resources.
    if [ "$app_icon" = "application-x-ms-dos-executable" ] && [ "${ext,,}" = "exe" ]; then
        local extracted
        extracted=$(extract_exe_icon "$app_key" "$exe_path")
        [ -n "$extracted" ] && app_icon="$extracted"
    fi

    # GOG: goggame-*.info marks a GOG game; prefer GalaxyClient for auth/DRM/overlay.
    local launch_exe="$exe_bin" launch_dir="$exe_dir" launch_args=""
    local gog_info
    gog_info=$(find "$exe_dir" -maxdepth 1 -name "goggame-*.info" 2>/dev/null | head -1)
    if [ -n "$gog_info" ]; then
        local gog_id; gog_id=$(basename "$gog_info" | sed 's/goggame-//;s/\.info//')
        if command -v python3 &>/dev/null && [ -z "${2:-}" ]; then
            local json_name
            json_name=$(python3 -c "
import json,sys
try:
    d=json.load(open(sys.argv[1]))
    print(d.get('name',''))
except: pass
" "$gog_info" 2>/dev/null)
            [ -n "$json_name" ] && display_name="$json_name"
        fi
        local galaxy_exe="$WINEPREFIX/pfx/drive_c/Program Files (x86)/GOG Galaxy/GalaxyClient.exe"
        if [ -f "$galaxy_exe" ]; then
            launch_exe="GalaxyClient.exe"
            launch_dir="$WINEPREFIX/pfx/drive_c/Program Files (x86)/GOG Galaxy"
            launch_args="/command=runGame /gameId=${gog_id}"
            print_info "GOG game ID ${gog_id} — launching via GalaxyClient"
        else
            print_warning "GOG Galaxy not found in prefix; launching game exe directly"
        fi
    fi

    local launcher="$BIN_DIR/${app_key}"
    local desktop="$APPS_DIR/${app_key}.desktop"

    # Self-contained wrapper — paths baked in at generation time; no parse_app_config needed.
    cat > "$launcher" <<LAUNCHER_EOF
#!/bin/bash
_dd="${WINEPREFIX}/pfx/dosdevices"
export STEAM_COMPAT_DATA_PATH="${WINEPREFIX}"
export STEAM_COMPAT_CLIENT_INSTALL_PATH="${WINE_DIR}/steam-root"
export PROTON_LOG=1 PROTON_LOG_DIR="${WINE_DIR}"
export WINEDLLOVERRIDES="winemenubuilder.exe=d"
export WINEESYNC="\${WINEESYNC:-1}" WINEFSYNC="\${WINEFSYNC:-1}"

[ -d "\${_dd}" ] && rm -f "\${_dd}/z:" "\${_dd}/z::" 2>/dev/null || true
cd "${launch_dir}" || exit 1
"${PROTON_DIR}/proton" run "${launch_exe}" ${launch_args} >"${WINE_DIR}/${app_key}.log" 2>&1 &
( _i=0; while [ \${_i} -lt 20 ]; do rm -f "\${_dd}/z:" "\${_dd}/z::" 2>/dev/null; sleep 0.5; _i=\$((\${_i}+1)); done ) &
LAUNCHER_EOF
    chmod +x "$launcher"

    cat > "$desktop" <<DESKTOP_EOF
[Desktop Entry]
Name=${display_name}
Exec=${launcher}
Type=Application
Categories=Game;
Terminal=false
StartupNotify=false
Icon=${app_icon}
Actions=Launch;

[Desktop Action Launch]
Name=Launch
Exec=${launcher}
DESKTOP_EOF

    chmod 644 "$desktop"
    command -v update-desktop-database &>/dev/null \
        && update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true

    print_success "Shortcut created: ${display_name}"
    print_info "Key: ${app_key}  |  Icon: $(basename "${app_icon}")"
}

# Scan a path (or default prefix + common GOG locations) for GOG games and Windows .lnk
# shortcuts, then create Proton-based .desktop entries for each discovered game.
# Usage: scan_shortcuts [path]
scan_shortcuts() {
    local scan_arg="${1:-}"
    local created=0 skipped=0

    print_info "Scanning for GOG games and Windows shortcuts..."

    # Build list of directories to search
    local -a roots=()
    if [ -n "$scan_arg" ]; then
        roots=("$scan_arg")
    else
        for d in \
            "$WINEPREFIX/pfx/drive_c/users/steamuser/Desktop" \
            "$WINEPREFIX/pfx/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs" \
            "${HOME}/Games" "${HOME}/GOG Games" "${HOME}/Games/GOG Galaxy"; do
            [ -d "$d" ] && roots+=("$d")
        done
    fi

    if [ ${#roots[@]} -eq 0 ]; then
        print_warning "No directories to scan. Try: wig scan-shortcuts /path/to/games/"
        return 1
    fi

    # Track processed dirs to avoid duplicate shortcuts from .lnk + goggame-*.info in same dir
    local -A _seen=()

    # Pass 1: GOG game directories identified by goggame-*.info
    while IFS= read -r -d '' info_file; do
        local game_dir; game_dir=$(dirname "$info_file")
        [[ -n "${_seen[$game_dir]:-}" ]] && continue
        _seen[$game_dir]=1

        # Parse primary play task exe from the info JSON
        local primary_exe=""
        if command -v python3 &>/dev/null; then
            primary_exe=$(python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    for t in d.get('playTasks', []):
        if t.get('isPrimary') and t.get('type') == 'FileTask':
            print(t.get('path', '').replace('\\\\\\\\', '/').strip('/'))
            break
except: pass
" "$info_file" 2>/dev/null)
        fi

        # Fallback: largest .exe in the game dir
        if [ -z "$primary_exe" ] || [ ! -f "$game_dir/$primary_exe" ]; then
            local _bf="" _bsz=0 _f _sz
            while IFS= read -r -d '' _f; do
                _sz=$(stat -c%s "$_f" 2>/dev/null || echo 0)
                (( _sz > _bsz )) && { _bsz=$_sz; _bf="$_f"; }
            done < <(find "$game_dir" -maxdepth 1 -name "*.exe" -print0 2>/dev/null)
            [ -n "$_bf" ] && primary_exe=$(basename "$_bf")
        fi

        if [ -n "$primary_exe" ] && [ -f "$game_dir/$primary_exe" ]; then
            print_info "GOG game: $(basename "$game_dir") → $primary_exe"
            create_external_shortcut "$game_dir/$primary_exe" && ((created++)) || ((skipped++))
        fi
    done < <(find "${roots[@]}" -name "goggame-*.info" -print0 2>/dev/null)

    # Pass 2: Windows .lnk shortcuts not already covered by goggame detection
    while IFS= read -r -d '' lnk; do
        local lnk_dir; lnk_dir=$(dirname "$lnk")
        [[ -n "${_seen[$lnk_dir]:-}" ]] && continue
        local lnk_name; lnk_name=$(basename "$lnk" .lnk)
        case "${lnk_name,,}" in
            "gog galaxy"|"gog launcher"|"gog galaxy updater") continue ;;
        esac
        print_info "LNK: $lnk_name"
        create_external_shortcut "$lnk" "$lnk_name" && ((created++)) || ((skipped++))
    done < <(find "${roots[@]}" -name "*.lnk" -print0 2>/dev/null)

    if (( created + skipped == 0 )); then
        print_warning "No games found. Try specifying the games directory: wig scan-shortcuts /path/to/games/"
    else
        print_success "Scan complete — created: $created  skipped/failed: $skipped"
    fi
}
