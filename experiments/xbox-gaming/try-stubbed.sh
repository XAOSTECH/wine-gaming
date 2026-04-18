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

# Iter 9c: optional service-query trace, bypassing wig.
#   TRACE_SERVICES=1 ./try-stubbed.sh ...
# Calls wine directly with WINEDEBUG so stderr lands in our terminal and
# can be tee'd to a log file. The installer GUI still opens normally; we
# stay attached so Ctrl+C cleanly stops the trace.
if [ "${TRACE_SERVICES:-0}" = "1" ]; then
    SUMMARY="${SCRIPT_DIR}/service-trace.log"
    RAW="${SCRIPT_DIR}/service-trace.raw.log"
    PREFIX="${HOME}/.wine-gaming/prefix/pfx"
    PROTON_DIR="${HOME}/.wine-gaming/proton-ge/files"
    WINE_BIN="${PROTON_DIR}/bin/wine64"
    [ -x "$WINE_BIN" ] || WINE_BIN="${PROTON_DIR}/bin/wine"
    if [ ! -x "$WINE_BIN" ]; then
        echo "[trace] ERROR: wine binary not found at ${PROTON_DIR}/bin/" >&2
        exit 1
    fi

    echo "[trace] Bypassing wig — calling wine directly so stderr is ours."
    echo "[trace] Wine binary: $WINE_BIN"
    echo "[trace] Prefix:      $PREFIX"
    echo "[trace] Raw log:     $RAW"
    echo "[trace] Summary:     $SUMMARY"
    echo "[trace] Press Ctrl+C in this terminal AFTER reaching EULA dialog."
    echo

    : > "$RAW"
    export WINEPREFIX="$PREFIX"
    export WINEDEBUG="+advapi,+service"
    # Suppress Proton-style env to avoid invoking Proton's wrapper
    unset STEAM_COMPAT_DATA_PATH STEAM_COMPAT_CLIENT_INSTALL_PATH PROTON_LOG

    trap '
        echo
        echo "[trace] Stopping installer..."
        pkill -TERM -f XboxInstaller 2>/dev/null
        sleep 1
        pkill -KILL -f XboxInstaller 2>/dev/null
        echo "[trace] Building summary from $(wc -l < "$RAW") raw lines..."
        grep -aE "OpenServiceW|OpenServiceA|QueryServiceStatus|StartServiceW|EnumServicesStatus|OpenSCManagerW|CreateServiceW" "$RAW" \
            | grep -aoE "\b(OpenServiceW|OpenServiceA|QueryServiceStatus|StartServiceW|EnumServicesStatus|OpenSCManagerW|CreateServiceW)[^\\r\\n]{0,200}" \
            | sort -u > "$SUMMARY" || true
        echo "[trace] Found $(wc -l < "$SUMMARY") unique service-related calls."
        echo "[trace] Top hits:"
        head -30 "$SUMMARY"
        exit 0
    ' INT TERM

    # Run wine in foreground; tee both to terminal and raw log
    "$WINE_BIN" "$EXE" 2>&1 | tee "$RAW"
    # If wine exits on its own, still build the summary
    kill -INT $$ 2>/dev/null
    exit 0
fi

exec wig launch-exe "$EXE"
