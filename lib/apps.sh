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

    local install_log="$WINE_DIR/${app_key}-install.log"

    export STEAM_COMPAT_DATA_PATH="$WINEPREFIX"
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$WINE_DIR/steam-root"
    # PROTON_LOG=1 routes Wine subprocess stderr to a file (not a pipe), preventing
    # installers that check GetFileType(STD_ERROR_HANDLE) from aborting on pipe detection.
    export PROTON_LOG=1
    export PROTON_LOG_DIR="$WINE_DIR"
    mkdir -p "$WINE_DIR/steam-root"
    mkdir -p "$WINEPREFIX"
    _map_external_drives

    if [ ! -d "$WINEPREFIX/pfx" ]; then
        print_warning "First run: building the Wine prefix — this takes a minute or two with no output."
    fi
    print_info "An installer window may open — complete it there; this step waits until it closes."

    local -a run_cmd
    local -a _extra; read -ra _extra <<< "${APP_INSTALL_ARGS[$app_key]:-}"
    case "${installer_path,,}" in
        *.msi)
            # /passive = unattended (progress bar, no clicks); /qn breaks some MSI custom actions.
            # /log writes a verbose MSI transcript to the Windows temp dir for failure analysis.
            run_cmd=(msiexec /i "$installer_path" /passive REBOOT=ReallySuppress \
                /log "C:\\windows\\temp\\${app_key}-msi.log" "${_extra[@]}")
            ;;
        *)
            run_cmd=("$installer_path" "${_extra[@]}")
            ;;
    esac

    "$PROTON_DIR/proton" run "${run_cmd[@]}" 2>&1 | tee "$install_log" || true

    if find_app_exe "$app_key" >/dev/null 2>&1; then
        print_success "$APP_NAME installed successfully"
        create_shortcut "$app_key" && print_success "Desktop shortcut created" || true
        return 0
    else
        print_error "$APP_NAME did not install ($APP_EXE not found)"
        # Show the most recent Wine log; then point at all log files for deeper investigation.
        local _wlog; _wlog=$(ls -1t "$WINE_DIR"/steam-*.log 2>/dev/null | head -1)
        if [ -n "$_wlog" ] && [ -f "$_wlog" ]; then
            print_info "Last 25 lines from $(basename "$_wlog"):"
            tail -25 "$_wlog"
        fi
        print_info "Proton wrapper log : $install_log"
        [ -n "$_wlog" ] && print_info "Wine subprocess log: $_wlog"
        local _msi_log="$WINEPREFIX/pfx/drive_c/windows/temp/${app_key}-msi.log"
        [ -f "$_msi_log" ] && print_info "MSI install log    : $_msi_log"
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
