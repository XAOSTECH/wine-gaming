
## [0.1.2] - 2026-10-19

### Added
- --verbose flag for live output; fix(apps): comprehensive EOS stubs from DLL export table
- EOS Wine compat layer — stub EOSSDK DLL + stub EOSBootstrapperApp.exe
- install EOS runtime from Epic SDK; add install-eos command

### Fixed
- remove extension dependency from tray fix
- restore Wine SNI tray context menu on GNOME Wayland
- use launcher-bundled EOS DLL as proxy backend; guard Binaries/Win64
- replace EOS stub with proxy DLL — real SDK forwarding + dialog intercept
- filter DXVK capability blocks in verbose; auto-show app log on exit
- EOS stub coverage + kill_wine permission error + launch log hints
- overhaul kill_wine — env scan, Proton wineserver, socket cleanup
- run EpicOnlineServicesInstaller.exe; stamp EOS; thread --force through reinstall
- correct PlayStation Plus exe to pspluslauncher.exe
- timeout fast winetricks verbs; remove enable-latest-version-check
- remove EOS_ENABLED and BootstrapperVersion — both caused regressions
- stamp heavy verbs after first attempt to prevent endless retry
- spoof EOS bootstrapper version to suppress update dialog
- replace winetricks cacerts with host CA bundle via Proton certutil
- inject EOS env vars directly at launch for epic-games
- remove wineboot -u from quick_setup
- suppress EOS update loop; re-apply registry on quick
- skip heavy winetricks verbs when already installed
- stash Epic user data before MSI; use /fa repair mode on reinstall
- suppress EOS host crash via Wine per-process env + DLL overrides
- pre-create EOS dir; disable EOS auto-update; run EOS installer post-install

### Changed
- chore: humanise hard-wrapped comments and prose
- chore(dc-init): update workflows,actions
- chore: convert American spellings to British English
- chore(dc-init): load workflows,actions

## [0.1.1] - 2026-08-10 (re-release)

### Added
- add --reinstall flag to init/full/quick
- add i386 arch, wine, wine64, wine32:i386, winetricks
- detect AV-quarantined Proton DLL and guide recovery

### Fixed
- register EABackgroundService, -EpicPortal launch arg
- configure EA and its bg services + create/export DXVK
- msiextract for EA Desktop, fix copy root, clean up Wine windows
- EA app direct MSI + admin install, Epic msiexec revert, winetricks pfx target, Proton wine64 for verbs, wineboot removal, noise filter, PROTON_LOG=1 pipe-detection fix, vcrun2022, pre-create Windows dirs, DisableRollback reg, WINEDLLOVERRIDES winemenubuilder=d, Z: drive removal, --reinstall flag propagation
- bypass EA bootstrapper; run MSI directly with MSIFASTINSTALL=3 EAX_LAUNCH_CLIENT=0
- pfx ProgramData folder creation + vcrun2022
- remove wineboot, fix winetricks target/wine-binary, drop system-wine calls
- winetricks skip guard, WINETRICKS_LATEST_VERSION_CHECK=enabled, Proton install noise filter, EA Desktop exe path
- repair check_proton message and widen exclude to WINE_DIR
- install MSIs via msiexec and verify the app actually landed
- pause clamav on-access during Proton-GE extraction
- enable Proton log and warn on slow first-run prefix build
- create prefix dir before Proton acquires pfx.lock
- guard empty app key to avoid bad array subscript

### Changed
- chore: update CHANGELOG for v0.1.1 (re-release)
- chore: update deps, workflow, URL

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

