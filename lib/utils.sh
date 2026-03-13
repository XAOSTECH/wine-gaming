#!/bin/bash
# lib/utils.sh — Coloured print helpers and sanity checks
# Sourced by setup; do not execute directly.

print_info()    { echo -e "\033[1;36m[INFO]\033[0m $1"; }
print_error()   { echo -e "\033[1;31m[ERROR]\033[0m $1" >&2; }
print_success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }
print_warning() { echo -e "\033[1;33m[WARN]\033[0m $1"; }

# Verify Proton-GE binary is present before operations that require it.
check_proton() {
    if [ ! -x "$PROTON_DIR/proton" ]; then
        print_error "Proton not found at $PROTON_DIR. Run: $0 install-proton"
        return 1
    fi
    return 0
}
