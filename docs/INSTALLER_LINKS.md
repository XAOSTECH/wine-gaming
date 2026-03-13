# Launcher Download Links

External resources for game launcher installers. These are never committed to the repository due to binary file restrictions on GitHub.

## Launcher Installers

| Launcher | Download URL | Notes | Supported |
|----------|--------------|-------|-----------|
| **EA Desktop** | https://origin-a.akamaihd.net/EA-Desktop-Client-Download/installer/Pc/EAappInstaller.exe | Direct download, wget/curl compatible | ✅ Yes |
| **GOG Galaxy** | https://cdn.gog.com/Open/GOG%20Galaxy/GOG_Galaxy_2.0.exe | Direct download, wget/curl compatible | ✅ Yes |
| **Epic Games Launcher** | https://launcher-public-service-prod.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncherInstaller.msi | Direct download, wget/curl compatible | ✅ Yes |
| **Ubisoft Connect** | https://ubisoftconnect.com/en-US/downloads | May require browser User-Agent header | ⚠️ Partial |
| **Amazon Games** | https://amazon-games-launcher.s3.amazonaws.com/AmazonGamesSetup.exe | Direct download, wget/curl compatible | ✅ Yes |
| **Legacy Games** | https://legacy.games/download | Requires browser interaction | ❌ Manual only |

## How to Use

### Option A: Automatic Download (Recommended)
```bash
./setup install ea-desktop      # Auto-downloads installer
./setup install gog-galaxy
./setup install epic-games
./setup install-all             # Install all launchers (auto-downloads)
```

### Option B: Manual Download
1. Download installer from URL above
2. Save to `./installers/` directory
3. Run: `./setup install <app-key> ./installers/InstallerName.exe`

Example:
```bash
cd ~/PRO/SYS/WINE/wine-gaming
wget https://cdn.gog.com/Open/GOG%20Galaxy/GOG_Galaxy_2.0.exe -O installers/GOG_Galaxy_2.0.exe
./setup install gog-galaxy ./installers/GOG_Galaxy_2.0.exe
```

## Proton/Wine Dependencies

- **Wine**: 10.0+ (Ubuntu standard)
- **Proton-GE**: Downloaded automatically by `./setup install-proton`
  - Source: https://github.com/GloriousEggroll/proton-ge-custom/releases
  - Version: GE-Proton9-18 (configurable in script)
- **Winetricks**: Required, install via `apt install winetricks`

## Troubleshooting Download Issues

### "Failed to download installer"
1. Check internet connection
2. Verify URL is current (links may change)
3. Try manual download method above
4. Check `~/.cache/wine-installers/` for partial/corrupt files and delete them

### "User-Agent blocked"
For Ubisoft Connect (if needed):
```bash
wget --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64)" <URL> -O installers/ubisoft.exe
```

### "Launcher requires browser to download"
For Legacy Games and similar:
1. Download manually via browser to `./installers/`
2. Run: `./setup install legacy-games ./installers/Legacy.exe`

## Version Control Notes

- ✅ **DO commit**: Bash script (`setup`), documentation, YAML/JSON configs
- ❌ **DO NOT commit**: .exe/.msi files, wine prefix, cache directories
- ✅ **DO use** `.gitignore`: Prevents accidental binary uploads
- ✅ **DO use** `git lfs` (if needed): For rare binary assets under 100MB

See `.gitignore` for what's automatically excluded.
