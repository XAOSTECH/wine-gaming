
## [0.1.1] - 2026-08-03 (re-release)

### Added
- add --reinstall flag to init/full/quick
- add i386 arch, wine, wine64, wine32:i386, winetricks
- detect AV-quarantined Proton DLL and guide recovery
- expand knob catalogue (DLSS-SR/RR, Reflex, FSR custom res, NV power, shader cache)
- --profile flag for launch and install-shortcut
- user app registry with optional launcher grouping; wig add/remove
- install gamemode/mangohud via apt; add install-shortcut all

### Fixed
- remove wineboot, fix winetricks target/wine-binary, drop system-wine calls
- winetricks skip guard, WINETRICKS_LATEST_VERSION_CHECK=enabled, Proton install noise filter, EA Desktop exe path
- repair check_proton message and widen exclude to WINE_DIR
- install MSIs via msiexec and verify the app actually landed
- pause clamav on-access during Proton-GE extraction
- enable Proton log and warn on slow first-run prefix build
- create prefix dir before Proton acquires pfx.lock
- guard empty app key to avoid bad array subscript
- split winetricks into per-verb passes with progress; stream heavy verbs

### Changed
- chore: update deps, workflow, URL
- chore: update git tree visualisation
- refactor(profile): move profiles to XDG_CONFIG_HOME with auto-migration

## [0.1.1] - 2026-04-15 (re-release)

### Added
- global wig wrapper, auto-icon extraction for desktop shortcuts

### Fixed
- notice on re-run when prefix exists, suppress wineboot stderr noise
- PNG-first icon extraction with .ico fallback for corrupt group_icons

### Changed
- chore(readme): document wig global command, icon extraction, new commands, directories, v1.1 changelog
- refactor: simplify icon extraction — .ico direct, drop icotool
- chore: update git tree visualisation
- chore: update git tree visualisation
- Merge pull request #1 from XAOSTECH/anglicise/20260401-002733
- chore: convert American spellings to British English
- chore: update CHANGELOG for v0.1.1 (re-release)
- chore(dc-init): load workflows,actions
- chore(dc-init): load workflows,actions
- chore(dc-init): update workflows,actions
- chore(dc-init): recover interrupted update
- refactor: modularise into lib/ directory
- chore: clean up docs
- chore: update CHANGELOG for v0.1.1
- Add managed prefix info and external EXE launcher command
- security: add global and command route rate limiting

## [0.1.1] - 2026-03-30 (re-release)

### Changed
- chore(dc-init): load workflows,actions
- chore(dc-init): load workflows,actions
- chore(dc-init): update workflows,actions
- chore(dc-init): recover interrupted update
- refactor: modularise into lib/ directory
- chore: clean up docs
- chore: update CHANGELOG for v0.1.1
- Add managed prefix info and external EXE launcher command
- security: add global and command route rate limiting
- chore(dc-init): update workflows and actions
- gc-init

## [0.1.1] - 2026-03-13

### Changed
- Add managed prefix info and external EXE launcher command
- security: add global and command route rate limiting
- chore(dc-init): update workflows and actions
- gc-init

