#!/data/data/com.termux/files/usr/bin/bash
# ytdlp-run.sh — interactive yt-dlp launcher with bgutil HTTP server management
#
# Usage:
#   ./ytdlp-run.sh             → interactive menu (no URL argument)
#   ./ytdlp-run.sh "URL"       → direct single-video download (solo config)
#
# Menu options:
#   1) Single video  — termux-solo.conf
#   2) Playlist      — termux-playlist.conf
#   3) Batch file    — opens batchfile.txt in nano, then runs after confirm
#   4) Audio only    — termux-audio.conf

set -euo pipefail

# ============================================
# PATHS
# ============================================
GITHUB_DIR="$HOME/storage/shared/Github"
CONFIG_SOLO="$GITHUB_DIR/config/termux-solo.conf"
CONFIG_PLAYLIST="$GITHUB_DIR/config/termux-playlist.conf"
CONFIG_AUDIO="$GITHUB_DIR/config/termux-audio.conf"
BATCHFILE="$GITHUB_DIR/batchfile.txt"
PORT=4416
BGUTIL_CMD="proot-distro login alpine -- deno run -A /root/bgutil-ytdlp-pot-provider/server/build/main.js"

# ============================================
# HELPERS
# ============================================
start_server() {
    echo "[*] Acquiring wake lock..."
    termux-wake-lock

    echo "[*] Starting bgutil HTTP server..."
    $BGUTIL_CMD &
    SERVER_PID=$!

    echo "[*] Waiting for server on port $PORT..."
    for i in $(seq 1 30); do
        if curl -s "http://127.0.0.1:$PORT" > /dev/null 2>&1; then
            echo "[*] Server ready (${i}s)."
            return 0
        fi
        sleep 1
    done

    echo "[!] Server did not respond within 30s. Continuing anyway..."
}

stop_server() {
    echo "[*] Shutting down bgutil server (PID $SERVER_PID)..."
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    termux-wake-unlock
    echo "[*] Wake lock released."
}

run_ytdlp() {
    local config="$1"
    shift
    echo "[*] Running yt-dlp with config: $(basename "$config")"
    yt-dlp --config-location "$config" "$@"
}

# ============================================
# DIRECT MODE — URL passed as argument
# ============================================
if [[ $# -gt 0 ]]; then
    start_server
    trap stop_server EXIT
    run_ytdlp "$CONFIG_SOLO" "$@"
    exit 0
fi

# ============================================
# INTERACTIVE MENU
# ============================================
echo ""
echo "  yt-dlp Termux Runner"
echo "  ─────────────────────────────────────────"
echo "  1) Single video   (termux-solo.conf)"
echo "  2) Playlist       (termux-playlist.conf)"
echo "  3) Batch file     (edit batchfile.txt → run)"
echo "  4) Audio only     (termux-audio.conf)"
echo "  ─────────────────────────────────────────"
printf "  Select [1-4]: "
read -r CHOICE

case "$CHOICE" in

    1)
        printf "  URL: "
        read -r URL
        [[ -z "$URL" ]] && echo "[!] No URL entered. Exiting." && exit 1
        start_server
        trap stop_server EXIT
        run_ytdlp "$CONFIG_SOLO" "$URL"
        ;;

    2)
        printf "  Playlist URL: "
        read -r URL
        [[ -z "$URL" ]] && echo "[!] No URL entered. Exiting." && exit 1
        start_server
        trap stop_server EXIT
        run_ytdlp "$CONFIG_PLAYLIST" "$URL"
        ;;

    3)
        [[ ! -f "$BATCHFILE" ]] && touch "$BATCHFILE"

        echo ""
        echo "  Opening batchfile.txt in nano."
        echo "  Add one URL per line. Save with Ctrl+O, exit with Ctrl+X."
        echo ""
        sleep 1
        nano "$BATCHFILE"

        URL_COUNT=$(grep -cE '^[^#[:space:]]' "$BATCHFILE" 2>/dev/null || echo 0)

        if [[ "$URL_COUNT" -eq 0 ]]; then
            echo "[!] batchfile.txt is empty. Nothing to download."
            exit 0
        fi

        echo ""
        echo "  Found $URL_COUNT URL(s) in batchfile.txt."
        printf "  Proceed with download? [y/N]: "
        read -r CONFIRM

        if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
            start_server
            trap stop_server EXIT
            run_ytdlp "$CONFIG_SOLO" --batch-file "$BATCHFILE"
        else
            echo "[*] Cancelled."
        fi
        ;;

    4)
        printf "  URL: "
        read -r URL
        [[ -z "$URL" ]] && echo "[!] No URL entered. Exiting." && exit 1
        start_server
        trap stop_server EXIT
        run_ytdlp "$CONFIG_AUDIO" "$URL"
        ;;

    *)
        echo "[!] Invalid selection. Exiting."
        exit 1
        ;;

esac

echo "[*] Done."
