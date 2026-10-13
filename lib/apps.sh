#!/bin/bash
# lib/apps.sh — App install, uninstall, and batch operations
# Sourced by setup; do not execute directly.
# Depends on: lib/config.sh, lib/utils.sh, lib/registry.sh, lib/installer.sh, lib/shortcuts.sh

# Build a Wine compatibility layer for EOS: a stub EOSSDK-Win64-Shipping.dll that
# returns EOS_Success for all lifecycle calls + a stub EOSBootstrapperApp.exe that
# exits 0. Wine's DllOverrides then loads the stub instead of any bundled copy,
# preventing Epic Games Launcher from showing the "Install Epic Online Services" dialog.
_build_eos_compat_layer() {
    local _eos_dir="$WINEPREFIX/pfx/drive_c/Program Files (x86)/Epic Games/Epic Online Services"
    local _sys32="$WINEPREFIX/pfx/drive_c/windows/system32"
    local _portal_eos="$WINEPREFIX/pfx/drive_c/Program Files/Epic Games/Launcher/Portal/Extras/EOS"
    local _mgw="x86_64-w64-mingw32-gcc"

    command -v "$_mgw" &>/dev/null || {
        print_info "Installing MinGW cross-compiler for EOS stub..."
        sudo apt-get install -y gcc-mingw-w64 >/dev/null 2>&1 || {
            print_warning "gcc-mingw-w64 unavailable — EOS stub build skipped"
            return 1
        }
    }

    local _bld; _bld=$(mktemp -d)

    # Stub DLL: EOS_Platform_Create returns a non-NULL handle; all lifecycle
    # and logging functions return EOS_Success (0).
    cat > "$_bld/eos_stub.c" << 'STUBEOF'
#include <windows.h>
#include <stdint.h>
#define EOS_Success 0
static int _h[4];
#define FAKE ((void*)_h)
BOOL WINAPI DllMain(HINSTANCE h,DWORD r,LPVOID p){(void)h;(void)r;(void)p;return TRUE;}
__declspec(dllexport) int         EOS_Initialize(const void*o)                      {return EOS_Success;}
__declspec(dllexport) int         EOS_Shutdown(void)                                {return EOS_Success;}
__declspec(dllexport) void*       EOS_Platform_Create(const void*o)                 {return FAKE;}
__declspec(dllexport) void        EOS_Platform_Release(void*h)                      {}
__declspec(dllexport) void        EOS_Platform_Tick(void*h)                         {}
__declspec(dllexport) const char* EOS_GetVersion(void)                              {return "1.19.1";}
/* bootstrapper/crossplay checks — Success prevents the install dialog */
__declspec(dllexport) int         EOS_Platform_CheckForLauncherAndRestart(void*h)   {return EOS_Success;}
__declspec(dllexport) int         EOS_Platform_GetDesktopCrossplayStatus(void*h,void*o){return EOS_Success;}
__declspec(dllexport) int         EOS_Logging_SetCallback(void*cb)                  {return EOS_Success;}
__declspec(dllexport) int         EOS_Logging_SetLogLevel(int c,int l)              {return EOS_Success;}
/* all interface getters return the same stable non-NULL handle */
#define G(n) __declspec(dllexport) void* n(void*h){return FAKE;}
G(EOS_Platform_GetConnectInterface)         G(EOS_Platform_GetAuthInterface)
G(EOS_Platform_GetFriendsInterface)         G(EOS_Platform_GetPresenceInterface)
G(EOS_Platform_GetUserInfoInterface)        G(EOS_Platform_GetEcomInterface)
G(EOS_Platform_GetTitleStorageInterface)    G(EOS_Platform_GetPlayerDataStorageInterface)
G(EOS_Platform_GetAchievementsInterface)    G(EOS_Platform_GetStatsInterface)
G(EOS_Platform_GetLeaderboardsInterface)    G(EOS_Platform_GetAntiCheatServerInterface)
G(EOS_Platform_GetAntiCheatClientInterface) G(EOS_Platform_GetLobbyInterface)
G(EOS_Platform_GetSessionsInterface)        G(EOS_Platform_GetMetricsInterface)
G(EOS_Platform_GetP2PInterface)             G(EOS_Platform_GetUIInterface)
G(EOS_Platform_GetModsInterface)            G(EOS_Platform_GetReportsInterface)
G(EOS_Platform_GetSanctionsInterface)       G(EOS_Platform_GetCustomInvitesInterface)
G(EOS_Platform_GetProgressionSnapshotInterface) G(EOS_Platform_GetKWSInterface)
G(EOS_Platform_GetRTCInterface)             G(EOS_Platform_GetRTCAdminInterface)
G(EOS_Platform_GetVoiceInterface)
STUBEOF

    # Stub bootstrapper: exits 0 — Epic EGL interprets this as "EOS installed and current"
    cat > "$_bld/eos_boot.c" << 'BSEOF'
int main(void){return 0;}
BSEOF

    "$_mgw" -shared -Os -o "$_bld/EOSSDK-Win64-Shipping.dll" \
        "$_bld/eos_stub.c" -Wl,--kill-at 2>/dev/null || {
        rm -rf "$_bld"; print_warning "EOS stub DLL compilation failed"; return 1
    }
    "$_mgw" -Os -o "$_bld/EOSBootstrapperApp.exe" "$_bld/eos_boot.c" 2>/dev/null || {
        rm -rf "$_bld"; print_warning "EOS stub bootstrapper compilation failed"; return 1
    }

    # Stub DLL in system32 AND in Epic's Binaries/Win64/ — app-dir load beats system32 even with
    # DllOverrides=native, so we replace it at both locations to guarantee our stub is used.
    local _launcher_bin="$WINEPREFIX/pfx/drive_c/Program Files/Epic Games/Launcher/Portal/Binaries/Win64"
    mkdir -p "$_sys32" "$_eos_dir" "$_portal_eos" "$_launcher_bin"
    cp "$_bld/EOSSDK-Win64-Shipping.dll" "$_sys32/EOSSDK-Win64-Shipping.dll"
    cp "$_bld/EOSSDK-Win64-Shipping.dll" "$_launcher_bin/EOSSDK-Win64-Shipping.dll"
    # Both bootstrapper names — SDK gives EOSBootstrapper.exe but EGL may call EOSBootstrapperApp.exe
    cp "$_bld/EOSBootstrapperApp.exe" "$_eos_dir/EOSBootstrapperApp.exe"
    cp "$_bld/EOSBootstrapperApp.exe" "$_eos_dir/EOSBootstrapper.exe"
    cp "$_bld/EOSBootstrapperApp.exe" "$_portal_eos/EOSBootstrapperApp.exe"
    cp "$_bld/EOSBootstrapperApp.exe" "$_portal_eos/EOSBootstrapper.exe"

    rm -rf "$_bld"

    # Set Wine DllOverride: "native" makes Wine use the stub in system32 over any bundled copy
    local _or="$WINEPREFIX/pfx/drive_c/windows/temp/wg-eos-compat.reg"
    printf 'Windows Registry Editor Version 5.00\n\n'\
'[HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides]\n'\
'"EOSSDK-Win64-Shipping"="native"\n' > "$_or"
    STEAM_COMPAT_DATA_PATH="$WINEPREFIX" \
    STEAM_COMPAT_CLIENT_INSTALL_PATH="$WINE_DIR/steam-root" \
        "$PROTON_DIR/proton" run regedit /s "C:\\windows\\temp\\wg-eos-compat.reg" >/dev/null 2>&1 || true

    print_success "EOS compat layer installed (stub DLL + stub EOSBootstrapperApp.exe)"
}

# Reusable helper: write EOS version registry keys so Epic's 32-bit and 64-bit checks both pass.
_set_eos_registry() {
    local _ver="1.19.1.2"
    local _eos_reg="$WINEPREFIX/pfx/drive_c/windows/temp/wg-eos-install.reg"
    mkdir -p "$(dirname "$_eos_reg")"
    printf 'Windows Registry Editor Version 5.00\n\n'\
'[HKEY_LOCAL_MACHINE\\SOFTWARE\\Epic Games\\EpicOnlineServices]\n'\
'"ModSdkMetadataDir"="C:\\\\Program Files (x86)\\\\Epic Games\\\\Epic Online Services"\n'\
'"Version"="'"$_ver"'"\n\n'\
'[HKEY_LOCAL_MACHINE\\SOFTWARE\\WOW6432Node\\Epic Games\\EpicOnlineServices]\n'\
'"ModSdkMetadataDir"="C:\\\\Program Files (x86)\\\\Epic Games\\\\Epic Online Services"\n'\
'"Version"="'"$_ver"'"\n\n'\
'[HKEY_LOCAL_MACHINE\\SYSTEM\\ControlSet001\\Services\\EpicOnlineServices]\n'\
'"Type"=dword:00000010\n'\
'"Start"=dword:00000003\n'\
'"ErrorControl"=dword:00000001\n'\
'"DisplayName"="Epic Online Services"\n'\
'"ImagePath"="C:\\\\Program Files (x86)\\\\Epic Games\\\\Epic Online Services\\\\EOSBootstrapperApp.exe"\n' > "$_eos_reg"
    STEAM_COMPAT_DATA_PATH="$WINEPREFIX" \
    STEAM_COMPAT_CLIENT_INSTALL_PATH="$WINE_DIR/steam-root" \
        "$PROTON_DIR/proton" run regedit /s "C:\\windows\\temp\\wg-eos-install.reg" >/dev/null 2>&1 || true
}

# Install EOS runtime into the Wine prefix.
# Order: (1) run EpicOnlineServicesInstaller.exe if present, (2) DLL-only registry update if DLL present,
# (3) download SDK and extract. A stamp file prevents repeated runs; --force bypasses it.
install_eos_runtime() {
    local _force="${1:-}"
    local _stamp="$WINEPREFIX/pfx/.wg-eos-installed"
    local _eos_dir="$WINEPREFIX/pfx/drive_c/Program Files (x86)/Epic Games/Epic Online Services"
    local _eos_installer="$_eos_dir/EpicOnlineServicesInstaller.exe"
    local _eos_dll="$_eos_dir/EOSSDK-Win64-Shipping.dll"

    if [ "$_force" != "--force" ] && [ -f "$_stamp" ]; then
        print_info "EOS runtime already installed (use --force to reinstall)."
        # Still rebuild the compat layer in case it was deleted or prefix was recreated
        _build_eos_compat_layer || true
        return 0
    fi

    check_proton || return 1

    # The full EOS installer is the authoritative installation path — prefer it over the SDK extraction.
    if [ -f "$_eos_installer" ]; then
        print_info "Installing EOS runtime via EpicOnlineServicesInstaller.exe (~304 MB, takes up to 5 min)..."
        timeout 300 \
        STEAM_COMPAT_DATA_PATH="$WINEPREFIX" \
        STEAM_COMPAT_CLIENT_INSTALL_PATH="$WINE_DIR/steam-root" \
        PROTON_LOG=0 \
            "$PROTON_DIR/proton" run \
            "C:\\Program Files (x86)\\Epic Games\\Epic Online Services\\EpicOnlineServicesInstaller.exe" \
            /install /silent >/dev/null 2>&1 || true
        _set_eos_registry
        _build_eos_compat_layer || true
        touch "$_stamp"
        print_success "EOS runtime installed"
        return 0
    fi

    # DLL present but no installer — registry update is enough to satisfy the version check.
    if [ "$_force" != "--force" ] && [ -f "$_eos_dll" ]; then
        print_info "EOS DLL present; updating registry version keys."
        _set_eos_registry
        _build_eos_compat_layer || true
        touch "$_stamp"
        return 0
    fi

    # Nothing present — download the SDK to get both DLLs and the bootstrapper tools.
    command -v unzip &>/dev/null || {
        print_warning "unzip not found — run: sudo apt-get install unzip"
        return 1
    }
    local _eos_url="https://onlineservices.epicgames.com/api/cosmos/sdk/download?archive_id=870&archive_type=sdk"
    local _eos_cache="$CACHE_DIR/eos-sdk-870.zip"
    if [ ! -f "$_eos_cache" ]; then
        print_info "Downloading EOS SDK (~560 MB, cached after first run)..."
        if ! wget -q --show-progress -L -O "$_eos_cache.part" "$_eos_url" 2>&1; then
            rm -f "$_eos_cache.part"
            print_warning "EOS SDK download failed"
            return 1
        fi
        mv "$_eos_cache.part" "$_eos_cache"
    else
        print_info "Using cached EOS SDK: $(basename "$_eos_cache")"
    fi

    print_info "Extracting EOS runtime files..."
    mkdir -p "$_eos_dir" "$_eos_dir/x86"
    unzip -j -o "$_eos_cache" "*/Bin/EOSSDK-Win64-Shipping.dll"     -d "$_eos_dir"     >/dev/null 2>&1 || true
    unzip -j -o "$_eos_cache" "*/Bin/EOSSDK-Win32-Shipping.dll"     -d "$_eos_dir"     >/dev/null 2>&1 || true
    unzip -j -o "$_eos_cache" "*/Bin/x86/EOSSDK-Win32-Shipping.dll" -d "$_eos_dir/x86" >/dev/null 2>&1 || true
    unzip -j -o "$_eos_cache" "*/Tools/*.exe"                        -d "$_eos_dir"     >/dev/null 2>&1 || true

    [ -f "$_eos_dll" ] || { print_warning "EOSSDK-Win64-Shipping.dll not found in archive"; return 1; }

    # After extraction the full installer may now be present — run it if so.
    if [ -f "$_eos_installer" ]; then
        print_info "Running EpicOnlineServicesInstaller.exe extracted from SDK..."
        timeout 300 \
        STEAM_COMPAT_DATA_PATH="$WINEPREFIX" \
        STEAM_COMPAT_CLIENT_INSTALL_PATH="$WINE_DIR/steam-root" \
        PROTON_LOG=0 \
            "$PROTON_DIR/proton" run \
            "C:\\Program Files (x86)\\Epic Games\\Epic Online Services\\EpicOnlineServicesInstaller.exe" \
            /install /silent >/dev/null 2>&1 || true
    fi

    _set_eos_registry
    _build_eos_compat_layer || true
    touch "$_stamp"
    print_success "EOS runtime installed (SDK v1.19.1.2)"
}

# Post-install Wine registry fixes for apps that need service or install-key setup.
# _reg_only=1 (third arg): registry-only mode — skip post-install installers (used by quick_setup).
# _flags (fourth arg): forwarded to sub-installers, e.g. --force for install_eos_runtime.
_post_install_registry() {
    local app_key="$1" installer_path="${2:-}" _reg_only="${3:-0}" _flags="${4:-}"
    local _reg="$WINEPREFIX/pfx/drive_c/windows/temp/wg-post-install.reg"
    mkdir -p "$(dirname "$_reg")"
    case "$app_key" in
        epic-games)
            # DEMAND_START stops EpicGamesUpdater; DLL overrides prevent the overlay host from crashing under Wine.
            printf 'Windows Registry Editor Version 5.00\n\n'\
'[HKEY_LOCAL_MACHINE\\SYSTEM\\ControlSet001\\Services\\EpicGamesUpdater]\n'\
'"Start"=dword:00000003\n'\
'"FailureActions"=hex:00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00\n\n'\
'[HKEY_CURRENT_USER\\Software\\Epic Games\\EOS]\n'\
'"IsDisableAutoUpdate"=dword:00000001\n\n'\
'[HKEY_CURRENT_USER\\Software\\Epic Games\\EGL]\n'\
'"DisableEOSOverlay"=dword:00000001\n\n'\
'[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\EpicGamesLauncher.exe\\Environment]\n'\
'"EOS_NO_AUTOUPDATE"="1"\n'\
'"DISABLE_EOS_OVERLAY"="1"\n\n'\
'[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\EpicGamesLauncher.exe\\DllOverrides]\n'\
'"EOSOverlayRenderer-Win64-Shipping"="disabled"\n'\
'"eosovh-win64-shipping"="disabled"\n\n'\
'[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\EpicOnlineServicesHost.exe\\Environment]\n'\
'"EOS_NO_AUTOUPDATE"="1"\n\n'\
'[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\EpicOnlineServicesHost.exe\\DllOverrides]\n'\
'"eosovh-win64-shipping"="disabled"\n' \
                > "$_reg"
            STEAM_COMPAT_DATA_PATH="$WINEPREFIX" \
            STEAM_COMPAT_CLIENT_INSTALL_PATH="$WINE_DIR/steam-root" \
                "$PROTON_DIR/proton" run regedit /s "C:\\windows\\temp\\wg-post-install.reg" >/dev/null 2>&1 || true
            # Install EOS runtime; pass any force flag through so --reinstall --force re-runs the EOS installer.
            if [ "$_reg_only" != "1" ]; then
                install_eos_runtime "$_flags"
            fi
            ;;
        ea-desktop)
            local _v; _v=$(basename "${installer_path}" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            _v="${_v:-13.759.0.0}"
            printf 'Windows Registry Editor Version 5.00\n\n'\
'[HKEY_LOCAL_MACHINE\\SOFTWARE\\Electronic Arts\\EA Desktop]\n'\
'"InstallDir"="C:\\\\Program Files\\\\Electronic Arts\\\\EA Desktop\\\\EA Desktop\\\\"\n'\
'"Version"="'"$_v"'"\n\n'\
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
                > "$_reg"
            "$PROTON_DIR/proton" run regedit /s "C:\\windows\\temp\\wg-post-install.reg" >/dev/null 2>&1 || true
            ;;
    esac
}

# Install a registered launcher via Proton.
# Usage: install_app "app-key" [custom_installer_path]
install_app() {
    local app_key="$1"
    local custom_installer="$2"
    local _install_flags="${3:-}"  # forwarded to _post_install_registry (e.g. --force)

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
    # PROTON_LOG=1 routes Wine subprocess stderr to a file (not a pipe), preventing installers that check GetFileType(STD_ERROR_HANDLE) from aborting on pipe detection.
    export PROTON_LOG=1
    export PROTON_LOG_DIR="$WINE_DIR"
    mkdir -p "$WINE_DIR/steam-root"
    mkdir -p "$WINEPREFIX"
    _map_external_drives

    # Pre-create dirs that installers expect to already exist (prevents DirectoryNotFoundException).
    if [ -d "$WINEPREFIX/pfx/drive_c" ]; then
        mkdir -p \
            "$WINEPREFIX/pfx/drive_c/ProgramData/EA Desktop" \
            "$WINEPREFIX/pfx/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs/EA" \
            "$WINEPREFIX/pfx/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs/Epic Games" \
            "$WINEPREFIX/pfx/drive_c/Program Files/Epic Games/Launcher/Portal/Extras/EOS" \
            2>/dev/null || true
    fi

    if [ ! -d "$WINEPREFIX/pfx" ]; then
        print_warning "First run: building the Wine prefix — this takes a minute or two with no output."
    fi
    print_info "An installer window may open — complete it there; this step waits until it closes."

    local -a run_cmd
    local -a _extra; read -ra _extra <<< "${APP_INSTALL_ARGS[$app_key]:-}"
    case "${installer_path,,}" in
        *.msi)
            # Stash Epic user data before MSI to preserve login tokens and LauncherInstalled.dat.
            local _msi_mode="/i"
            if [ "$app_key" = "epic-games" ] && [ -d "$WINEPREFIX/pfx/drive_c" ]; then
                local _epic_stash="$WINE_DIR/.epic-stash-$$"
                mkdir -p "$_epic_stash"
                local _pc="$WINEPREFIX/pfx/drive_c"
                for _d in                     "users/steamuser/AppData/Local/EpicGamesLauncher"                     "users/steamuser/AppData/Local/EpicGamesPlatform"                     "ProgramData/Epic/EpicGamesLauncher"                     "ProgramData/Epic/UnrealEngineLauncher"                     "ProgramData/Epic/EpicOnlineServices"; do
                    [ -d "$_pc/$_d" ] && { mkdir -p "$_epic_stash/$(dirname "$_d")"; mv "$_pc/$_d" "$_epic_stash/$_d"; }
                done
                # /fa (repair) reinstalls all files but preserves registry and user data in place.
                find_app_exe "$app_key" >/dev/null 2>&1 && _msi_mode="/fa"
            fi
            run_cmd=(msiexec "$_msi_mode" "$installer_path" /passive REBOOT=ReallySuppress \
                /log "C:\\windows\\temp\\${app_key}-msi.log" "${_extra[@]}")
            ;;
        *)
            run_cmd=("$installer_path" "${_extra[@]}")
            ;;
    esac

    # timeout prevents indefinite stall if a GUI installer fails to close.
    timeout 600 "$PROTON_DIR/proton" run "${run_cmd[@]}" 2>&1 \
        | awk '/MonoBtlsPkcs12\.Import|Missing private key/ { c++; next }
               /^info:  |^warn:  |^GnuTLS error:|^ProtonFixes\[/ { dxvk++; next }
               { print }
               END {
                   if (c+0>0)    printf "[WARN] %d Mono TLS cert exceptions suppressed\n", c
                   if (dxvk+0>0) printf "[note] %d DXVK/Proton diagnostic lines suppressed\n", dxvk
               }' \
        | tee "$install_log" || true

    if find_app_exe "$app_key" >/dev/null 2>&1; then
        print_success "$APP_NAME installed successfully"
        _post_install_registry "$app_key" "$installer_path" "0" "$_install_flags"
        _ensure_cacerts
        # Restore stashed user data (Epic login tokens, game library manifest).
        if [ -n "${_epic_stash:-}" ] && [ -d "${_epic_stash:-}" ]; then
            cp -rT "$_epic_stash" "$WINEPREFIX/pfx/drive_c" 2>/dev/null && rm -rf "$_epic_stash" || true
        fi
        create_shortcut "$app_key" && print_success "Desktop shortcut created" || true
        print_info "Install log: $install_log"
        local _msi_log_ok="$WINEPREFIX/pfx/drive_c/windows/temp/${app_key}-msi.log"
        [ -f "$_msi_log_ok" ] && print_info "MSI log    : $_msi_log_ok"
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
