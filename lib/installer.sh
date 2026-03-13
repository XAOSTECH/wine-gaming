#!/bin/bash
# lib/installer.sh — Installer download with caching
# Sourced by setup; do not execute directly.
# Depends on: lib/config.sh, lib/utils.sh, lib/registry.sh

# Download installer for an app key, returning the local path.
# Cached copies in CACHE_DIR are reused without re-downloading.
# Usage: download_installer "app-key"
# Returns: path to installer file
download_installer() {
    local app_key="$1"

    parse_app_config "$app_key" || return 1

    local filename
    filename=$(basename "${APP_URL}" | cut -d'?' -f1)
    local cache_path="$CACHE_DIR/$filename"

    if [ -f "$cache_path" ]; then
        print_info "Using cached installer: $filename"
        echo "$cache_path"
        return 0
    fi

    print_info "Downloading installer for $APP_NAME..."
    print_info "Source: $APP_URL"

    if ! wget -q --show-progress -O "$cache_path" "$APP_URL"; then
        print_error "Failed to download installer from $APP_URL"
        rm -f "$cache_path"
        return 1
    fi

    print_success "Installer downloaded: $cache_path"
    echo "$cache_path"
    return 0
}
