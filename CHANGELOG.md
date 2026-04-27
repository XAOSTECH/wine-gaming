
## [0.1.1] - 2026-04-27 (re-release)

### Added
- --profile flag for launch and install-shortcut
- user app registry with optional launcher grouping; wig add/remove
- install gamemode/mangohud via apt; add install-shortcut all
- per-launcher launch profiles for FPS cap, HUD, FSR, NVAPI, gamemode
- global wig wrapper, auto-icon extraction for desktop shortcuts

### Fixed
- split winetricks into per-verb passes with progress; stream heavy verbs
- send log helpers to stderr; drop chromium flags; redirect proton output
- update install paths
- update download link and install paths
- notice on re-run when prefix exists, suppress wineboot stderr noise
- PNG-first icon extraction with .ico fallback for corrupt group_icons

### Changed
- refactor(profile): move profiles to XDG_CONFIG_HOME with auto-migration
- Merge pull request #2 from XAOSTECH/anglicise/20260415-232714
- chore: convert American spellings to British English
- chore: update CHANGELOG for v0.1.1 (re-release)
- chore(readme): document wig global command, icon extraction, new commands, directories, v1.1 changelog
- refactor: simplify icon extraction — .ico direct, drop icotool
- chore: update git tree visualisation
- chore: update git tree visualisation

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

