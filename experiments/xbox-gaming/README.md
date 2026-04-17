# Xbox Gaming on Wine — Experimental

Research branch: attempting to run Microsoft's Xbox PC app installer (`XboxInstaller.exe`)
through the wine-gaming managed Proton prefix.

> **Status:** ⚠️ Experimental — not wired into the main `setup` script.
> The Xbox PC app depends on UWP/MSIX + Microsoft Gaming Services (Windows Store
> components). Even if the installer runs, the app itself may never sign in or
> download games. This directory documents what was tried and why.

## The wall

The installer is a WPF app that crashes during XAML parse:

```
System.TypeLoadException: Could not load type of field
'XboxInstaller.Helpers.TextScaling+UnsafeUiSettings:_uiSettings' (0)
due to: Could not load file or assembly
'Windows.Foundation.UniversalApiContract, Version=7.0.0.0,
Culture=neutral, PublicKeyToken=null'
```

`Windows.Foundation.UniversalApiContract` is a **WinRT contract assembly** —
metadata-only, no executable code. Wine-Mono ships zero WinRT interop, so even
though the installer only uses it for one harmless feature (text scaling /
accessibility DPI), the missing reference poisons the entire WPF resource
dictionary on line 375 of `App.xaml`, killing the process before any window
draws.

## Approaches tried

### 1. `WINEDLLOVERRIDES` on the WinRT assembly name

```bash
WINEDLLOVERRIDES="Windows.Foundation.UniversalApiContract=" wig launch-exe XboxInstaller.exe
```

**Result:** No effect. `WINEDLLOVERRIDES` only intercepts Win32 native DLL loads
via Wine's loader. .NET assembly resolution is handled by Mono's own runtime,
which never consults Wine's override map.

### 2. Silent-mode flags

```bash
wig launch-exe XboxInstaller.exe /S /silent /quiet
```

**Result:** Same crash. The crash happens in `App..ctor()` before any
command-line parsing — silent mode is a runtime flag of an app that never
manages to construct.

### 3. Force native .NET 4.8 over Wine-Mono

```bash
WINEDLLOVERRIDES="mscoree=n,mscorwks=n" wig launch-exe XboxInstaller.exe
```

`mscoree` is the .NET runtime loader. `n` = native (the real .NET 4.8 installed
inside the prefix by `winetricks dotnet48`). The default `b` = builtin =
Wine-Mono, which has no WinRT interop.

**See:** `try-native-dotnet.sh`.

### 4. Stub the WinRT contract assembly

`Windows.Foundation.UniversalApiContract` is a facade — pure metadata, no
methods with bodies. We can synthesise an empty assembly with the exact same
name + version + public key token, drop it into the prefix's GAC, and Mono
will resolve the reference. The `UISettings` type-load failure becomes a
runtime null instead of an assembly-load failure, and the WPF `Setter`
initialisation can complete.

**See:** `UniversalApiContract.il` and `build-and-install-stub.sh`.

#### Iteration 1 — empty assembly

Mono *did* load the empty stub, but failed at the next step:

```
Could not resolve type with token 0100008d from typeref
(expected class 'Windows.UI.ViewManagement.UISettings'
 in assembly 'Windows.Foundation.UniversalApiContract...')
```

Progress: assembly resolution succeeded, type resolution failed.

#### Iteration 2 — define the UISettings class skeleton

Added a minimal `Windows.UI.ViewManagement.UISettings` class with:

- Parameterless constructor (`new UISettings()`)
- `TextScaleFactor` property → returns `1.0` (no scaling)
- `TextScaleFactorChanged` event → no-op add/remove

Result: progress! Failure shifted from `UnsafeUiSettings:_uiSettings` (field
load) to `SafeUiSettings..ctor` (called) — `TextScaling` has a
try/catch that falls back to a different `UISettings` accessor when the
unsafe path fails. New missing assembly:

```
Could not load file or assembly
'Windows.Foundation.FoundationContract, Version=3.0.0.0,
 Culture=neutral, PublicKeyToken=null'
```

#### Iteration 3 — generalise to multiple stub assemblies

Build script now compiles every `*.il` in this directory and installs each
to its correct GAC path. Added empty `FoundationContract.il` (3.0.0.0) — we'll
let Mono surface the next type-resolution error to drive iter 4.

#### Iteration 4 — TypedEventHandler + PackageManager (the wall)

Got past `TextScaling` entirely. New stack frame:

```
at XboxInstaller.MainWindow.InitializeAsync ()
```

The static initialisers are done — we're now in real app code. Two new
type-resolution failures:

1. `Windows.Foundation.TypedEventHandler<TSender, TResult>` in
   `FoundationContract` — the WinRT generic event delegate. Stubbed as a
   normal MulticastDelegate.
2. **`Windows.Management.Deployment.PackageManager`** in `UniversalApiContract`
   — UWP/MSIX package management. **This is the hard wall.** Stubbed so the
   field load succeeds, but every method throws `NotSupportedException`
   with a clear message.

After iter 4 we expect MainWindow to actually construct and the app to
fail on the first `PackageManager` method call — which is the *real*
limitation, not a Mono/Wine bug.

## Files

| File | Purpose |
|------|---------|
| `UniversalApiContract.il` | Stub for WinRT contract — defines `UISettings` skeleton |
| `FoundationContract.il` | Stub for `Windows.Foundation.FoundationContract` (iter 3) |
| `build-and-install-stub.sh` | Compile every `*.il` and place into prefix GAC |
| `try-native-dotnet.sh` | Launch wrapper using `mscoree=n` override |
| `try-stubbed.sh` | Launch wrapper after stubs are installed |

## Honest ceiling

Even if the installer succeeds, the Xbox app needs:

- **MSIX runtime** — Wine has no UWP package activation
- **Microsoft.GamingServices** — distributed only through the Windows Store
- **xgameruntime / Microsoft.UI.Xaml** — additional WinRT surfaces
- **PlayReady DRM** for downloaded games

Crossing those walls is an order of magnitude harder than this installer crash.
This branch exists to document the boundary.
