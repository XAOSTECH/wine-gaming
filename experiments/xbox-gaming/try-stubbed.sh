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

# Iter 9: optional service-query trace.
#   TRACE_SERVICES=1 ./try-stubbed.sh ...
# Wine's debug channels are routed by Proton into ~/.wine-gaming/steam-*.log
# (because wig sets PROTON_LOG=1). We enable +advapi,+service before launch
# so Proton picks them up, then tail the resulting log.
if [ "${TRACE_SERVICES:-0}" = "1" ]; then
    PROTON_LOG_DIR="${HOME}/.wine-gaming"
    SUMMARY="${SCRIPT_DIR}/service-trace.log"
    echo "[trace] Enabling WINEDEBUG=+advapi,+service"
    echo "[trace] Proton will write to: ${PROTON_LOG_DIR}/steam-*.log"
    echo "[trace] Filtered summary will be at: ${SUMMARY}"
    export WINEDEBUG="+advapi,+service"
    # Snapshot existing logs so we know which one is new
    BEFORE=$(ls -1 "${PROTON_LOG_DIR}"/steam-*.log 2>/dev/null | sort)
    wig launch-exe "$EXE"
    sleep 3
    AFTER=$(ls -1 "${PROTON_LOG_DIR}"/steam-*.log 2>/dev/null | sort)
    NEW_LOG=$(comm -13 <(echo "$BEFORE") <(echo "$AFTER") | tail -1)
    if [ -z "$NEW_LOG" ]; then
        # Fall back to most recently modified
        NEW_LOG=$(ls -t "${PROTON_LOG_DIR}"/steam-*.log 2>/dev/null | head -1)
    fi
    echo "[trace] Detected log: ${NEW_LOG:-<none>}"
    if [ -n "$NEW_LOG" ]; then
        echo "[trace] Tailing log live. Ctrl+C when EULA dialog appears."
        echo "[trace] After Ctrl+C, summary is written to ${SUMMARY}"
        # Live tail with extraction; on exit, build the summary
        trap 'echo; echo "[trace] Building summary..."; \
              grep -aE "OpenServiceW|QueryServiceStatus|StartServiceW|EnumServicesStatus|OpenSCManagerW" "$NEW_LOG" \
                | sed -E "s/^.*(OpenServiceW|QueryServiceStatus|StartServiceW|EnumServicesStatus|OpenSCManagerW)/\1/" \
                | sort -u > "$SUMMARY"; \
              echo "[trace] Found $(wc -l < "$SUMMARY") unique service-related calls."; \
              echo "[trace] Top hits:"; head -20 "$SUMMARY"; exit 0' INT
        tail -f "$NEW_LOG"
    fi
    exit 0
fi

exec wig launch-exe "$EXE"
