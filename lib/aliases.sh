#!/bin/bash
# lib/aliases.sh — wig-* shell alias generation and management
# Sourced by setup; do not execute directly.
# Depends on: lib/config.sh, lib/utils.sh
# SETUP_SCRIPT_PATH must be set by the setup entrypoint before sourcing this file.

ALIAS_FILE="${HOME}/.config/wine-gaming/aliases.sh"

# Write wig-* aliases to ALIAS_FILE and wire them into ~/.bashrc.
# After running, reload the shell: source ~/.bashrc (or open a new terminal).
install_aliases() {
    local setup_path="${SETUP_SCRIPT_PATH:-}"

    if [ -z "$setup_path" ] || [ ! -f "$setup_path" ]; then
        print_error "Cannot resolve setup script path. Run this from the wine-gaming directory."
        return 1
    fi

    mkdir -p "$(dirname "$ALIAS_FILE")"

    # Write alias definitions — $setup_path expands at write time, giving absolute paths.
    cat > "$ALIAS_FILE" << ALIAS_EOF
# wine-gaming shell aliases — auto-generated on $(date '+%Y-%m-%d %H:%M')
# Managed by: $setup_path
# Do not edit manually — re-run: ./setup install-aliases

alias wig-launch='$setup_path launch'
alias wig-launch-exe='$setup_path launch-exe'
alias wig-install='$setup_path install'
alias wig-install-all='$setup_path install-all'
alias wig-uninstall='$setup_path uninstall'
alias wig-list='$setup_path list'
alias wig-init='$setup_path init'
alias wig-purge='$setup_path purge'
alias wig-info='$setup_path prefix-info'
alias wig-shortcuts='$setup_path install-shortcut'
alias wig-help='$setup_path help'
ALIAS_EOF

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

    echo ""
    print_info "Available wig-* aliases:"
    grep "^alias" "$ALIAS_FILE" | sed 's/alias /  /'
    echo ""
    print_warning "To activate in this terminal, run:"
    echo "    source ~/.bashrc"
    print_info "Or open a new terminal — aliases will be available automatically from then on."
}

# Remove the alias file and scrub the source line from ~/.bashrc.
remove_aliases() {
    if [ -f "$ALIAS_FILE" ]; then
        rm -f "$ALIAS_FILE"
        print_success "Alias file removed: $ALIAS_FILE"
    else
        print_info "Alias file not found (already removed?)"
    fi

    local bashrc="${HOME}/.bashrc"
    if grep -qF "wine-gaming aliases" "$bashrc" 2>/dev/null; then
        # Remove the source line (and the blank line before it if any)
        sed -i '/wine-gaming aliases/d' "$bashrc"
        print_success "Removed wine-gaming aliases source line from ~/.bashrc"
    fi
}

# Print the currently installed wig-* aliases.
show_aliases() {
    if [ -f "$ALIAS_FILE" ]; then
        print_info "Installed wine-gaming aliases (from $ALIAS_FILE):"
        grep "^alias" "$ALIAS_FILE" | sed 's/alias /  /'
    else
        print_warning "No aliases installed. Run: ./setup install-aliases"
    fi
}
