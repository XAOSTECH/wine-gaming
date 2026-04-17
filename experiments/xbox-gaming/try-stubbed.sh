#!/bin/bash
# try-stubbed.sh — launch Xbox installer after the WinRT contract stub
# has been installed via build-and-install-stub.sh.
#
# Strategy: native .NET 4.8 + stub assembly available in the GAC and (ideally)
# alongside the installer .exe.
#
# Usage:  ./try-stubbed.sh /path/to/XboxInstaller.exe

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUB_DLL="${SCRIPT_DIR}/Windows.Foundation.UniversalApiContract.dll"

EXE="${1:-}"
if [ -z "$EXE" ] || [ ! -f "$EXE" ]; then
    echo "Usage: $0 /path/to/XboxInstaller.exe" >&2
    exit 1
fi

if [ ! -f "$STUB_DLL" ]; then
    echo "Stub not built. Run: ./build-and-install-stub.sh" >&2
    exit 1
fi

EXE_DIR=$(dirname "$(readlink -f "$EXE")")

# Always re-place the stub next to the installer — Mono's probing order checks
# the application directory first, which is more reliable than the GAC.
cp "$STUB_DLL" "$EXE_DIR/" 2>/dev/null || true

export WINEDLLOVERRIDES="mscoree,mscorwks,clr=n,b"

exec wig launch-exe "$EXE"
