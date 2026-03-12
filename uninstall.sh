#!/data/data/com.termux/files/usr/bin/bash
# uninstall.sh — yt-dlp-termux clean removal
# Item 5.6: removes all installed files, symlinks, and optionally Alpine proot.

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SCRIPT_DIR}/lib/common.sh" 2>/dev/null || {
    COMMON="${XDG_CONFIG_HOME:-$HOME/.config}/yt-dlp-termux/lib/common.sh"
    source "$COMMON" 2>/dev/null || {
        log()   { echo "[*] $*"; }
        ok()    { echo "[✓] $*"; }
        warn()  { echo "[!] $*" >&2; }
        error() { echo "[✗] $*" >&2; }
        die()   { error "$*"; exit 1; }
    }
}

INSTALL_BASE="${XDG_CONFIG_HOME:-$HOME/.config}/yt-dlp-termux"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/yt-dlp-termux"
BIN_DIR="${HOME}/bin"

echo ""
echo "╔════════════════════════════════════════╗"
echo "║      yt-dlp-termux uninstaller         ║"
echo "╚════════════════════════════════════════╝"
echo ""
warn "This will remove yt-dlp-termux from your system."
warn "Your personal user.conf will be preserved by default."
echo ""
read -rp "Continue? [y/N]: " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { log "Aborted."; exit 0; }

# ─── Remove ~/bin symlink and termux-url-opener ───────────────────────────────
log "Removing ~/bin/yt-termux symlink..."
[[ -L "${BIN_DIR}/yt-termux" ]] && rm -f "${BIN_DIR}/yt-termux" && ok "Removed: ~/bin/yt-termux"

log "Checking termux-url-opener..."
if [[ -f "${BIN_DIR}/termux-url-opener" ]] \
   && grep -q "# yt-dlp-termux managed" "${BIN_DIR}/termux-url-opener" 2>/dev/null; then
    rm -f "${BIN_DIR}/termux-url-opener"
    ok "Removed: ~/bin/termux-url-opener"
    # Restore backup if one exists
    LATEST_BACKUP=$(ls -t "${BIN_DIR}/termux-url-opener.backup."* 2>/dev/null | head -1 || true)
    if [[ -n "$LATEST_BACKUP" ]]; then
        mv "$LATEST_BACKUP" "${BIN_DIR}/termux-url-opener"
        ok "Restored previous termux-url-opener from backup: ${LATEST_BACKUP}"
    fi
fi

# ─── Remove Termux:Boot script ────────────────────────────────────────────────
BOOT_SCRIPT="${HOME}/.termux/boot/start-bgutil.sh"
if [[ -f "$BOOT_SCRIPT" ]]; then
    log "Removing Termux:Boot script..."
    rm -f "$BOOT_SCRIPT"
    ok "Removed: ${BOOT_SCRIPT}"
fi

# ─── Optionally preserve user.conf ────────────────────────────────────────────
USER_CONF="${INSTALL_BASE}/config/user.conf"
PRESERVE_USER=true
if [[ -f "$USER_CONF" ]]; then
    echo ""
    read -rp "Keep your personal user.conf? [Y/n]: " _KEEP || _KEEP="y"
    [[ "$_KEEP" =~ ^[Nn]$ ]] && PRESERVE_USER=false
fi

# ─── Remove install base ─────────────────────────────────────────────────────
log "Removing ${INSTALL_BASE}..."
if [[ "$PRESERVE_USER" == "true" && -f "$USER_CONF" ]]; then
    TMPCONF="$(mktemp)"
    cp "$USER_CONF" "$TMPCONF"
    rm -rf "$INSTALL_BASE"
    mkdir -p "$(dirname "$USER_CONF")"
    mv "$TMPCONF" "$USER_CONF"
    ok "Removed install directory. user.conf preserved at: ${USER_CONF}"
else
    rm -rf "$INSTALL_BASE"
    ok "Removed: ${INSTALL_BASE}"
fi

# ─── Remove state/log directory ───────────────────────────────────────────────
if [[ -d "$STATE_DIR" ]]; then
    echo ""
    read -rp "Remove log directory (${STATE_DIR})? [y/N]: " _RM_LOGS || _RM_LOGS="n"
    if [[ "$_RM_LOGS" =~ ^[Yy]$ ]]; then
        rm -rf "$STATE_DIR"
        ok "Removed: ${STATE_DIR}"
    fi
fi

# ─── Optionally remove Alpine proot ──────────────────────────────────────────
echo ""
read -rp "Remove Alpine proot (frees ~500 MB)? [y/N]: " _RM_ALPINE || _RM_ALPINE="n"
if [[ "$_RM_ALPINE" =~ ^[Yy]$ ]]; then
    log "Removing Alpine proot-distro..."
    proot-distro remove alpine && ok "Alpine proot removed."
fi

echo ""
ok "yt-dlp-termux uninstalled."
echo ""
