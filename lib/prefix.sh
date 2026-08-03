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
        dxvk vkd3d
        corefonts gdiplus
        directmusic faudio xact directplay directshow
        msctf
        gamemode
    )
    local heavy_verbs=( dotnet48 dotnet472 physx )

    # Winetricks must target Proton's pfx/ prefix, not the bare STEAM_COMPAT_DATA_PATH.
    # pfx/ is created by Proton on the first installer run — run `wig install <app>` first.
    local _wt_prefix="$WINEPREFIX/pfx"
    if [ ! -d "$_wt_prefix/drive_c/windows/system32" ]; then
        print_warning "Skipping winetricks: Proton prefix not yet initialised."
        print_info "Run \`wig install <app>\` first (builds the prefix), then \`wig init\` for verbs."
        print_info "Proton-GE provides dxvk/vkd3d/vcrun natively; most verbs are optional."
        return 0
    fi

    # Prefer Proton's bundled wine binary; system wine may not function on this host.
    local _wine_bin="wine"
    local _candidate
    for _candidate in "$PROTON_DIR/files/bin/wine64" "$PROTON_DIR/files/bin/wine"; do
        [ -x "$_candidate" ] && { _wine_bin="$_candidate"; break; }
    done

    # Subshell isolates wine env overrides from the rest of the script.
    (
        export WINE="$_wine_bin"
        export WINESERVER="$(dirname "$_wine_bin")/wineserver"
        export WINEPREFIX="$_wt_prefix"
        if [ -d "$PROTON_DIR/files/lib64" ]; then
            export LD_LIBRARY_PATH="$PROTON_DIR/files/lib:$PROTON_DIR/files/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        fi

        print_info "Installing fast winetricks verbs (${#fast_verbs[@]} packages)..."
        local v
        for v in "${fast_verbs[@]}"; do
            printf "  → %s ... " "$v"
            if WINETRICKS_LATEST_VERSION_CHECK=enabled \
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
            WINETRICKS_LATEST_VERSION_CHECK=enabled \
                winetricks -q --force "$v" 2>&1 \
                | grep -Ev "^warning:|winetricks latest version check|^Executing cd|^-{10,}$|^WINEPREFIX INFO:|Drive C: total|^[dl-][-rwx]{9} |^Registry info:|/#arch=|^$" \
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

# Initialise a fresh Wine prefix with all required dependencies.
# --reinstall  Force apt-get --reinstall on wine packages (fixes broken wine installation).
init() {
    local _reinstall=0
    [[ "${1:-}" == "--reinstall" ]] && _reinstall=1

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
    # winetricks:  helper to install Windows DLL/runtime packages into a Wine prefix.
    # wine/wine64: Wine itself — wineserver must be present for winetricks to work.
    # wine32:i386: 32-bit Wine runtime — required by many 32-bit Windows binaries.
    print_info "Installing system dependencies (apt)..."
    if command -v apt-get &>/dev/null; then
        # Enable i386 arch for wine32; dpkg --add-architecture is idempotent.
        if ! dpkg --print-foreign-architectures 2>/dev/null | grep -q i386; then
            sudo dpkg --add-architecture i386
            sudo apt-get update -qq 2>&1 | tail -1 || true
        fi
        local _apt_args=( install -y )
        [ "$_reinstall" -eq 1 ] && { _apt_args=( install --reinstall -y ); print_info "Forcing package reinstall (--reinstall)..."; }
        sudo apt-get "${_apt_args[@]}" icoutils gamemode mangohud winetricks \
            wine wine64 wine32:i386 msitools 2>&1 \
            | grep -v "^Reading\|^Building\|^(Reading\|^Selecting\|^Setting\|^Preparing" || true
    else
        print_warning "apt-get not available — skipping system package install"
    fi

    # Download winetricks directly if apt didn't install it (e.g. no sudo or apt failure).
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
    export WINETRICKS_LATEST_VERSION_CHECK=enabled

    _install_winetricks_verbs

    # Create DXVK config once; upstream DXVK has no OpenVR option — warnings are benign.
    if [ ! -f "$WINE_DIR/dxvk.conf" ]; then
        cat > "$WINE_DIR/dxvk.conf" << 'EOF'
# wine-gaming DXVK configuration
# See https://github.com/doitsujin/dxvk/blob/master/dxvk.conf for all options.
# OpenVR/OpenXR warnings are informational only; DXVK has no config option to suppress them.
EOF
    fi

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
    local _reinstall_flag=""
    [[ "${1:-}" == "--reinstall" ]] && _reinstall_flag="--reinstall"

    print_info "Running full setup..."
    purge
    init ${_reinstall_flag:+"$_reinstall_flag"}
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
    print_success "Full setup complete"
}

# Quick setup: re-run dependencies non-destructively, install any missing launchers.
quick_setup() {
    local _reinstall_flag=""
    [[ "${1:-}" == "--reinstall" ]] && _reinstall_flag="--reinstall"

    if [ ! -d "$WINEPREFIX" ]; then
        print_warning "Wine prefix not found, running full setup instead"
        full_setup ${_reinstall_flag:+"$_reinstall_flag"}
        return 0
    fi

    print_info "Running quick setup..."

    if [ -n "$_reinstall_flag" ]; then
        # --reinstall: force-reinstall wine packages + wineboot + winetricks via init
        init --reinstall
    else
        print_info "Reinstalling Wine dependencies via winetricks (non-destructive)..."
        _install_winetricks_verbs
    fi

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
