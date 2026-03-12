#!/data/data/com.termux/files/usr/bin/bash
# bgutil-autostart.sh — one-time installer for bgutil auto-start on Termux launch
#
# What this script does:
#   1. Appends a background start hook to ~/.bashrc so bgutil starts
#      automatically every time a new Termux session opens.
#   2. Writes ~/.termux/boot/start-bgutil.sh for users with Termux:Boot
#      installed, which fires the server on device reboot.
#
# Run once:
#   chmod +x bgutil-autostart.sh && ./bgutil-autostart.sh
#
# To undo:
#   Remove the bgutil block from ~/.bashrc manually.
#   Delete ~/.termux/boot/start-bgutil.sh if present.

set -euo pipefail

BGUTIL_CMD="proot-distro login alpine -- deno run -A /root/bgutil-ytdlp-pot-provider/server/build/main.js"
BOOT_DIR="$HOME/.termux/boot"
BOOT_SCRIPT="$BOOT_DIR/start-bgutil.sh"
BASHRC="$HOME/.bashrc"
MARKER="# bgutil-autostart"

echo "[*] bgutil-autostart.sh — one-time installer"
echo ""

# ============================================
# STEP 1 — ~/.bashrc hook
# ============================================
if grep -q "$MARKER" "$BASHRC" 2>/dev/null; then
    echo "[=] ~/.bashrc hook already present. Skipping."
else
    echo "[*] Writing ~/.bashrc hook..."
    cat >> "$BASHRC" << EOF

$MARKER — added by bgutil-autostart.sh
# Starts the bgutil HTTP server in the background when a Termux session opens.
# The server runs on http://127.0.0.1:4416 inside Alpine proot via Deno.
if ! curl -s http://127.0.0.1:4416 > /dev/null 2>&1; then
    echo "[bgutil] Starting server in background..."
    $BGUTIL_CMD > /tmp/bgutil.log 2>&1 &
    disown
fi
EOF
    echo "[+] ~/.bashrc hook written."
fi

# ============================================
# STEP 2 — Termux:Boot script
# ============================================
if [[ -d "$BOOT_DIR" ]] || command -v termux-reload-settings &>/dev/null; then
    mkdir -p "$BOOT_DIR"

    if [[ -f "$BOOT_SCRIPT" ]]; then
        echo "[=] Termux:Boot script already present at $BOOT_SCRIPT. Skipping."
    else
        echo "[*] Writing Termux:Boot script..."
        cat > "$BOOT_SCRIPT" << EOF
#!/data/data/com.termux/files/usr/bin/bash
# start-bgutil.sh — fires on device reboot via Termux:Boot
termux-wake-lock
$BGUTIL_CMD > /tmp/bgutil-boot.log 2>&1 &
disown
EOF
        chmod +x "$BOOT_SCRIPT"
        echo "[+] Termux:Boot script written to $BOOT_SCRIPT."
    fi
else
    echo "[~] Termux:Boot directory not found."
    echo "    If you have the Termux:Boot app installed, create it manually:"
    echo "    mkdir -p ~/.termux/boot"
    echo "    Then re-run this script."
fi

# ============================================
# DONE
# ============================================
echo ""
echo "[*] Installation complete."
echo ""
echo "    The bgutil server will now start automatically:"
echo "    - On every new Termux session (via ~/.bashrc)"
if [[ -f "$BOOT_SCRIPT" ]]; then
echo "    - On device reboot (via Termux:Boot)"
fi
echo ""
echo "    To verify the server is running:"
echo "    curl http://127.0.0.1:4416"
echo "    Expected response: 'Cannot GET /' (server alive)"
echo ""
echo "    Logs: /tmp/bgutil.log (session) and /tmp/bgutil-boot.log (boot)"
