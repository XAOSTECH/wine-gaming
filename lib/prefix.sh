#!/bin/bash
# lib/prefix.sh — Wine prefix lifecycle and Proton management
# Sourced by setup; do not execute directly.
# Depends on: lib/config.sh, lib/utils.sh, lib/registry.sh, lib/installer.sh, lib/apps.sh

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
init() {
    print_info "Initializing Wine prefix..."

    # Install system-level apt packages required by wine-gaming tooling.
    # icoutils: wrestool + icotool — extract and convert .exe icons for desktop shortcuts.
    print_info "Installing system dependencies (apt)..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get install -y icoutils 2>&1 \
            | grep -v "^Reading\|^Building\|^(Reading\|^Selecting\|^Setting\|^Preparing" || true
    else
        print_warning "apt-get not available — skipping icoutils install (icon extraction will be skipped)"
    fi

    mkdir -p "${HOME}/.config/winetricks"
    touch "${HOME}/.config/winetricks/enable-latest-version-check"

    wineboot -u

    print_info "Installing Wine dependencies via winetricks..."
    # vcrun*: Visual C++ runtimes | d3dcompiler/d3dx: DirectX | dxvk/vkd3d/d9vk: GPU layers
    # dotnet/corefonts/gdiplus: .NET + UI | directmusic/faudio/xact: audio
    # directplay/directshow/physx/msctf: legacy subsystems + physics + text services
    WINETRICKS_LATEST_VERSION_CHECK=disabled winetricks -q \
        vcrun2019 vcrun2015 vcrun2012 \
        d3dcompiler_47 d3dcompiler_43 d3dx9 d3dx10_43 d3dx11_43 \
        dxvk vkd3d d9vk \
        corefonts dotnet48 dotnet472 gdiplus \
        directmusic faudio xact directplay directshow \
        physx msctf \
        2>&1 | grep -v "warning: You are using a 64-bit WINEPREFIX" \
              | grep -v "Note that many verbs only install 32-bit" || true

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
    purge
    init
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
    print_info "Running quick setup..."

    if [ ! -d "$WINEPREFIX" ]; then
        print_warning "Wine prefix not found, running full setup instead"
        full_setup
        return 0
    fi

    wineboot -u

    print_info "Reinstalling Wine dependencies via winetricks (non-destructive)..."
    WINETRICKS_LATEST_VERSION_CHECK=disabled winetricks -q \
        vcrun2019 vcrun2015 vcrun2012 \
        d3dcompiler_47 d3dcompiler_43 d3dx9 d3dx10_43 d3dx11_43 \
        dxvk vkd3d d9vk \
        corefonts dotnet48 dotnet472 gdiplus \
        directmusic faudio xact directplay directshow \
        physx msctf \
        2>&1 | grep -v "warning: You are using a 64-bit WINEPREFIX" \
              | grep -v "Note that many verbs only install 32-bit" || true

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
    tar -xf "$archive" -C "$PROTON_DIR" --strip-components=1
    rm -f "$archive"

    print_success "Proton-GE installed to $PROTON_DIR"
}
