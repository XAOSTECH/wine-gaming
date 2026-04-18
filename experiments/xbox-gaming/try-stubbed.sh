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

    SUMMARISED=0
    WINESERVER_BIN="${PROTON_DIR}/bin/wineserver"

    summarise() {
        [ "$SUMMARISED" = "1" ] && return
        SUMMARISED=1
        trap - INT TERM EXIT
        echo
        echo "[trace] Stopping installer..."
        # Kill via wineserver (clean) — avoids pkill matching our own argv
        [ -x "$WINESERVER_BIN" ] && "$WINESERVER_BIN" -k 2>/dev/null
        echo "[trace] Building summary from $(wc -l < "$RAW") raw lines..."
        grep -aE "OpenServiceW|OpenServiceA|QueryServiceStatus|StartServiceW|EnumServicesStatus|OpenSCManagerW|CreateServiceW|RegisterEventSourceW|ReportEventW" "$RAW" \
            | grep -aoE "(OpenServiceW|OpenServiceA|QueryServiceStatus[A-Za-z]*|StartServiceW|EnumServicesStatus[A-Za-z]*|OpenSCManagerW|CreateServiceW|RegisterEventSourceW|ReportEventW)[^]*{0,200}" \
            | sort -u > "$SUMMARY" 2>/dev/null || true
        # Simpler, more reliable extraction:
        grep -aE "service:(OpenServiceW|OpenServiceA|StartServiceW|EnumServicesStatus|OpenSCManagerW|CreateServiceW|GetServiceKeyNameW)" "$RAW" \
            | sed -E 's/^[0-9a-f]+://; s/^[[:space:]]+//' \
            | sort -u > "$SUMMARY" 2>/dev/null || true
        echo "[trace] Found $(wc -l < "$SUMMARY") unique service calls."
        echo "[trace] Names the installer queried (likely missing from prefix):"
        grep -oE 'L"[^"]+"' "$SUMMARY" | sort -u | head -40
        echo
        echo "[trace] Error-event sites in log (the 'something went wrong' moments):"
        grep -nE "ReportEventW|RegisterEventSourceW" "$RAW" | head -10 || true
    }

    trap 'summarise; exit 0' INT TERM

    # Run wine in background so we have a real PID to wait on
    "$WINE_BIN" "$EXE" > >(tee "$RAW") 2>&1 &
    WINE_PID=$!
    wait "$WINE_PID" 2>/dev/null || true
    summarise
    exit 0
fi

exec wig launch-exe "$EXE"
