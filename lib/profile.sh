#!/bin/bash
# lib/profile.sh — Per-app launch profiles (FPS cap, VSync, HUD, frame-gen, …)
# Sourced by setup; do not execute directly.
# Depends on: lib/config.sh, lib/utils.sh, lib/registry.sh
#
# Profile files live at:
#   $WINE_DIR/profiles/default.conf       — applied to every launch
#   $WINE_DIR/profiles/<app-key>.conf     — overrides default
#
# Format: plain shell KEY=VALUE lines (sourceable). Comments allowed.
# Any KEY/VALUE pair may be set; this module ships a curated menu of well-known
# DXVK / VKD3D / Wine / Proton / NVAPI knobs but does not restrict the set.

# XDG-compliant config location. Migrates legacy $WINE_DIR/profiles on first run.
WG_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/wine-gaming"
PROFILE_DIR="${WG_CONFIG_DIR}/profiles"
mkdir -p "$PROFILE_DIR" 2>/dev/null || true

# One-shot migration from legacy ~/.wine-gaming/profiles → XDG.
_legacy_profile_dir="${WINE_DIR}/profiles"
if [ -d "$_legacy_profile_dir" ] && [ "$_legacy_profile_dir" != "$PROFILE_DIR" ]; then
    if compgen -G "$_legacy_profile_dir/*.conf" >/dev/null; then
        mv -n "$_legacy_profile_dir"/*.conf "$PROFILE_DIR/" 2>/dev/null || true
    fi
    rmdir "$_legacy_profile_dir" 2>/dev/null || true
fi
unset _legacy_profile_dir

# Curated knob catalogue used by the interactive menu and `set`/`unset` validation.
# Format: [KEY]="Human description"
declare -A PROFILE_KNOBS=(
    [DXVK_FRAME_RATE]="Hard FPS cap for D3D9/10/11 games (0 = uncapped)"
    [VKD3D_FRAME_RATE]="Hard FPS cap for D3D12 games via VKD3D-Proton (0 = uncapped)"
    [DXVK_HUD]="Overlay: fps,frametimes,gpuload,memory,version,api,scale=1.5 (or 0)"
    [DXVK_ASYNC]="Async shader compile, less stutter (1/0). Needs dxvk-async/gplasync"
    [DXVK_FILTER_ANISOTROPY]="Force anisotropic filter level: 0/2/4/8/16"
    [DXVK_ENABLE_NVAPI]="Expose NVAPI to game (1/0) — required for DLSS / Reflex"
    [PROTON_ENABLE_NVAPI]="Proton-side NVAPI enable (1/0)"
    [PROTON_HIDE_NVIDIA_GPU]="Pretend GPU is non-NVIDIA (1/0)"
    [DXVK_NVAPI_DRS_NGX_DLSS_FG]="DLSS Frame Generation override (on/off/default)"
    [WINE_FULLSCREEN_FSR]="AMD FSR upscaling in fullscreen (1/0)"
    [WINE_FULLSCREEN_FSR_STRENGTH]="FSR sharpness 0–5 (lower = sharper)"
    [WINE_FULLSCREEN_FSR_MODE]="FSR quality: ultra|quality|balanced|performance"
    [__GL_SYNC_TO_VBLANK]="NVIDIA driver VSync (1/0)"
    [__GL_THREADED_OPTIMIZATION]="NVIDIA threaded GL (1/0)"
    [MANGOHUD]="Wrap launch with MangoHud overlay (1/0)"
    [MANGOHUD_CONFIG]="MangoHud config string e.g. fps_limit=60,gpu_temp,cpu_temp"
    [GAMEMODE]="Wrap launch with gamemoderun (1/0) — needs gamemode installed"
    [PROTON_LOG]="Verbose Proton logging (1/0)"
    [WINEDEBUG]="Wine debug channels e.g. -all, +seh, fixme-all"
    [WINEDLLOVERRIDES]="DLL overrides e.g. mscoree=n,b;crashreportclient.exe=d"
)

# Resolve which profile file applies to an app key.
# Echoes path (may not exist).
_profile_path() {
    echo "$PROFILE_DIR/${1:-default}.conf"
}

# Load default + per-app profile into the current shell environment.
# Special handling: GAMEMODE/MANGOHUD become wrapper hints exported as
# WG_LAUNCH_PREFIX so the caller can prepend `gamemoderun mangohud …`.
# Usage: load_profile "app-key"   (or load_profile "" for default only)
load_profile() {
    local app_key="$1"
    local default_file per_app_file
    default_file=$(_profile_path "default")
    per_app_file=$(_profile_path "$app_key")

    WG_LAUNCH_PREFIX=""

    local f
    for f in "$default_file" "$per_app_file"; do
        [ -f "$f" ] || continue
        # Read KEY=VAL lines; export each. Skip blanks and comments.
        local line key val
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line%%#*}"                      # strip trailing comment
            line="${line#"${line%%[![:space:]]*}"}"  # ltrim
            line="${line%"${line##*[![:space:]]}"}"  # rtrim
            [ -z "$line" ] && continue
            [[ "$line" != *=* ]] && continue
            key="${line%%=*}"
            val="${line#*=}"
            # strip optional surrounding quotes
            val="${val%\"}"; val="${val#\"}"
            val="${val%\'}"; val="${val#\'}"
            export "$key=$val"
        done < "$f"
    done

    # Translate wrapper-style knobs into a command prefix.
    if [ "${GAMEMODE:-0}" = "1" ] && command -v gamemoderun &>/dev/null; then
        WG_LAUNCH_PREFIX+="gamemoderun "
    fi
    if [ "${MANGOHUD:-0}" = "1" ] && command -v mangohud &>/dev/null; then
        WG_LAUNCH_PREFIX+="mangohud "
    fi
    export WG_LAUNCH_PREFIX
}

# Print the merged profile (default + per-app) without exporting.
# Usage: show_profile [app-key]
show_profile() {
    local app_key="${1:-}"
    local default_file per_app_file
    default_file=$(_profile_path "default")
    per_app_file=$(_profile_path "$app_key")

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "wine-gaming — Profile: ${app_key:-default}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Default file: $default_file $([ -f "$default_file" ] && echo "(exists)" || echo "(none)")"
    if [ -n "$app_key" ]; then
        echo "Per-app file: $per_app_file $([ -f "$per_app_file" ] && echo "(exists)" || echo "(none)")"
    fi
    echo ""
    echo "Effective settings (default → per-app overrides):"
    (
        load_profile "$app_key" >/dev/null 2>&1
        local k
        for k in "${!PROFILE_KNOBS[@]}"; do
            local v="${!k:-}"
            [ -n "$v" ] && printf "  %-30s = %s\n" "$k" "$v"
        done
        # Also surface non-catalogued vars present in the files
        local f
        for f in "$default_file" "$per_app_file"; do
            [ -f "$f" ] || continue
            local line key
            while IFS= read -r line || [ -n "$line" ]; do
                line="${line%%#*}"
                key="${line%%=*}"
                key="${key#"${key%%[![:space:]]*}"}"
                key="${key%"${key##*[![:space:]]}"}"
                [ -z "$key" ] && continue
                [[ -n "${PROFILE_KNOBS[$key]:-}" ]] && continue
                local v="${!key:-}"
                [ -n "$v" ] && printf "  %-30s = %s   (custom)\n" "$key" "$v"
            done < "$f"
        done
    )
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Set a KEY=VALUE pair in a profile file (creates if missing).
# Usage: set_profile_value [app-key] KEY=VALUE [KEY=VALUE ...]
set_profile_value() {
    local app_key="$1"; shift
    local file
    file=$(_profile_path "$app_key")
    touch "$file"

    local pair key val
    for pair in "$@"; do
        if [[ "$pair" != *=* ]]; then
            print_error "Expected KEY=VALUE, got: $pair"
            return 1
        fi
        key="${pair%%=*}"
        val="${pair#*=}"
        # Replace existing line or append
        if grep -qE "^[[:space:]]*${key}=" "$file" 2>/dev/null; then
            sed -i "s|^[[:space:]]*${key}=.*|${key}=${val}|" "$file"
        else
            echo "${key}=${val}" >> "$file"
        fi
        print_success "${app_key:-default}: ${key}=${val}"
    done
}

# Remove a key from a profile file.
# Usage: unset_profile_value [app-key] KEY [KEY ...]
unset_profile_value() {
    local app_key="$1"; shift
    local file
    file=$(_profile_path "$app_key")
    [ -f "$file" ] || { print_warning "Profile not found: $file"; return 0; }

    local key
    for key in "$@"; do
        sed -i "/^[[:space:]]*${key}=/d" "$file"
        print_success "${app_key:-default}: removed $key"
    done
}

# List all profile files.
list_profiles() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "wine-gaming — Profiles in $PROFILE_DIR"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    local count=0 f
    for f in "$PROFILE_DIR"/*.conf; do
        [ -f "$f" ] || continue
        local name
        name=$(basename "$f" .conf)
        local lines
        lines=$(grep -cE '^[[:space:]]*[A-Z_]+=' "$f" 2>/dev/null || echo 0)
        printf "  %-20s (%d settings)\n" "$name" "$lines"
        ((count++))
    done
    [ "$count" -eq 0 ] && echo "  (no profiles yet — try: wig profile menu)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Open a profile file in $EDITOR (or nano).
edit_profile() {
    local app_key="${1:-default}"
    local file
    file=$(_profile_path "$app_key")
    touch "$file"
    "${EDITOR:-nano}" "$file"
}

# Delete a profile file.
reset_profile() {
    local app_key="${1:-default}"
    local file
    file=$(_profile_path "$app_key")
    if [ -f "$file" ]; then
        rm -f "$file"
        print_success "Profile reset: $app_key"
    else
        print_warning "No profile to reset: $app_key"
    fi
}

# Interactive menu for the curated knob catalogue.
# Usage: profile_menu [app-key]
profile_menu() {
    local app_key="${1:-default}"
    local file
    file=$(_profile_path "$app_key")
    touch "$file"

    while true; do
        clear 2>/dev/null || true
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  wine-gaming — Profile Menu  [${app_key}]"
        echo "  File: $file"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        # Stable ordering for menu numbering.
        local keys=(
            DXVK_FRAME_RATE
            VKD3D_FRAME_RATE
            DXVK_HUD
            DXVK_ASYNC
            DXVK_FILTER_ANISOTROPY
            DXVK_ENABLE_NVAPI
            PROTON_ENABLE_NVAPI
            DXVK_NVAPI_DRS_NGX_DLSS_FG
            WINE_FULLSCREEN_FSR
            WINE_FULLSCREEN_FSR_STRENGTH
            WINE_FULLSCREEN_FSR_MODE
            __GL_SYNC_TO_VBLANK
            __GL_THREADED_OPTIMIZATION
            MANGOHUD
            MANGOHUD_CONFIG
            GAMEMODE
            PROTON_LOG
            WINEDEBUG
            WINEDLLOVERRIDES
        )

        local i=1 k cur
        for k in "${keys[@]}"; do
            cur=$(grep -E "^[[:space:]]*${k}=" "$file" 2>/dev/null | tail -1 | cut -d= -f2-)
            printf "  %2d) %-30s  [%s]\n      %s\n" "$i" "$k" "${cur:-unset}" "${PROFILE_KNOBS[$k]}"
            ((i++))
        done
        echo ""
        echo "   s) show effective profile     e) edit raw file"
        echo "   r) reset (delete) profile     q) quit"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        read -r -p "Choose [1-${#keys[@]} / s / e / r / q]: " choice

        case "$choice" in
            q|Q|"") return 0 ;;
            s|S)    show_profile "$app_key"; read -r -p "Press Enter…" _ ;;
            e|E)    edit_profile "$app_key" ;;
            r|R)
                read -r -p "Delete $file? [y/N]: " confirm
                [[ "$confirm" =~ ^[yY] ]] && reset_profile "$app_key" && touch "$file"
                ;;
            ''|*[!0-9]*)
                print_warning "Invalid choice"; sleep 1 ;;
            *)
                if (( choice >= 1 && choice <= ${#keys[@]} )); then
                    local sel="${keys[$((choice-1))]}"
                    local cur_val
                    cur_val=$(grep -E "^[[:space:]]*${sel}=" "$file" 2>/dev/null | tail -1 | cut -d= -f2-)
                    echo ""
                    echo "  $sel — ${PROFILE_KNOBS[$sel]}"
                    echo "  current: ${cur_val:-unset}"
                    read -r -p "  new value (empty = unset): " newval
                    if [ -z "$newval" ]; then
                        unset_profile_value "$app_key" "$sel"
                    else
                        set_profile_value "$app_key" "${sel}=${newval}"
                    fi
                    sleep 1
                else
                    print_warning "Out of range"; sleep 1
                fi
                ;;
        esac
    done
}

# Top-level dispatch for the `profile` subcommand.
# Usage: profile_dispatch <subcmd> [args…]
profile_dispatch() {
    local sub="${1:-show}"; shift || true
    case "$sub" in
        show)    show_profile "${1:-}" ;;
        list)    list_profiles ;;
        set)
            local app="$1"; shift || true
            if [ -z "$app" ] || [[ "$app" == *=* ]]; then
                # No app key given — first arg was a KEY=VAL → target default
                [ -n "$app" ] && set -- "$app" "$@"
                set_profile_value "default" "$@"
            else
                set_profile_value "$app" "$@"
            fi
            ;;
        unset)
            local app="$1"; shift || true
            if [ -z "$app" ] || [[ "$app" != *[!A-Z_0-9]* && -z "${APP_REGISTRY[$app]:-}" && "$app" != "default" ]]; then
                # Heuristic: looks like a bare KEY → target default
                [ -n "$app" ] && set -- "$app" "$@"
                unset_profile_value "default" "$@"
            else
                unset_profile_value "$app" "$@"
            fi
            ;;
        edit)    edit_profile "${1:-default}" ;;
        reset)   reset_profile "${1:-default}" ;;
        menu)    profile_menu "${1:-default}" ;;
        help|-h|--help|"")
            cat <<'PROFILE_HELP'
wig profile — per-app launch profiles

  profile menu  [app-key]            Interactive editor (recommended)
  profile show  [app-key]            Show effective settings
  profile list                       List all profiles
  profile set   [app-key] KEY=VAL …  Set one or more values (default if no key)
  profile unset [app-key] KEY …      Remove keys
  profile edit  [app-key]            Open raw file in $EDITOR
  profile reset [app-key]            Delete the profile file

EXAMPLES
  wig profile set DXVK_FRAME_RATE=60                  # global cap
  wig profile set ubisoft-connect DXVK_FRAME_RATE=120 # per-launcher override (inherited by all its games)
  wig profile set epic-games WINEDLLOVERRIDES=crashreportclient.exe=d
  wig profile menu epic-games

Files: ~/.wine-gaming/profiles/<app-key>.conf  (default.conf is global)
PROFILE_HELP
            ;;
        *) print_error "Unknown profile subcommand: $sub"; return 1 ;;
    esac
}
