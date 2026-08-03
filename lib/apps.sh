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
        mkdir -p \
            "$_pfx_c/ProgramData/Microsoft/Windows/Start Menu/Programs/EA" \
            2>/dev/null || true
        # Disable MSI rollback so a partially-successful MSI install leaves files on disk.
        # EA App's MSI fails when registering its background service under Wine, triggering
        # a full rollback that removes the already-installed EA Desktop.exe.
        PROTON_LOG=0 "$PROTON_DIR/proton" run reg.exe add \
            "HKLM\\Software\\Policies\\Microsoft\\Windows\\Installer" \
            /v DisableRollback /t REG_DWORD /d 1 /f \
            >/dev/null 2>&1 || true
        PROTON_LOG=0 "$PROTON_DIR/proton" run cmd.exe /c \
            "md \"%ProgramData%\\Microsoft\\Windows\\Start Menu\\Programs\\EA\" 2>nul" \
            >/dev/null 2>&1 || true
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
    # ea-desktop: /a (admin install) extracts files without running the service-registration
    # custom action that causes ERROR_FUNCTION_FAILED (0x8007065b) under Wine.
    local -a run_cmd
    case "${installer_path,,}" in
        *.msi)
            if [ "$app_key" = "ea-desktop" ]; then
                run_cmd=(msiexec /a "$installer_path" TARGETDIR="C:\\Program Files")
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
