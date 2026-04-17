#!/bin/bash
# build-and-install-stub.sh — compile every .il in this directory and place the
# resulting .dll into the wine-gaming prefix so Mono can resolve the references.
#
# Iterative stub strategy: each missing WinRT contract assembly gets its own
# .il file. Add new ones as Mono surfaces them; this script picks them all up.
#
# Requires: ilasm  (apt: mono-devel)
# Usage:    ./build-and-install-stub.sh [optional-app-dir-to-also-copy-into]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WINE_DIR="${WINE_GAMING_HOME:-${HOME}/.wine-gaming}"
PREFIX="${WINE_DIR}/prefix/pfx"

# Locate ilasm.
ILASM=""
if command -v ilasm &>/dev/null; then
    ILASM="ilasm"
elif command -v ilasm-4 &>/dev/null; then
    ILASM="ilasm-4"
else
    echo "ERROR: ilasm not found. Install with: sudo apt install mono-devel" >&2
    exit 1
fi

GAC_BASE="${PREFIX}/drive_c/windows/Microsoft.NET/assembly/GAC_MSIL"
if [ ! -d "$GAC_BASE" ]; then
    echo "ERROR: GAC not found at $GAC_BASE" >&2
    echo "       Run: ./setup init   (installs dotnet48 via winetricks)" >&2
    exit 1
fi

APP_DIR_HINT="${1:-}"
shopt -s nullglob

count=0
for il_src in "$SCRIPT_DIR"/*.il; do
    count=$((count + 1))
    base=$(basename "$il_src" .il)

    # Read assembly name + version from the .il itself — single source of truth.
    # Exclude `.assembly extern <name>` lines (those declare references, not the asm itself).
    asm_name=$(awk '/^\.assembly[[:space:]]+extern/ {next}
                    /^\.assembly[[:space:]]+[A-Za-z]/ {print $2; exit}' "$il_src")
    asm_ver=$(awk -v target="$asm_name" '
                    $0 ~ "^\\.assembly[[:space:]]+" target "([[:space:]]|$)" {inblock=1; next}
                    inblock && /\.ver[[:space:]]+/ {gsub(":", ".", $2); print $2; exit}
                    inblock && /^}/ {exit}' "$il_src")

    if [ -z "$asm_name" ] || [ -z "$asm_ver" ]; then
        echo "WARN: $il_src — could not parse assembly name/version (got name='$asm_name' ver='$asm_ver'), skipping"
        continue
    fi

    dll_out="${SCRIPT_DIR}/${asm_name}.dll"

    echo "[${count}] Compiling $base.il → $asm_name $asm_ver"
    if ! "$ILASM" /nologo /quiet /dll /output:"$dll_out" "$il_src"; then
        echo "      ✗ ilasm FAILED on $il_src" >&2
        exit 1
    fi

    # GAC path: GAC_MSIL/<Name>/v4.0_<ver>__null/<Name>.dll
    gac_dest="${GAC_BASE}/${asm_name}/v4.0_${asm_ver}__null"
    mkdir -p "$gac_dest"
    cp "$dll_out" "$gac_dest/${asm_name}.dll"
    echo "      → GAC: $gac_dest"

    # Also drop alongside the installer if a path was provided.
    if [ -n "$APP_DIR_HINT" ] && [ -d "$APP_DIR_HINT" ]; then
        cp "$dll_out" "$APP_DIR_HINT/"
    fi
done

if [ $count -eq 0 ]; then
    echo "No .il files found in $SCRIPT_DIR"
    exit 1
fi

echo ""
echo "Built and installed $count stub(s)."
[ -n "$APP_DIR_HINT" ] && echo "Also copied into: $APP_DIR_HINT"
echo "Next: ./try-stubbed.sh /path/to/XboxInstaller.exe"
