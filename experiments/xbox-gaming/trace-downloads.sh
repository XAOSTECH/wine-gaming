#!/usr/bin/env bash
# trace-downloads.sh — wrap try-stubbed.sh and catch what the installer writes.
#
# Strategy:
#   1. Snapshot the prefix's user-writable areas BEFORE launch
#   2. Run the installer (you interact with it normally)
#   3. After it exits (or you Ctrl+C), diff to find new/modified files
#   4. Report sizes, MIME types, and where they landed
#
# Usage: ./trace-downloads.sh /path/to/XboxInstaller.exe

set -euo pipefail

EXE="${1:-../../installers/XboxInstaller.exe}"
PREFIX="${WINEPREFIX:-$HOME/.wine-gaming/prefix/pfx}"
USERDIR="$PREFIX/drive_c/users"

if [[ ! -d "$USERDIR" ]]; then
  echo "Prefix user dir not found: $USERDIR"
  echo "Set WINEPREFIX or check that the prefix exists."
  exit 1
fi

# Areas Xbox installer is most likely to write into
WATCH_DIRS=(
  "$USERDIR"
  "$PREFIX/drive_c/ProgramData"
  "$PREFIX/drive_c/Program Files/WindowsApps"
  "$PREFIX/drive_c/Program Files (x86)/WindowsApps"
  "$PREFIX/drive_c/windows/Temp"
)

SNAPSHOT_BEFORE="$(mktemp /tmp/xbox-trace-before.XXXXXX)"
SNAPSHOT_AFTER="$(mktemp /tmp/xbox-trace-after.XXXXXX)"

snapshot() {
  local out="$1"
  : > "$out"
  for d in "${WATCH_DIRS[@]}"; do
    [[ -d "$d" ]] || continue
    # path<TAB>size<TAB>mtime
    find "$d" -type f -printf '%p\t%s\t%T@\n' 2>/dev/null >> "$out" || true
  done
}

echo "[trace] Snapshotting prefix BEFORE launch..."
snapshot "$SNAPSHOT_BEFORE"
echo "[trace] Baseline: $(wc -l < "$SNAPSHOT_BEFORE") files."
echo

echo "[trace] Launching installer. Interact with it normally."
echo "[trace] When it finishes (or you've seen enough), close the window or Ctrl+C here."
echo
echo "==================================================================="

# Run via try-stubbed.sh which sets the right WINEDLLOVERRIDES + uses wig
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/try-stubbed.sh" "$EXE" || true

echo "==================================================================="
echo
echo "[trace] Installer exited. Snapshotting AFTER..."
# Give Wine a moment to flush
sleep 2
snapshot "$SNAPSHOT_AFTER"
echo "[trace] Now: $(wc -l < "$SNAPSHOT_AFTER") files."
echo

REPORT="$(mktemp /tmp/xbox-trace-report.XXXXXX)"

# New files (present in AFTER, absent in BEFORE)
echo "=== NEW FILES ===" | tee "$REPORT"
comm -13 \
  <(cut -f1 "$SNAPSHOT_BEFORE" | sort -u) \
  <(cut -f1 "$SNAPSHOT_AFTER"  | sort -u) \
  > "${REPORT}.new"

# Modified files (same path, different size or mtime)
echo "=== MODIFIED FILES ===" >> "$REPORT"
join -t $'\t' \
  <(sort -k1,1 "$SNAPSHOT_BEFORE") \
  <(sort -k1,1 "$SNAPSHOT_AFTER") \
  2>/dev/null \
  | awk -F'\t' '$2 != $4 || $3 != $5 { print $1 }' \
  > "${REPORT}.modified" || true

NEW_COUNT=$(wc -l < "${REPORT}.new")
MOD_COUNT=$(wc -l < "${REPORT}.modified")

echo
echo "[trace] $NEW_COUNT new file(s), $MOD_COUNT modified file(s)."
echo

if [[ "$NEW_COUNT" -gt 0 ]]; then
  echo "=== Top 20 LARGEST new files (likely the download payload) ==="
  while IFS= read -r path; do
    [[ -f "$path" ]] || continue
    size=$(stat -c%s "$path" 2>/dev/null || echo 0)
    echo -e "${size}\t${path}"
  done < "${REPORT}.new" | sort -rn | head -20 | \
    awk -F'\t' '{
      s = $1
      unit = "B"
      if (s > 1048576) { s = s/1048576; unit = "MiB" }
      else if (s > 1024) { s = s/1024; unit = "KiB" }
      printf "  %8.1f %-3s  %s\n", s, unit, $2
    }'
  echo

  echo "=== File types (top 10) ==="
  while IFS= read -r path; do
    [[ -f "$path" ]] || continue
    file -b --mime-type "$path" 2>/dev/null
  done < "${REPORT}.new" | sort | uniq -c | sort -rn | head -10
  echo

  echo "=== Interesting filenames (msix, appx, cab, zip, json, xml, log) ==="
  grep -iE '\.(msix|msixbundle|appx|appxbundle|cab|zip|json|xml|log|exe|dll)$' "${REPORT}.new" || echo "  (none)"
  echo
fi

if [[ "$MOD_COUNT" -gt 0 && "$MOD_COUNT" -lt 50 ]]; then
  echo "=== Modified files ==="
  cat "${REPORT}.modified"
  echo
fi

echo "[trace] Full lists saved to:"
echo "  new:      ${REPORT}.new"
echo "  modified: ${REPORT}.modified"
echo
echo "[trace] To inspect a specific file:"
echo "  file '<path>'           # type"
echo "  hexdump -C '<path>' | head"
echo "  unzip -l '<path>'       # if .zip/.msix/.appx (they're all zip containers)"

# Cleanup snapshots, keep report
rm -f "$SNAPSHOT_BEFORE" "$SNAPSHOT_AFTER"
