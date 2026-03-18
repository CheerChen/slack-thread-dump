#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
DEST="${PREFIX}/bin/slack-thread-dump"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "Usage: $0 [install|uninstall|check]"
    echo ""
    echo "Commands:"
    echo "  install    Install slack-thread-dump (default)"
    echo "  uninstall  Uninstall slack-thread-dump"
    echo "  check      Check installation location"
    exit 1
}

do_install() {
    mkdir -p "${PREFIX}/bin"
    cp "${SCRIPT_DIR}/slack-thread-dump.sh" "${DEST}"
    chmod +x "${DEST}"
    echo "✅ Installed slack-thread-dump to ${DEST}"
    echo "Make sure ${PREFIX}/bin is on your PATH."
}

do_uninstall() {
    # Check using which command
    local installed_path
    installed_path=$(which slack-thread-dump 2>/dev/null || true)
    
    if [[ -z "${installed_path}" ]]; then
        echo "❌ slack-thread-dump is not installed or not in PATH."
        # Try to remove from default location anyway
        if [[ -f "${DEST}" ]]; then
            rm -f "${DEST}"
            echo "✅ Removed ${DEST}"
        fi
        return 0
    fi
    
    echo "Found slack-thread-dump at: ${installed_path}"
    rm -f "${installed_path}"
    echo "✅ Uninstalled slack-thread-dump from ${installed_path}"
}

do_check() {
    local installed_path
    installed_path=$(which slack-thread-dump 2>/dev/null || true)
    
    if [[ -z "${installed_path}" ]]; then
        echo "❌ slack-thread-dump is not installed or not in PATH."
        if [[ -f "${DEST}" ]]; then
            echo "However, found at default location: ${DEST}"
            echo "Make sure ${PREFIX}/bin is on your PATH."
        fi
        return 1
    fi
    
    echo "✅ slack-thread-dump is installed at: ${installed_path}"
    
    # Show version or first line if available
    if [[ -f "${installed_path}" ]]; then
        local version_line
        version_line=$(head -n 5 "${installed_path}" | grep -i "version" || true)
        if [[ -n "${version_line}" ]]; then
            echo "   ${version_line}"
        fi
    fi
}

# Parse command line arguments
case "${1:-install}" in
    install)
        do_install
        ;;
    uninstall)
        do_uninstall
        ;;
    check)
        do_check
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        echo "Unknown command: $1"
        usage
        ;;
esac
