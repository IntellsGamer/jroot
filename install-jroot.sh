#!/usr/bin/env bash
# =============================================================================
# install-jroot.sh - Install jroot (no host root required)
#
# Everything is user-local: the jroot script goes to ~/.local/bin and the
# PATH/alias block goes into ~/.bashrc. sudo is never needed.
#
# Usage:  bash install-jroot.sh
# Env:    JROOT_URL=<url>   download the jroot script from a URL instead of
#                           the copy sitting next to this installer.
# =============================================================================
set -e

C_RED='\033[1;31m'; C_GRN='\033[1;32m'; C_YEL='\033[1;33m'; C_NC='\033[0m'
log()  { echo -e "${C_GRN}[+]${C_NC} $1"; }
warn() { echo -e "${C_YEL}[!]${C_NC} $1"; }
err()  { echo -e "${C_RED}[!]${C_NC} $1" >&2; exit 1; }

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JROOT_SRC="$SRC_DIR/jroot"
INSTALL_DIR="$HOME/.local/bin"
JROOT_HOME="$HOME/.jroot"
BASHRC="$HOME/.bashrc"
PROFILE="$HOME/.profile"

# --- Detect an existing install ---------------------------------------------
existing=""
[ -f "$INSTALL_DIR/jroot" ] && existing="$INSTALL_DIR/jroot"
[ -z "$existing" ] && [ -f /usr/local/bin/jroot ] && existing="/usr/local/bin/jroot"

if [ -n "$existing" ]; then
    echo "jroot is already installed at: $existing"
    echo "  1) Clean reinstall (removes ALL jails + configs, reinstalls fresh)"
    echo "  2) Upgrade (keep jails + configs, replace the jroot script)"
    echo "  3) Cancel"
    read -rp "Choose [1/2/3]: " choice
    case "$choice" in
        1)
            rm -rf "$JROOT_HOME"
            rm -f "$INSTALL_DIR/jroot" 2>/dev/null || true
            rm -f /usr/local/bin/jroot 2>/dev/null || true
            log "Removed existing jroot install and all jails."
            ;;
        2)
            warn "Upgrade mode: keeping $JROOT_HOME (jails + configs preserved)."
            ;;
        3|"")
            echo "Cancelled."
            exit 0
            ;;
        *)
            echo "Invalid choice. Cancelled."
            exit 1
            ;;
    esac
fi

# --- Install the script ------------------------------------------------------
mkdir -p "$INSTALL_DIR"

if [ -n "${JROOT_URL:-}" ]; then
    log "Downloading jroot from $JROOT_URL"
    curl -fsSL --connect-timeout 15 -o "$INSTALL_DIR/jroot" "$JROOT_URL" || err "Download failed"
else
    [ -f "$JROOT_SRC" ] || err "jroot script not found next to installer: $JROOT_SRC"
    cp "$JROOT_SRC" "$INSTALL_DIR/jroot"
fi
chmod +x "$INSTALL_DIR/jroot"
mkdir -p "$JROOT_HOME/roots" "$JROOT_HOME/configs" "$JROOT_HOME/bin"
log "Installed jroot to $INSTALL_DIR/jroot"

# --- bashrc aliases + PATH (idempotent) --------------------------------------
append_jroot_block() {
    local file="$1"
    [ -f "$file" ] || : > "$file"
    if ! grep -qF '# >>> jroot >>>' "$file" 2>/dev/null; then
        cat >> "$file" << 'EOF'

# >>> jroot >>>
export PATH="$HOME/.local/bin:$PATH"
alias jenter='jroot enter'
alias jlist='jroot list'
alias jconfig='jroot config'
# <<< jroot <<<
EOF
        log "Added jroot PATH + aliases to $file"
    else
        log "jroot block already present in $file (left untouched)"
    fi
}

append_jroot_block "$BASHRC"
append_jroot_block "$PROFILE"

# --- Done ---------------------------------------------------------------------
log "=== INSTALLED ==="
log "  Command:     jroot help"
log "  Jails dir:   $JROOT_HOME"
log "  New shells will have it. To enable in this shell:"
log "      source ~/.bashrc"
log "  Create your first jail:"
log "      jroot init ubuntu:22.04"
