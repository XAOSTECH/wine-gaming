#!/bin/bash
# lib/aliases.sh — wig-* shell alias generation and management
# Sourced by setup; do not execute directly.
# Depends on: lib/config.sh, lib/utils.sh
# SETUP_SCRIPT_PATH must be set by the setup entrypoint before sourcing this file.

ALIAS_FILE="${HOME}/.config/wine-gaming/aliases.sh"
WIG_LOCATION="${HOME}/.config/wine-gaming/location"
WIG_BIN="${HOME}/.local/bin/wig"

# Write wig-* aliases to ALIAS_FILE and wire them into ~/.bashrc.
# Also creates ~/.local/bin/wig — a path-agnostic wrapper that resolves the
# wine-gaming directory at runtime, so aliases survive folder moves.
# After running, reload the shell: source ~/.bashrc (or open a new terminal).
install_aliases() {
    local setup_path="${SETUP_SCRIPT_PATH:-}"

    if [ -z "$setup_path" ] || [ ! -f "$setup_path" ]; then
        print_error "Cannot resolve setup script path. Run this from the wine-gaming directory."
        return 1
    fi

    mkdir -p "$(dirname "$ALIAS_FILE")" "${HOME}/.local/bin"

    # Persist the setup script location — wig reads this to find setup even after folder moves.
    echo "$setup_path" > "$WIG_LOCATION"

    # Create ~/.local/bin/wig — the single global entry point for wine-gaming.
    # Uses the location file as indirection so it stays valid if the folder is moved
    # (just re-run ./setup install-aliases from the new location to refresh).
    cat > "$WIG_BIN" << 'WIG_EOF'
#!/bin/bash
# wig — wine-gaming global wrapper (auto-generated — do not edit manually)
# If the wine-gaming folder is moved, re-run: ./setup install-aliases
_wig_loc="${HOME}/.config/wine-gaming/location"
if [ ! -f "$_wig_loc" ]; then
    echo "wig: wine-gaming not configured. Run: ./setup install-aliases" >&2
    exit 1
fi
_wig_setup="$(cat "$_wig_loc")"
if [ ! -x "$_wig_setup" ]; then
    echo "wig: setup script not found at: $_wig_setup" >&2
    echo "     Folder moved? Re-run from the new location: ./setup install-aliases" >&2
    exit 1
fi
exec "$_wig_setup" "$@"
WIG_EOF
    chmod +x "$WIG_BIN"

    # Write alias definitions — thin wrappers around wig for shell tab-completion convenience.
    cat > "$ALIAS_FILE" << ALIAS_EOF
# wine-gaming shell aliases — auto-generated on $(date '+%Y-%m-%d %H:%M')
# Managed by: $setup_path  (via wig: $WIG_BIN)
# Do not edit manually — re-run: ./setup install-aliases

alias wig-launch='wig launch'
alias wig-launch-exe='wig launch-exe'
alias wig-install='wig install'
alias wig-install-all='wig install-all'
alias wig-uninstall='wig uninstall'
alias wig-list='wig list'
alias wig-init='wig init'
alias wig-purge='wig purge'
alias wig-info='wig prefix-info'
alias wig-shortcuts='wig install-shortcut'
alias wig-profile='wig profile'
alias wig-help='wig help'
ALIAS_EOF

    print_success "Global wrapper created: $WIG_BIN"
    print_success "Aliases written to $ALIAS_FILE"

    # Wire into ~/.bashrc if not already present.
    local bashrc="${HOME}/.bashrc"
    local source_line="[ -f \"$ALIAS_FILE\" ] && source \"$ALIAS_FILE\"  # wine-gaming aliases"

    if grep -qF "wine-gaming aliases" "$bashrc" 2>/dev/null; then
        print_info "~/.bashrc already sources wine-gaming aliases (no change needed)"
    else
        printf '\n%s\n' "$source_line" >> "$bashrc"
        print_success "Added to ~/.bashrc: source $ALIAS_FILE"
    fi

    # Warn if ~/.local/bin is not yet in PATH.
    if [[ ":$PATH:" != *":${HOME}/.local/bin:"* ]]; then
        print_warning "~/.local/bin is not in your PATH. Add to ~/.bashrc:"
        echo '    export PATH="$HOME/.local/bin:$PATH"'
    fi

    echo ""
    print_info "Available wig-* aliases (also: wig <command> directly):"
    grep "^alias" "$ALIAS_FILE" | sed 's/alias /  /'
    echo ""
    print_warning "To activate in this terminal, run:"
    echo "    source ~/.bashrc"
    print_info "Or open a new terminal — aliases will be available automatically from then on."
    print_info "Folder moved later? Just re-run: ./setup install-aliases"
}

# Remove the alias file, wig wrapper, location file and scrub the ~/.bashrc entry.
remove_aliases() {
    if [ -f "$ALIAS_FILE" ]; then
        rm -f "$ALIAS_FILE"
        print_success "Alias file removed: $ALIAS_FILE"
    else
        print_info "Alias file not found (already removed?)"
    fi

    if [ -f "$WIG_BIN" ]; then
        rm -f "$WIG_BIN"
        print_success "wig wrapper removed: $WIG_BIN"
    fi

    [ -f "$WIG_LOCATION" ] && rm -f "$WIG_LOCATION"

    local bashrc="${HOME}/.bashrc"
    if grep -qF "wine-gaming aliases" "$bashrc" 2>/dev/null; then
        # Remove the source line (and the blank line before it if any)
        sed -i '/wine-gaming aliases/d' "$bashrc"
        print_success "Removed wine-gaming aliases source line from ~/.bashrc"
    fi
}

# Print the currently installed wig-* aliases and wig wrapper status.
show_aliases() {
    if [ -f "$ALIAS_FILE" ]; then
        print_info "Installed wine-gaming aliases (from $ALIAS_FILE):"
        grep "^alias" "$ALIAS_FILE" | sed 's/alias /  /'
        echo ""
        if [ -f "$WIG_BIN" ]; then
            local setup_path
            setup_path=$(cat "$WIG_LOCATION" 2>/dev/null || echo "unknown")
            print_info "wig wrapper: $WIG_BIN"
            print_info "  → $setup_path"
        else
            print_warning "wig wrapper not found at $WIG_BIN — re-run: ./setup install-aliases"
        fi
    else
        print_warning "No aliases installed. Run: ./setup install-aliases"
    fi
}
