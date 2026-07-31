#!/bin/bash
# lib/utils.sh — Coloured print helpers and sanity checks
# Sourced by setup; do not execute directly.

# All log helpers write to stderr so command substitution
# `var=$(some_func)` only captures genuine return values (e.g. paths).
print_info()    { echo -e "\033[1;36m[INFO]\033[0m $1" >&2; }
print_error()   { echo -e "\033[1;31m[ERROR]\033[0m $1" >&2; }
print_success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1" >&2; }
print_warning() { echo -e "\033[1;33m[WARN]\033[0m $1" >&2; }

# Verify Proton-GE binary is present before operations that require it.
check_proton() {
    if [ ! -x "$PROTON_DIR/proton" ]; then
        print_error "Proton not found at $PROTON_DIR. Run: $0 install-proton"
        return 1
    fi
    # A missing bundled kernel32.dll means an on-access AV quarantined it as a
    # false positive; without it Proton dies mid-prefix-build with a raw traceback.
    if [ ! -f "$PROTON_DIR/files/share/default_pfx/drive_c/windows/syswow64/kernel32.dll" ]; then
        print_error "Proton-GE is incomplete — bundled kernel32.dll is gone."
        print_error "An on-access scanner (e.g. clamav-clamonacc) likely quarantined it (false positive)."
        print_error "Recover: sudo systemctl stop clamav-clamonacc && $0 install-proton && sudo systemctl start clamav-clamonacc"
        print_error "To stop it recurring, exclude \"$PROTON_DIR\" from on-access scanning (see docs/README)."
        return 1
    fi
    return 0
}

# Run "$@" with clamav on-access scanning paused, if it is active. ClamAV
# false-positives on Proton's bundled Windows PE DLLs and can quarantine them
# as they are written. No-op when clamonacc isn't running.
run_without_oas() {
    if command -v systemctl &>/dev/null && systemctl is-active --quiet clamav-clamonacc 2>/dev/null; then
        print_warning "Pausing clamav-clamonacc for this step (avoids DLL false-positive quarantine)..."
        sudo systemctl stop clamav-clamonacc
        "$@"; local rc=$?
        sudo systemctl start clamav-clamonacc && print_info "clamav-clamonacc resumed."
        return $rc
    fi
    "$@"
}
