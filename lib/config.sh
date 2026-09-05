#!/bin/bash
# lib/config.sh — Configuration variables and APP_REGISTRY
# Sourced by setup; do not execute directly.

# Allow overrides for container/host setups where HOME may not be preferred.
WINE_DIR="${WINE_GAMING_HOME:-${HOME}/.wine-gaming}"
WINEPREFIX="${WINE_DIR}/prefix"
PROTON_DIR="${WINE_DIR}/proton-ge"
BACKUP_DIR="${WINE_DIR}/backup"
CACHE_DIR="${WINE_GAMING_CACHE:-${HOME}/.cache/wine-installers}"
BIN_DIR="${WINE_DIR}/bin"
APPS_DIR="${WINE_GAMING_APPS_DIR:-${HOME}/.local/share/applications}"

export WINEPREFIX WINEARCH=win64
# DXVK reads this to disable OpenVR/OpenXR init on non-VR setups
DXVK_CONFIG_FILE="$WINE_DIR/dxvk.conf"
export DXVK_CONFIG_FILE

# Per-app install arguments for silent/unattended installation.
# NSIS EXEs: /VERYSILENT /SUPPRESSMSGBOXES /NORESTART; MSI properties appended to /qn.
declare -A APP_INSTALL_ARGS=(
    [gog-galaxy]="/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-"
    [epic-games]="LAUNCH=0"                    # MSI property: suppress post-install auto-launch
    [ubisoft-connect]="/VERYSILENT /SUPPRESSMSGBOXES /NORESTART"
    [ea-desktop]="/quiet /norestart"           # WiX Bundle flags for EAappInstaller.exe
    [legacy-games]="/S"
    [amazon-games]="/S"
    [ps-plus]="/S"
)

# Per-app launch arguments appended after the exe (e.g. force UI open)
declare -A APP_LAUNCH_ARGS=(
    [epic-games]="-EpicPortal"
)

# Colon-separated host paths to expose as Windows drive letters (D:, E:, …) in Wine.
# Useful for game libraries on external/NTFS drives accessed by Epic, GOG, etc.
# Example: WINE_EXTRA_DRIVES="/run/media/user/DATA-NTFS:/mnt/games"
WINE_EXTRA_DRIVES="${WINE_EXTRA_DRIVES:-}"

# Ensure necessary directories exist
mkdir -p "$WINE_DIR" "$BACKUP_DIR" "$CACHE_DIR" "$BIN_DIR" "$APPS_DIR" 2>/dev/null || true

# ============================================================================
# APP REGISTRY
# ============================================================================
# Format: [key]="Name|ExePath|DownloadURL|UninstallPath1|UninstallPath2|..."
# ExePath is relative to drive_c inside the Wine prefix.
# Add new launchers by appending entries here.
#
declare -A APP_REGISTRY=(
    [ea-desktop]="EA Desktop|Program Files/Electronic Arts/EA Desktop/EA Desktop/EADesktop.exe|https://origin-a.akamaihd.net/EA-Desktop-Client-Download/installer-releases/EAapp-13.759.2.6273-14790298.msi|Program Files/Electronic Arts|AppData/Local/Electronic Arts|AppData/Roaming/Electronic Arts"

    [gog-galaxy]="GOG Galaxy|Program Files (x86)/GOG Galaxy/GalaxyClient.exe|https://webinstallers.gog-statics.com/download/GOG_Galaxy_2.0.exe|Program Files (x86)/GOG Galaxy|AppData/Local/GOG.com|AppData/Roaming/GOG.com"

    [epic-games]="Epic Games Launcher|Program Files/Epic Games/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe|https://launcher-public-service-prod.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncherInstaller.msi|Program Files/Epic Games|AppData/Local/EpicGamesLauncher|ProgramData/Epic"

    [ubisoft-connect]="Ubisoft Connect|Program Files/Ubisoft/Ubisoft Game Launcher/upc.exe|https://ubisoftconnect.com/en-US/downloads|Program Files/Ubisoft|AppData/Local/Ubisoft"

    [amazon-games]="Amazon Games|users/steamuser/AppData/Local/Amazon Games/App/Amazon Games.exe|https://download.amazongames.com/AmazonGamesSetup.exe|users/steamuser/AppData/Local/Amazon Games|users/steamuser/AppData/Roaming/Amazon Games|ProgramData/Amazon Games"

    [legacy-games]="Legacy Games|users/steamuser/AppData/Local/Programs/legacy-games-launcher/Legacy Games Launcher.exe|https://cdn.legacygames.com/LegacyGamesLauncher/legacy-games-launcher-setup-1.16.7-x64-full.exe|users/steamuser/AppData/Local/Programs/legacy-games-launcher|users/steamuser/AppData/Local/legacy-games-launcher-updater|users/steamuser/AppData/Roaming/Legacy Games Launcher"

    [ps-plus]="PlayStation Plus|Program Files (x86)/PlayStationPlus/PlayStationPlus.exe|https://download-psplus.playstation.com/downloads/psplus/pc/latest|Program Files (x86)/PlayStationPlus|users/steamuser/AppData/Roaming/playstation-plus|users/steamuser/AppData/Roaming/playstation-now"
)
