#!/bin/bash
# build-and-install-stub.sh — compile the WinRT contract stub and place it
# into the wine-gaming prefix so Mono can resolve the reference.
#
# Requires: ilasm  (apt: mono-devel, OR shipped inside Wine-Mono)
# Usage:    ./build-and-install-stub.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WINE_DIR="${WINE_GAMING_HOME:-${HOME}/.wine-gaming}"
PREFIX="${WINE_DIR}/prefix/pfx"

IL_SRC="${SCRIPT_DIR}/UniversalApiContract.il"
DLL_OUT="${SCRIPT_DIR}/Windows.Foundation.UniversalApiContract.dll"

if [ ! -f "$IL_SRC" ]; then
    echo "ERROR: $IL_SRC not found" >&2
    exit 1
fi

# Locate ilasm — prefer system Mono, fall back to Wine-Mono's bundled one.
ILASM=""
if command -v ilasm &>/dev/null; then
    ILASM="ilasm"
elif command -v ilasm-4 &>/dev/null; then
    ILASM="ilasm-4"
else
    # Wine-Mono ships ilasm.exe under proton-ge — would need wine to invoke
    cand=$(find "${WINE_DIR}/proton-ge" -name "ilasm*" -type f 2>/dev/null | head -1 || true)
    if [ -n "$cand" ]; then
        echo "Found bundled ilasm at $cand — but it's a Windows binary."
        echo "Install host ilasm instead: sudo apt install mono-devel"
        exit 1
    fi
    echo "ERROR: ilasm not found. Install with: sudo apt install mono-devel" >&2
    exit 1
fi

echo "[1/3] Compiling stub via $ILASM..."
cd "$SCRIPT_DIR"
"$ILASM" /dll /output:"$DLL_OUT" "$IL_SRC"

echo "[2/3] Locating .NET 4 GAC inside prefix..."
# Native .NET 4.x GAC layout (after winetricks dotnet48):
#   <prefix>/drive_c/windows/Microsoft.NET/assembly/GAC_MSIL/<name>/v4.0_<ver>__<token>/<name>.dll
GAC_BASE="${PREFIX}/drive_c/windows/Microsoft.NET/assembly/GAC_MSIL"
if [ ! -d "$GAC_BASE" ]; then
    echo "ERROR: GAC not found at $GAC_BASE" >&2
    echo "       Run: ./setup init   (installs dotnet48 via winetricks)" >&2
    exit 1
fi

GAC_DEST="${GAC_BASE}/Windows.Foundation.UniversalApiContract/v4.0_7.0.0.0__null"
mkdir -p "$GAC_DEST"

echo "[3/3] Installing to $GAC_DEST"
cp "$DLL_OUT" "$GAC_DEST/Windows.Foundation.UniversalApiContract.dll"

# Also drop a copy alongside the installer .exe — Mono checks the application
# directory before the GAC, which is the most reliable resolution path.
APP_DIR_HINT="${1:-}"
if [ -n "$APP_DIR_HINT" ] && [ -d "$APP_DIR_HINT" ]; then
    cp "$DLL_OUT" "$APP_DIR_HINT/"
    echo "      Also copied to: $APP_DIR_HINT"
fi

echo ""
echo "Stub installed. Next: ./try-stubbed.sh /path/to/XboxInstaller.exe"
