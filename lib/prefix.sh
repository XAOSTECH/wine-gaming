#!/bin/bash
# lib/prefix.sh — Wine prefix lifecycle and Proton management
# Sourced by setup; do not execute directly.
# Depends on: lib/config.sh, lib/utils.sh, lib/registry.sh, lib/installer.sh, lib/apps.sh

# Curated winetricks verb list, split into "fast" (seconds each) and "heavy"
# (minutes each, downloads MS installers). Streams output verbatim so the user
# sees winetricks progress instead of a silent hang during dotnet/physx.
_install_winetricks_verbs() {
    local fast_verbs=(
        vcrun2022 vcrun2019 vcrun2015 vcrun2012
        d3dcompiler_47 d3dcompiler_43 d3dx9 d3dx10_43 d3dx11_43
        corefonts gdiplus cacerts
        directmusic faudio xact directplay directshow
        msctf
        gamemode
    )
    local heavy_verbs=( dotnet48 dotnet472 physx )

    # Winetricks must target Proton's pfx/ prefix — not the bare STEAM_COMPAT_DATA_PATH.
    local _wt_prefix="$WINEPREFIX/pfx"
    if [ ! -d "$_wt_prefix/drive_c/windows/system32" ]; then
        print_warning "Skipping winetricks: Proton prefix not yet initialised."
        print_info "Run 'wig install <app>' first, then 'wig init' for verbs."
        return 0
    fi

    local _wine_bin="wine"
    for _c in "$PROTON_DIR/files/bin/wine64" "$PROTON_DIR/files/bin/wine"; do
        [ -x "$_c" ] && { _wine_bin="$_c"; break; }
    done

    # Subshell isolates Proton wine env from the rest of the script.
    (
        export WINE="$_wine_bin"
        export WINESERVER="$(dirname "$_wine_bin")/wineserver"
        export PATH="$(dirname "$_wine_bin"):$PATH"
        export WINEPREFIX="$_wt_prefix"
        [ -d "$PROTON_DIR/files/lib64" ] && \
            export LD_LIBRARY_PATH="$PROTON_DIR/files/lib:$PROTON_DIR/files/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

        print_info "Installing fast winetricks verbs (${#fast_verbs[@]} packages)..."
        local v
        for v in "${fast_verbs[@]}"; do
            printf "  → %s ... " "$v"
            if WINETRICKS_LATEST_VERSION_CHECK=disabled \
                    winetricks -q --force "$v" >/dev/null 2>&1; then
                echo "ok"
            else
                echo "FAILED (continuing)"
            fi
        done

        print_warning "Installing heavy verbs (${heavy_verbs[*]}) — each may take several minutes"
        print_info "Output is streamed below; press Ctrl-C to skip a verb."
        for v in "${heavy_verbs[@]}"; do
            echo ""
            print_info "winetricks → $v"
            WINETRICKS_LATEST_VERSION_CHECK=disabled \
                winetricks -q --force "$v" 2>&1 \
                | grep -Ev "^warning:|winetricks latest version|^Executing cd|^-{10,}\$|^WINEPREFIX INFO:|Drive C:|^[dl-][-rwx]{9} |^Registry info:|/#arch=|^\$" \
                || print_warning "$v failed or was skipped — continuing"
        done
    )
}

# Print the managed prefix paths and env-var exports for manual use.
prefix_info() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "wine-gaming — Managed Runtime"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "WINE_DIR:                 $WINE_DIR"
    echo "STEAM_COMPAT_DATA_PATH:   $WINEPREFIX"
    echo "Managed Wine prefix:      $WINEPREFIX/pfx"
    echo "Proton binary:            $PROTON_DIR/proton"
    echo "Generated launchers:      $BIN_DIR"
    echo ""
    echo "To reuse this prefix for manual Wine commands:"
    echo "  export WINE_DIR=\"$WINE_DIR\""
    echo "  export STEAM_COMPAT_DATA_PATH=\"$WINEPREFIX\""
    echo "  export WINEPREFIX=\"$WINEPREFIX/pfx\""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Wipe the Wine prefix entirely.
purge() {
    print_warning "Purging Wine prefix at $WINEPREFIX..."
    if [ -d "$WINEPREFIX" ]; then
        rm -rf "$WINEPREFIX"
        print_success "Wine prefix purged"
    else
        print_info "Wine prefix not found (already clean)"
    fi
}

# Back up essential DLLs and winetricks packages.
backup() {
    print_info "Backing up essential packages..."

    if [ -d "$WINEPREFIX/drive_c/windows/system32" ]; then
        find "$WINEPREFIX/drive_c/windows/system32" \
            \( -name "d3d*.dll" -o -name "vcruntime*.dll" \
               -o -name "msvcp*.dll" -o -name "ucrtbase*.dll" \) 2>/dev/null \
            | xargs -I {} cp {} "$BACKUP_DIR/" 2>/dev/null || true
    fi

    if [ -d "$CACHE_DIR" ]; then
        for pkg in vcrun2019 d3dcompiler_47 dxvk vkd3d; do
            [ -d "$CACHE_DIR/$pkg" ] && cp -r "$CACHE_DIR/$pkg" "$BACKUP_DIR/" 2>/dev/null || true
        done
    fi

    print_success "Backup complete at $BACKUP_DIR"
}

# Restore DLLs from the backup directory.
restore() {
    print_info "Restoring from backup..."

    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR")" ]; then
        print_warning "No backup found, skipping restore"
        return 1
    fi

    [ -d "$WINEPREFIX/drive_c/windows/system32" ] && \
        cp -r "$BACKUP_DIR"/*.dll "$WINEPREFIX/drive_c/windows/system32/" 2>/dev/null || true

    print_success "Restored from backup"
    return 0
}

# Back up all launcher profile/login data from the Proton prefix.
# Stored as $BACKUP_DIR/launcher-data-YYYYMMDD-HHMMSS.tar.gz.
backup_launcher_data() {
    local prefix_c="$WINEPREFIX/pfx/drive_c"
    if [ ! -d "$prefix_c" ]; then
        print_error "Proton prefix not initialised (no drive_c)"
        return 1
    fi

    local -a data_dirs=(
        "users/steamuser/AppData/Local/GOG.com"
        "users/steamuser/AppData/Roaming/GOG.com"
        "ProgramData/GOG.com"
        "users/steamuser/AppData/Local/EpicGamesLauncher"
        "ProgramData/Epic"
        "users/steamuser/AppData/Local/Electronic Arts"
        "users/steamuser/AppData/Roaming/Electronic Arts"
        "users/steamuser/AppData/Local/Ubisoft"
        "users/steamuser/AppData/Roaming/Ubisoft"
        "users/steamuser/AppData/Local/Amazon Games"
        "users/steamuser/AppData/Roaming/Amazon Games"
        "users/steamuser/AppData/Local/Programs/legacy-games-launcher"
        "users/steamuser/AppData/Roaming/Legacy Games Launcher"
    )

    local -a present=()
    for d in "${data_dirs[@]}"; do
        [ -d "$prefix_c/$d" ] && present+=("$d")
    done

    if [ ${#present[@]} -eq 0 ]; then
        print_warning "No launcher data directories found to back up"
        return 0
    fi

    mkdir -p "$BACKUP_DIR"
    local archive="$BACKUP_DIR/launcher-data-$(date +%Y%m%d-%H%M%S).tar.gz"
    local _est; _est=$(cd "$prefix_c" && du -sch "${present[@]}" 2>/dev/null | tail -1 | awk '{print $1}')
    print_info "Backing up ${#present[@]} launcher data directories (~${_est:-?}) — this may take a while for large libraries..."
    (cd "$prefix_c" && tar -czf "$archive" "${present[@]}" 2>/dev/null)
    local size; size=$(du -sh "$archive" 2>/dev/null | cut -f1)
    print_success "Launcher data backed up: $archive ($size)"
    printf '    %s\n' "${present[@]}"
}

# List available launcher data backups.
list_launcher_backups() {
    local -a backups
    mapfile -t backups < <(ls -1t "$BACKUP_DIR"/launcher-data-*.tar.gz 2>/dev/null)
    if [ ${#backups[@]} -eq 0 ]; then
        print_info "No launcher data backups in $BACKUP_DIR"
        return 0
    fi
    echo "│ Launcher data backups (newest first):"
    for b in "${backups[@]}"; do
        local sz; sz=$(du -sh "$b" 2>/dev/null | cut -f1)
        printf '  %-55s %s\n' "$(basename "$b")" "($sz)"
    done
    echo "│ Restore: wig restore-data [backup-name-fragment]"
}

# Restore launcher data from a backup archive.
# Usage: restore_launcher_data [--auto] [name-fragment]  (default: most recent)
restore_launcher_data() {
    local _auto=0
    [ "${1:-}" = "--auto" ] && { _auto=1; shift; }
    local target_arg="${1:-}"
    local prefix_c="$WINEPREFIX/pfx/drive_c"
    local -a backups
    mapfile -t backups < <(ls -1t "$BACKUP_DIR"/launcher-data-*.tar.gz 2>/dev/null)

    if [ ${#backups[@]} -eq 0 ]; then
        print_error "No launcher data backups found in $BACKUP_DIR"
        return 1
    fi

    local target
    if [ -z "$target_arg" ]; then
        target="${backups[0]}"
        print_info "Using most recent backup: $(basename "$target")"
    else
        for b in "${backups[@]}"; do
            [[ "$b" == *"$target_arg"* ]] && { target="$b"; break; }
        done
        if [ -z "${target:-}" ]; then
            print_error "No backup matching '$target_arg'"
            list_launcher_backups
            return 1
        fi
    fi

    if [ "$_auto" -eq 0 ]; then
        print_warning "Restoring will overwrite current launcher data from: $(basename "$target")"
        print_warning "Press Enter to continue (Ctrl-C to abort)..."
        read -r _
    fi

    mkdir -p "$prefix_c"
    tar -xzf "$target" -C "$prefix_c" || { print_error "Restore failed"; return 1; }
    print_success "Launcher data restored from $(basename "$target")"
}

# Initialise a fresh Wine prefix with all required dependencies.
init() {
    if [ -d "${WINEPREFIX:-}" ]; then
        print_info "Prefix already exists at $WINEPREFIX — re-running dependencies non-destructively"
        print_info "(Use './setup full' to start completely fresh)"
    else
        print_info "Initialising Wine prefix..."
    fi

    # Install system-level apt packages required by wine-gaming tooling.
    # icoutils:    wrestool + icotool — extract and convert .exe icons for desktop shortcuts.
    # gamemode:    gamemoderun wrapper — CPU governor + niceness tuning for games.
    # mangohud:    in-game perf overlay (FPS, frametime, GPU/CPU); also enforces fps_limit.
    print_info "Installing system dependencies (apt)..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get install -y icoutils gamemode mangohud winetricks 2>&1 \
            | grep -v "^Reading\|^Building\|^(Reading\|^Selecting\|^Setting\|^Preparing" || true
    else
        print_warning "apt-get not available — skipping system package install"
    fi

    # Download winetricks directly if apt didn't install it (e.g. sudo auth failure).
    if ! command -v winetricks &>/dev/null; then
        print_info "winetricks not in PATH; downloading to ~/.local/bin (no sudo needed)..."
        mkdir -p "${HOME}/.local/bin"
        if wget -q -O "${HOME}/.local/bin/winetricks" \
                "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks" \
                && chmod +x "${HOME}/.local/bin/winetricks"; then
            export PATH="${HOME}/.local/bin:${PATH}"
            print_success "winetricks installed to ~/.local/bin/winetricks"
        else
            print_warning "winetricks download failed — verb installation will be skipped"
        fi
    fi

    mkdir -p "${HOME}/.config/winetricks"
    touch "${HOME}/.config/winetricks/enable-latest-version-check"

    wineboot -u 2>/dev/null

    _install_winetricks_verbs

    print_info "Configuring Wine environment..."
    wine winecfg /v win10 >/dev/null 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v "VideoMemorySize" /t REG_SZ /d "8192" /f >/dev/null 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v "CSMT"           /t REG_SZ /d "enabled" /f >/dev/null 2>&1 || true

    print_success "Wine prefix initialised"

    # Auto-install the wig wrapper and aliases so wine-gaming commands work globally.
    if [ -n "${SETUP_SCRIPT_PATH:-}" ] && [ -f "${SETUP_SCRIPT_PATH:-}" ]; then
        echo ""
        install_aliases
    fi
}

# Helper: install one app with local-installer preference.
_install_with_fallback() {
    local app_key="$1"
    local local_installer
    local_installer=$(find_local_installer "$app_key" 2>/dev/null)

    if [ -n "$local_installer" ] && [ -f "$local_installer" ]; then
        print_info "Found local installer: $(basename "$local_installer")"
        install_app "$app_key" "$local_installer"
    else
        install_app "$app_key"
    fi
}

# Full setup: purge → init → install all launchers.
full_setup() {
    print_info "Running full setup..."

    # If a prefix already exists, back up launcher sessions before wiping.
    local _had_data=0
    if [ -d "$WINEPREFIX/pfx/drive_c" ]; then
        print_info "Preserving launcher data before purge (instant move — no compression)..."
        _stash_launcher_data && _had_data=1 || true
    fi

    purge
    init "$@"
    backup

    print_info "Installing all registered launchers..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local succeeded=0 failed=0 failed_apps=""

    for app_key in "${!APP_REGISTRY[@]}"; do
        parse_app_config "$app_key" || continue
        print_info "Installing $app_key..."
        if _install_with_fallback "$app_key"; then
            ((succeeded++))
        else
            ((failed++))
            failed_apps="$failed_apps\n  - $app_key"
        fi
    done

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_info "Full Setup Summary: Successful=$succeeded  Failed=$failed"
    [ "$failed" -gt 0 ] && echo -e "  Failed apps:$failed_apps"

    if [ "$_had_data" -eq 1 ]; then
        print_info "Restoring launcher sessions..."
        _unstash_launcher_data || true
    fi

    print_success "Full setup complete"
}

# Quick setup: re-run dependencies non-destructively, install any missing launchers.
quick_setup() {
    print_info "Running quick setup..."

    if [ ! -d "$WINEPREFIX" ]; then
        print_warning "Wine prefix not found, running full setup instead"
        full_setup
        return 0
    fi

    wineboot -u

    print_info "Reinstalling Wine dependencies via winetricks (non-destructive)..."
    _install_winetricks_verbs

    print_info "Configuring Wine environment..."
    wine winecfg /v win10 >/dev/null 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v "VideoMemorySize" /t REG_SZ /d "8192" /f >/dev/null 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v "CSMT"           /t REG_SZ /d "enabled" /f >/dev/null 2>&1 || true

    print_info "Installing any missing launchers..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local succeeded=0 failed=0 skipped=0 failed_apps=""

    for app_key in "${!APP_REGISTRY[@]}"; do
        parse_app_config "$app_key" || continue
        if find_app_exe "$app_key" >/dev/null 2>&1; then
            print_info "$APP_NAME already installed, skipping..."
            ((skipped++))
            continue
        fi
        print_info "Installing: $app_key..."
        if _install_with_fallback "$app_key"; then
            ((succeeded++))
        else
            ((failed++))
            failed_apps="$failed_apps\n  - $app_key"
        fi
    done

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_info "Quick Setup Summary: Installed=$succeeded  Skipped=$skipped  Failed=$failed"
    [ "$failed" -gt 0 ] && echo -e "  Failed apps:$failed_apps"
    print_success "Quick setup complete"

    # Refresh wig aliases (also updates location if the folder was moved).
    if [ -n "${SETUP_SCRIPT_PATH:-}" ] && [ -f "${SETUP_SCRIPT_PATH:-}" ]; then
        echo ""
        install_aliases
    fi
}

# Move launcher AppData/ProgramData dirs outside the prefix so purge can wipe
# freely. Lives at $WINE_DIR/.launcher-stash (same FS as prefix → mv is instant).
_stash_launcher_data() {
    local _pc="$WINEPREFIX/pfx/drive_c"
    [ -d "$_pc" ] || return 1
    local _stash="$WINE_DIR/.launcher-stash"
    rm -rf "$_stash" && mkdir -p "$_stash"
    local -a _dirs=(
        "users/steamuser/AppData/Local/GOG.com"
        "users/steamuser/AppData/Roaming/GOG.com"
        "ProgramData/GOG.com"
        "users/steamuser/AppData/Local/EpicGamesLauncher"
        "ProgramData/Epic"
        "users/steamuser/AppData/Local/Electronic Arts"
        "users/steamuser/AppData/Roaming/Electronic Arts"
        "users/steamuser/AppData/Local/Ubisoft"
        "users/steamuser/AppData/Roaming/Ubisoft"
        "users/steamuser/AppData/Local/Amazon Games"
        "users/steamuser/AppData/Roaming/Amazon Games"
        "users/steamuser/AppData/Local/Programs/legacy-games-launcher"
        "users/steamuser/AppData/Roaming/Legacy Games Launcher"
    )
    local _count=0
    for _d in "${_dirs[@]}"; do
        [ -d "$_pc/$_d" ] || continue
        mkdir -p "$_stash/$(dirname "$_d")"
        mv "$_pc/$_d" "$_stash/$_d" && ((_count++))
    done
    if [ "$_count" -eq 0 ]; then rm -rf "$_stash"; return 1; fi
    print_info "Stashed $_count launcher data directories"
}

# Merge the stash back into a freshly-built prefix. Uses cp -rT for directory merge.
_unstash_launcher_data() {
    local _stash="$WINE_DIR/.launcher-stash"
    [ -d "$_stash" ] || return 0
    local _pc="$WINEPREFIX/pfx/drive_c"
    if [ ! -d "$_pc" ]; then
        print_warning "Prefix not ready — stash kept at $_stash"
        return 1
    fi
    cp -rT "$_stash" "$_pc" 2>/dev/null && rm -rf "$_stash" \
        && print_success "Launcher data restored from stash" \
        || print_warning "Stash restore had errors — data kept at $_stash"
}

# Remap Z: from / to an inert sandbox dir so launchers cannot see the host FS
# for disk-space checks or path traversal, while keeping Z: visible to Wine.
_sandbox_z_drive() {
    local _dd="$WINEPREFIX/pfx/dosdevices"
    [ -d "$_dd" ] || return 0
    mkdir -p "$WINEPREFIX/pfx/drive_c/z-sandbox"
    rm -f "$_dd/z:" "$_dd/z::" 2>/dev/null
    ln -sfn "../drive_c/z-sandbox" "$_dd/z:" 2>/dev/null || true
    # /dev/null device node: lets Wine query the volume without EACCES.
    ln -sfn "/dev/null" "$_dd/z::" 2>/dev/null || true
}

# Auto-detect mounted external volumes and map each to the next free drive letter
# (D: → Y:), preserving any already-assigned letters. Also reads WINE_EXTRA_DRIVES
# (colon-separated host paths). Games on NTFS/external drives must be reconfigured
# in their launcher settings to use the assigned letter instead of the Z: path.
_map_external_drives() {
    local _dd="$WINEPREFIX/pfx/dosdevices"
    [ -d "$_dd" ] || return 0

    local -A _mapped=()
    for _lnk in "$_dd"/[a-y]:; do
        [ -L "$_lnk" ] || continue
        local _t; _t=$(readlink -f "$_lnk" 2>/dev/null) && _mapped["$_t"]=1
    done

    local -a _candidates=()
    local _uid_media="/run/media/$(id -un)"
    [ -d "$_uid_media" ] && while IFS= read -r -d '' _d; do
        _candidates+=("$_d")
    done < <(find "$_uid_media" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null)
    while IFS= read -r -d '' _d; do
        local _fs; _fs=$(findmnt -n -o FSTYPE "$_d" 2>/dev/null)
        case "${_fs:-}" in tmpfs|sysfs|proc|devtmpfs|"") continue ;; esac
        _candidates+=("$_d")
    done < <(find /mnt -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null)
    if [ -n "${WINE_EXTRA_DRIVES:-}" ]; then
        local -a _xd; IFS=':' read -ra _xd <<< "$WINE_EXTRA_DRIVES"
        for _p in "${_xd[@]}"; do [ -d "$_p" ] && _candidates+=("$_p"); done
    fi

    for _mnt in "${_candidates[@]}"; do
        [ -d "$_mnt" ] || continue
        local _real; _real=$(readlink -f "$_mnt") || continue
        [[ -n "${_mapped[$_real]:-}" ]] && continue
        local _letter=""
        for _l in d e f g h i j k l m n o p q r s t u v w x y; do
            [ -L "$_dd/${_l}:" ] || { _letter="$_l"; break; }
        done
        [ -z "$_letter" ] && { print_warning "No free Wine drive letter for: $_real"; break; }
        ln -sfn "$_real" "$_dd/${_letter}:" 2>/dev/null \
            && _mapped["$_real"]=1 \
            && print_info "Drive ${_letter^^}: → $_real  (update game library path in launcher settings to use ${_letter^^}:)"
        # /dev/null lets Wine open the device node without root (prevents EACCES for all mapped drives).
        ln -sfn "/dev/null" "$_dd/${_letter}::" 2>/dev/null || true
    done
    # Z: always exists; give it a :: node too so installs suppress the EACCES probe.
    [ -L "$_dd/z:" ] && [ ! -L "$_dd/z::" ] && ln -sfn "/dev/null" "$_dd/z::" 2>/dev/null || true
}

# Configure Wine drive letter mappings.
# Usage: configure_wine_drives [drive_letter] [mount_path]
configure_wine_drives() {
    print_info "Configuring Wine drive mappings..."

    local dosdevices_dir="$WINEPREFIX/pfx/dosdevices"

    if [ ! -d "$dosdevices_dir" ]; then
        print_warning "Wine prefix not initialised yet, skipping drive configuration"
        return 1
    fi

    if [ -n "$1" ] && [ -n "$2" ]; then
        local drive_letter="${1:0:1}"
        local mount_path="$2"

        if [ ! -d "$mount_path" ]; then
            print_error "Mount path does not exist: $mount_path"
            return 1
        fi

        [ -L "$dosdevices_dir/${drive_letter}:" ] && rm "$dosdevices_dir/${drive_letter}:" \
            && print_info "Removed existing ${drive_letter}: symlink"

        ln -s "$mount_path" "$dosdevices_dir/${drive_letter}:"
        print_success "Created symlink: ${drive_letter}: -> $mount_path"
    fi

    print_info "Current Wine drive mappings:"
    ls -la "$dosdevices_dir" | grep -E "^l" | awk '{print "  " $NF " -> " $11}'

    if [ -L "$dosdevices_dir/z:" ]; then
        rm "$dosdevices_dir/z:"
        print_info "Removed Z: drive symlink (prevents /mnt auto-mounting)"
    fi

    print_info "Refreshing Wine configuration..."
    wineserver -k >/dev/null 2>&1
    WINEPREFIX="$WINEPREFIX/pfx" wineboot -r >/dev/null 2>&1 || true

    print_success "Drive configuration complete. Restart Wine apps to see changes."
}

# Permanently remove Z: drive from Wine dosdevices and registry.
fix_z_drive() {
    print_info "Removing Z: drive mount from Wine prefix..."

    [ -d "$WINEPREFIX" ] || { print_warning "Wine prefix not found at $WINEPREFIX"; return 1; }

    local dosdevices_dir="$WINEPREFIX/pfx/dosdevices"

    [ -L "$dosdevices_dir/z:" ] && rm "$dosdevices_dir/z:" \
        && print_success "Z: drive removed from dosdevices"

    wine reg delete \
        "HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2" \
        /v Z: /f 2>/dev/null || true

    print_success "Z: drive removed (Wine will use only configured drive letters)"
    return 0
}

# Temporarily hide Z: drive (stops apps seeing /mnt; use mount-z to restore).
unmount_z() {
    print_info "Unmounting Z: drive from Wine..."

    [ -d "$WINEPREFIX" ] || { print_warning "Wine prefix not found at $WINEPREFIX"; return 1; }

    local dosdevices_dir="$WINEPREFIX/pfx/dosdevices"

    if [ -L "$dosdevices_dir/z:" ]; then
        readlink "$dosdevices_dir/z:" > "$dosdevices_dir/.z_drive_backup"
        rm "$dosdevices_dir/z:"
        print_success "Z: drive unmounted"
    else
        print_warning "Z: drive not found (may already be unmounted)"
    fi

    wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\VxD\SMCFS" \
        /v "IgnoreSerialNumbers" /t REG_SZ /d "1" /f >/dev/null 2>&1 || true

    print_info "Wine no longer sees /mnt volumes (prevents disk space warnings)"
    return 0
}

# Restore Z: drive after unmount-z.
mount_z() {
    print_info "Mounting Z: drive in Wine..."

    [ -d "$WINEPREFIX" ] || { print_warning "Wine prefix not found at $WINEPREFIX"; return 1; }

    local dosdevices_dir="$WINEPREFIX/pfx/dosdevices"
    local backup_file="$dosdevices_dir/.z_drive_backup"

    if [ -f "$backup_file" ]; then
        ln -s "$(cat "$backup_file")" "$dosdevices_dir/z:"
        rm "$backup_file"
        print_success "Z: drive mounted"
    else
        ln -s "/" "$dosdevices_dir/z:"
        print_success "Z: drive mounted (default: /)"
    fi

    return 0
}

# Suppress Z: drive serial/label warnings in Wine registry and logs.
suppress_z_warnings() {
    print_info "Suppressing Wine Z: drive serial number warnings..."

    [ -d "$WINEPREFIX" ] || { print_warning "Wine prefix not found at $WINEPREFIX"; return 1; }

    wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\VxD\SMCFS" \
        /v "IgnoreSerialNumbers" /t REG_SZ /d "1" /f >/dev/null 2>&1
    wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\FileSystem" \
        /v "NtfsDisable8dot3NameCreation" /t REG_DWORD /d "1" /f >/dev/null 2>&1
    wine reg add "HKEY_CURRENT_USER\Software\Wine\Explorer" \
        /v "ShowHiddenFiles" /t REG_SZ /d "Y" /f >/dev/null 2>&1 || true

    print_success "Z: drive warnings suppressed in Wine registry"
    return 0
}

# Download and install Proton-GE.
install_proton() {
    print_info "Installing Proton-GE..."

    mkdir -p "$PROTON_DIR"
    cd /tmp

    local PROTON_VERSION="GE-Proton9-18"
    local archive="${PROTON_VERSION}.tar.gz"

    print_info "Downloading Proton-GE $PROTON_VERSION..."

    if ! wget -q --show-progress \
        "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${PROTON_VERSION}/${archive}"; then
        print_error "Failed to download Proton-GE"
        return 1
    fi

    print_info "Extracting Proton-GE..."
    run_without_oas tar -xf "$archive" -C "$PROTON_DIR" --strip-components=1
    rm -f "$archive"

    print_success "Proton-GE installed to $PROTON_DIR"
}
