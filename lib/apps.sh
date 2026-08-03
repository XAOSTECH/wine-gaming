#!/bin/bash
# lib/apps.sh — App install, uninstall, and batch operations
# Sourced by setup; do not execute directly.
# Depends on: lib/config.sh, lib/utils.sh, lib/registry.sh, lib/installer.sh, lib/shortcuts.sh

# Install a registered launcher via Proton.
# Usage: install_app "app-key" [custom_installer_path]
install_app() {
    local app_key="$1"
    local custom_installer="$2"

    parse_app_config "$app_key" || return 1
    check_proton || return 1

    local installer_path
    if [ -n "$custom_installer" ] && [ -f "$custom_installer" ]; then
        installer_path="$custom_installer"
        print_info "Using custom installer: $installer_path"
    else
        installer_path=$(download_installer "$app_key") || return 1
    fi

    print_info "Installing $APP_NAME via Proton..."

    export STEAM_COMPAT_DATA_PATH="$WINEPREFIX"
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$WINE_DIR/steam-root"
    # Prevent Wine from processing shortcuts/file associations; we handle shortcuts ourselves.
    export WINEDLLOVERRIDES="winemenubuilder.exe=d"
    # PROTON_LOG=1 routes wine subprocess stderr to a log file (not a pipe), which prevents
    # installers that call GetFileType(GetStdHandle(STD_ERROR_HANDLE)) from detecting a pipe and aborting.
    export PROTON_LOG=1
    export PROTON_LOG_DIR="$WINE_DIR"
    local install_log="$WINE_DIR/${app_key}-install.log"
    mkdir -p "$WINE_DIR/steam-root"
    # Proton locks $STEAM_COMPAT_DATA_PATH/pfx.lock; the dir must exist first.
    mkdir -p "$WINEPREFIX"

    # Create Windows special directories via Proton's bundled wine64 so Wine VFS junctions are
    # respected. Shell mkdir creates directories outside the junction and Wine ignores them.
    local _dosdevices="$WINEPREFIX/pfx/dosdevices"
    if [ -d "$WINEPREFIX/pfx" ]; then
        local _pfx_c="$WINEPREFIX/pfx/drive_c"
        # Pre-create All-Users Start Menu dirs; some installers use DirectoryInfo.Create()
        # which throws DirectoryNotFoundException if the parent doesn't exist.
        mkdir -p \
            "$_pfx_c/ProgramData/Microsoft/Windows/Start Menu/Programs/EA" \
            "$_pfx_c/ProgramData/Microsoft/Windows/Start Menu/Programs/Epic Games" \
            2>/dev/null || true
        rm -f "$_dosdevices/z:" "$_dosdevices/z::" 2>/dev/null || true
    fi

    # First run builds the prefix (copies thousands of DLLs) before the installer
    # window appears, during which Proton is silent — warn so it isn't mistaken for a hang.
    if [ ! -d "$WINEPREFIX/pfx" ]; then
        print_warning "First run: building the Wine prefix — this takes a minute or two with no output."
    fi
    print_info "An installer window may open — complete it there; this step waits until it closes."
    print_info "Install log: $install_log  |  Wine log: $WINE_DIR/steam-*.log"

    # MSI packages must be driven through msiexec; handing the .msi straight to
    # Proton only opens it and exits, so nothing installs (e.g. Epic, Ubisoft).
    # ea-desktop: EA App MSI has a WiX Burn LaunchCondition that exits immediately when
    # called standalone — use msiextract to pull files out without running any conditions.
    local -a run_cmd
    case "${installer_path,,}" in
        *.msi)
            if [ "$app_key" = "ea-desktop" ] && command -v msiextract &>/dev/null; then
                print_info "Extracting EA App MSI via msiextract (bypasses WiX Burn LaunchCondition)..."
                local _ea_tmp _pfx_c
                _ea_tmp=$(mktemp -d /tmp/ea_msi.XXXXXX)
                _pfx_c="$WINEPREFIX/pfx/drive_c"
                if msiextract "$installer_path" -C "$_ea_tmp" 2>/dev/null; then
                    # EA App installs to 64-bit Program Files; copy into Wine prefix.
                    # msiextract may root at $tmp or at $tmp/Program Files depending on MSI Directory table.
                    local _src
                    for _src in "$_ea_tmp/Program Files" "$_ea_tmp/Program Files (x86)" "$_ea_tmp"; do
                        if [ -d "$_src/Electronic Arts" ]; then
                            cp -rn "$_src/Electronic Arts" "$_pfx_c/Program Files/" 2>/dev/null || true
                            break
                        fi
                    done
                fi
                rm -rf "$_ea_tmp"
                # Skip the Proton installer run entirely
                if find_app_exe "$app_key" >/dev/null 2>&1; then
                    print_success "$APP_NAME installed via MSI extraction"
                    create_shortcut "$app_key" && print_success "Desktop shortcut created" || true
                    return 0
                fi
                print_warning "msiextract didn't place exe at expected path — falling back to msiexec"
            fi
            local _msi_name _msi_wtemp
            _msi_name=$(basename "$installer_path")
            _msi_wtemp="$WINEPREFIX/pfx/drive_c/windows/temp"
            mkdir -p "$_msi_wtemp" 2>/dev/null || true
            cp -f "$installer_path" "$_msi_wtemp/$_msi_name" 2>/dev/null || true
            if [ "$app_key" = "ea-desktop" ]; then
                run_cmd=(msiexec /i "C:\\windows\\temp\\$_msi_name" MSIFASTINSTALL=3 EAX_LAUNCH_CLIENT=0)
            else
                run_cmd=(msiexec /i "$installer_path")
            fi
            ;;
        *) run_cmd=("$installer_path") ;;
    esac

    # With PROTON_LOG=1, wine subprocess output goes to steam-*.log (not through this pipe).
    # Tee captures only Proton's own wrapper output (Proton:/fsync: lines) to install_log.
    "$PROTON_DIR/proton" run "${run_cmd[@]}" 2>&1 | tee "$install_log" || true

    # Keep Z: drive removed so subsequent installs don't hit access-denied errors.
    rm -f "$_dosdevices/z:" "$_dosdevices/z::" 2>/dev/null || true

    # Proton's exit status reflects the wrapper, not whether the app landed, so
    # verify the real executable exists before claiming success.
    if find_app_exe "$app_key" >/dev/null 2>&1; then
        print_success "$APP_NAME installed successfully"
        # Use regedit /s (truly silent, no window) to disable background services that
        # restart-loop under Wine when they can't initialize OpenVR or missing dependencies.
        local _svc_reg="$WINEPREFIX/pfx/drive_c/windows/temp/disable-bg-svc.reg"
        case "$app_key" in
            epic-games)
                # DEMAND_START (3): launcher can start the service; FailureActions=0 prevents restart loops.
                printf 'Windows Registry Editor Version 5.00\n\n'\
'[HKEY_LOCAL_MACHINE\\SYSTEM\\ControlSet001\\Services\\EpicGamesUpdater]\n'\
'"Start"=dword:00000003\n'\
'"FailureActions"=hex:00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00\n' \
                    > "$_svc_reg"
                "$PROTON_DIR/proton" run regedit /s \
                    "C:\\windows\\temp\\disable-bg-svc.reg" >/dev/null 2>&1 || true
                ;;
            ea-desktop)
                # DEMAND_START + no restart; also create install registry key that EADesktop.exe
                # checks on startup — if absent it falls back to bootstrapper/repair mode.
                # Register EABackgroundService so StartService() succeeds — msiextract skips this CA.
                local _ea_ver
                _ea_ver=$(basename "${installer_path:-}" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
                _ea_ver="${_ea_ver:-13.759.0.0}"
                printf 'Windows Registry Editor Version 5.00\n\n'\
'[HKEY_LOCAL_MACHINE\\SOFTWARE\\Electronic Arts\\EA Desktop]\n'\
'"InstallDir"="C:\\\\Program Files\\\\Electronic Arts\\\\EA Desktop\\\\EA Desktop\\\\"\n'\
'"Version"="'"$_ea_ver"'"\n\n'\
'[HKEY_LOCAL_MACHINE\\SOFTWARE\\Electronic Arts\\EA Desktop\\Install]\n'\
'"InstallDir"="C:\\\\Program Files\\\\Electronic Arts\\\\EA Desktop\\\\EA Desktop\\\\"\n\n'\
'[HKEY_LOCAL_MACHINE\\SYSTEM\\ControlSet001\\Services\\EABackgroundService]\n'\
'"Type"=dword:00000010\n'\
'"Start"=dword:00000003\n'\
'"ErrorControl"=dword:00000001\n'\
'"ImagePath"="\\"C:\\\\Program Files\\\\Electronic Arts\\\\EA Desktop\\\\EA Desktop\\\\EABackgroundService.exe\\" -start"\n'\
'"DisplayName"="EABackgroundService"\n'\
'"ObjectName"="LocalSystem"\n'\
'"FailureActions"=hex:00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00\n' \
                    > "$_svc_reg"
                "$PROTON_DIR/proton" run regedit /s \
                    "C:\\windows\\temp\\disable-bg-svc.reg" >/dev/null 2>&1 || true
                ;;
        esac
        create_shortcut "$app_key" && print_success "Desktop shortcut created" || true
        return 0
    else
        print_error "$APP_NAME did not install ($APP_EXE not found) — see $install_log"
        return 1
    fi
}

# Remove a launcher from the Wine prefix.
# Usage: uninstall_app "app-key"
uninstall_app() {
    local app_key="$1"

    parse_app_config "$app_key" || return 1

    print_info "Uninstalling $APP_NAME..."

    local pfx_dir="$WINEPREFIX/pfx"
    local removed_count=0

    IFS='|' read -r -a paths <<< "${APP_REGISTRY[$app_key]}"

    # Fields 0-2 are name|exe|url — uninstall paths start at index 3
    for ((i=3; i<${#paths[@]}; i++)); do
        local uninstall_path="${paths[$i]}"
        local full_path="$pfx_dir/drive_c/$uninstall_path"

        if [ -e "$full_path" ]; then
            print_info "Removing: $uninstall_path"
            rm -rf "$full_path"
            ((removed_count++))
        fi
    done

    if [ "$removed_count" -gt 0 ]; then
        print_success "$APP_NAME uninstalled ($removed_count paths removed)"
        remove_shortcut "$app_key" || true
    else
        print_warning "$APP_NAME not found in prefix (already uninstalled?)"
    fi

    return 0
}

# Install every launcher registered in APP_REGISTRY.
install_all_launchers() {
    print_info "Installing all registered launchers..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    check_proton || return 1

    local succeeded=0 failed=0 failed_apps=""

    for app_key in "${!APP_REGISTRY[@]}"; do
        print_info "Installing $app_key..."
        if install_app "$app_key"; then
            ((succeeded++))
        else
            ((failed++))
            failed_apps="$failed_apps\n  - $app_key"
        fi
    done

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_info "Installation Summary:"
    echo "  Successful: $succeeded"
    echo "  Failed:     $failed"
    [ "$failed" -gt 0 ] && echo -e "  Failed apps:$failed_apps"
}
