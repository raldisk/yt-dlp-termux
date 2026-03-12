#!/data/data/com.termux/files/usr/bin/bash
# bgutil-autostart.sh — configures Termux:Boot autostart for bgutil HTTP server
#
# Items implemented:
#   1.4  Termux:Boot detection now checks for BOOT_DIR existence, not
#        termux-reload-settings (which ships with termux-tools on every instance)

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_COMMON="${_SCRIPT_DIR}/../lib/common.sh"
[[ -f "$_COMMON" ]] || _COMMON="${XDG_CONFIG_HOME:-$HOME/.config}/yt-dlp-termux/lib/common.sh"
[[ -f "$_COMMON" ]] && source "$_COMMON" || {
    log()  { echo "[*] $*"; }
    warn() { echo "[!] $*" >&2; }
    error(){ echo "[✗] $*" >&2; }
    die()  { error "$*"; exit 1; }
}

BOOT_DIR="${HOME}/.termux/boot"
BOOT_SCRIPT="${BOOT_DIR}/start-bgutil.sh"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/yt-dlp-termux"

BGUTIL_START_CONTENT='#!/data/data/com.termux/files/usr/bin/bash
# Termux:Boot autostart — bgutil HTTP server
# Managed by yt-dlp-termux bgutil-autostart.sh
termux-wake-lock
proot-distro login alpine -- \
    deno run -A \
    /root/bgutil-ytdlp-pot-provider/server/build/main.js \
    >> "${XDG_STATE_HOME:-$HOME/.local/state}/yt-dlp-termux/bgutil-boot.log" 2>&1 &
'

# item 1.4: use directory existence — the only reliable signal that
# Termux:Boot is installed. termux-reload-settings ships with termux-tools
# on every Termux instance, making it a false positive as a detection method.
if [[ -d "$BOOT_DIR" ]]; then
    log "Termux:Boot directory found — installing autostart script..."
    mkdir -p "$BOOT_DIR"
    printf '%s' "$BGUTIL_START_CONTENT" > "$BOOT_SCRIPT"
    chmod +x "$BOOT_SCRIPT"
    log "Autostart installed: ${BOOT_SCRIPT}"
    log "bgutil server will start automatically on device boot."
else
    log "Termux:Boot directory not found — skipping autostart setup."
    log "To enable: install Termux:Boot from F-Droid, open it once,"
    log "then re-run this script. The boot directory will be created."
fi
