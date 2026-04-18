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
    [ea-desktop]="EA Desktop|Program Files/Electronic Arts/EA Desktop/EA Desktop/EADesktop.exe|https://origin-a.akamaihd.net/EA-Desktop-Client-Download/installer/Pc/EAappInstaller.exe|Program Files/Electronic Arts|AppData/Local/Electronic Arts|AppData/Roaming/Electronic Arts"

    [gog-galaxy]="GOG Galaxy|Program Files (x86)/GOG Galaxy/GalaxyClient.exe|https://cdn.gog.com/Open/GOG%20Galaxy/GOG_Galaxy_2.0.exe|Program Files (x86)/GOG Galaxy|AppData/Local/GOG.com|AppData/Roaming/GOG.com"

    [epic-games]="Epic Games Launcher|ProgramData/Epic/EpicGamesLauncher/Data/Update/Install/Portal/Binaries/Win64/EpicGamesLauncher.exe|https://launcher-public-service-prod.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncherInstaller.msi|Program Files/Epic Games|AppData/Local/EpicGamesLauncher|ProgramData/Epic"

    [ubisoft-connect]="Ubisoft Connect|Program Files/Ubisoft/Ubisoft Game Launcher/upc.exe|https://ubisoftconnect.com/en-US/downloads|Program Files/Ubisoft|AppData/Local/Ubisoft"

    [amazon-games]="Amazon Games|users/steamuser/AppData/Local/Amazon Games/App/Amazon Games.exe|https://download.amazongames.com/AmazonGamesSetup.exe|users/steamuser/AppData/Local/Amazon Games|users/steamuser/AppData/Roaming/Amazon Games|ProgramData/Amazon Games"

    [legacy-games]="Legacy Games|Program Files/Legacy Games/Legacy Games/Legacy.exe|https://legacy.games/download|Program Files/Legacy Games|AppData/Local/Legacy Games"
)
