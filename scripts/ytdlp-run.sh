#!/data/data/com.termux/files/usr/bin/bash
# ytdlp-run.sh — auto-manages bgutil HTTP server via Alpine proot

# Acquire wakelock to prevent Android from killing background processes
termux-wake-lock
echo "[*] Wake lock acquired."

BGUTIL_SERVER="proot-distro login alpine -- deno run -A /root/bgutil-ytdlp-pot-provider/server/build/main.js"
PORT=4416

echo "[*] Starting bgutil server..."
$BGUTIL_SERVER &
SERVER_PID=$!

# Wait until the server is accepting connections (max 30s)
for i in $(seq 1 30); do
    if curl -s "http://127.0.0.1:$PORT" > /dev/null 2>&1; then
        echo "[*] Server ready."
        break
    fi
    sleep 1
done

echo "[*] Running yt-dlp..."
yt-dlp --config-location ~/storage/shared/Github/termux-solo.conf "$@"

echo "[*] Shutting down bgutil server..."
kill $SERVER_PID 2>/dev/null
wait $SERVER_PID 2>/dev/null

# Release wakelock now that everything is done
termux-wake-unlock
echo "[*] Wake lock released."
echo "[*] Done."
