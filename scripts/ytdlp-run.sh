#!/data/data/com.termux/files/usr/bin/bash
# ytdlp-run.sh — yt-dlp-termux main launcher
# Manages bgutil HTTP server lifecycle and dispatches yt-dlp downloads.
#
# Items implemented:
#   1.2  SERVER_PID initialized — prevents unbound variable crash under set -u
#   1.3  BGUTIL_CMD as bash array — no word-splitting
#   1.7  start_server() — health check with early-death detection
#   1.8  run_ytdlp() — propagates yt-dlp exit codes
#   3.1  XDG-compliant config paths with YTDLPTERMUX_CONFIG env override
#   3.4  Process group kill via setsid; trap covers EXIT INT TERM HUP
#   3.5  Layered config: base conf + optional user.conf overlay
#   5.2  Retry wrapper — max 3 attempts on network errors
#   5.3  Disk space pre-flight check — default 2 GB threshold
#   2.2  Option B: audio restored as option 3; batch renumbered to 4

set -euo pipefail

# ─── Source shared library ───────────────────────────────────────────────────
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_COMMON="${_SCRIPT_DIR}/../lib/common.sh"
[[ -f "$_COMMON" ]] || _COMMON="${XDG_CONFIG_HOME:-$HOME/.config}/yt-dlp-termux/lib/common.sh"
if [[ -f "$_COMMON" ]]; then
    source "$_COMMON"
else
    log()   { echo "[*] $*"; }
    ok()    { echo "[✓] $*"; }
    warn()  { echo "[!] $*" >&2; }
    error() { echo "[✗] $*" >&2; }
    die()   { error "$*"; exit 1; }
    jlog()  { log  "$*"; }
    jok()   { ok   "$*"; }
    jwarn() { warn "$*"; }
    jerr()  { error "$*"; }
    log_json() { :; }
fi

# ─── XDG Paths (item 3.1) ────────────────────────────────────────────────────
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/yt-dlp-termux"
CONFIG_SOLO="${YTDLPTERMUX_CONFIG:-${CONFIG_DIR}/config/termux-solo.conf}"
CONFIG_PLAYLIST="${CONFIG_DIR}/config/termux-playlist.conf"
CONFIG_AUDIO="${CONFIG_DIR}/config/termux-audio.conf"
CONFIG_USER="${CONFIG_DIR}/config/user.conf"
BATCHFILE="${CONFIG_DIR}/batchfile.txt"

[[ -f "$CONFIG_SOLO" ]] || die "Config not found: ${CONFIG_SOLO}\n    Run install.sh or: export YTDLPTERMUX_CONFIG=/path/to/conf"

# ─── Server state (item 1.2: initialized to prevent unbound variable) ────────
SERVER_PID=
PORT=4416

# ─── bgutil command as array (item 1.3: no word-splitting) ───────────────────
BGUTIL_CMD=(
    proot-distro login alpine --
    deno run -A
    /root/bgutil-ytdlp-pot-provider/server/build/main.js
)

# ─── Disk space pre-flight (item 5.3) ────────────────────────────────────────
MIN_FREE_MB="${YTDLPT_MIN_FREE_MB:-2048}"

check_disk_space() {
    local avail_kb avail_mb target
    target="${HOME}/storage/shared"
    [[ -d "$target" ]] || target="$HOME"
    avail_kb=$(df "$target" 2>/dev/null | awk 'NR==2{print $4}')
    [[ -z "$avail_kb" ]] && { jwarn "Cannot read disk space — skipping check."; return 0; }
    avail_mb=$(( avail_kb / 1024 ))
    if (( avail_mb < MIN_FREE_MB )); then
        jerr "Low disk space: ${avail_mb} MB free, ${MIN_FREE_MB} MB required."
        jerr "Lower threshold with: export YTDLPT_MIN_FREE_MB=512"
        return 1
    fi
    jlog "Disk OK: ${avail_mb} MB free."
}

# ─── Server lifecycle (items 1.7, 3.4) ───────────────────────────────────────
start_server() {
    jlog "Acquiring wake lock..."
    termux-wake-lock

    jlog "Starting bgutil HTTP server (port ${PORT})..."

    # item 3.4: setsid creates new process group for clean tree kill
    set -m
    setsid "${BGUTIL_CMD[@]}" &
    SERVER_PID=$!
    set +m

    log_json "INFO" "bgutil server starting" "{\"pid\":${SERVER_PID}}"

    local attempts=0
    local http_code=""
    while (( attempts < 30 )); do
        # item 1.7: detect process death before polling HTTP
        if ! kill -0 "$SERVER_PID" 2>/dev/null; then
            jerr "Server process died at startup (PID ${SERVER_PID})."
            jerr "Verify Alpine proot: proot-distro login alpine -- deno --version"
            log_json "ERROR" "bgutil server died at startup" "{\"pid\":${SERVER_PID}}"
            return 1
        fi

        http_code=$(curl -s -o /dev/null -w "%{http_code}" \
            "http://127.0.0.1:${PORT}" 2>/dev/null || true)

        # 200 or 404 both confirm server is alive and accepting connections
        if [[ "$http_code" == "200" || "$http_code" == "404" ]]; then
            jok "bgutil server ready (${attempts}s)."
            log_json "OK" "bgutil server ready" "{\"pid\":${SERVER_PID},\"elapsed_s\":${attempts}}"
            return 0
        fi

        sleep 1
        (( attempts++ ))
    done

    jerr "bgutil server health check failed after 30s (last HTTP: ${http_code:-none})."
    log_json "ERROR" "bgutil server health check timeout" "{\"pid\":${SERVER_PID},\"http_code\":\"${http_code}\"}"
    return 1
}

stop_server() {
    # item 3.4: kill entire process group, not just proot parent
    if [[ -n "${SERVER_PID:-}" ]]; then
        jlog "Shutting down bgutil server (PGID ${SERVER_PID})..."
        kill -- -"${SERVER_PID}" 2>/dev/null || true
        wait "${SERVER_PID}" 2>/dev/null || true
        log_json "INFO" "bgutil server stopped" "{\"pid\":${SERVER_PID}}"
    fi
    termux-wake-unlock 2>/dev/null || true
    jlog "Wake lock released."
}

# item 3.4: trap all termination signals, not only EXIT
trap 'stop_server' EXIT INT TERM HUP

# ─── yt-dlp runner (items 1.8, 3.5, 5.2) ────────────────────────────────────
MAX_RETRIES="${YTDLPT_MAX_RETRIES:-3}"
RETRY_SLEEP="${YTDLPT_RETRY_SLEEP:-5}"

build_config_args() {
    # item 3.5: layered config — base + optional user.conf overlay
    local base="$1"
    local -a args=(--config-location "$base")
    if [[ -f "$CONFIG_USER" ]]; then
        args+=(--config-location "$CONFIG_USER")
        jlog "User override config active: user.conf"
    fi
    printf '%s\n' "${args[@]}"
}

run_ytdlp() {
    local config="$1"; shift
    local -a config_args
    mapfile -t config_args < <(build_config_args "$config")

    local attempt=1
    local exit_code=0

    while (( attempt <= MAX_RETRIES )); do
        jlog "yt-dlp — attempt ${attempt}/${MAX_RETRIES} ($(basename "$config"))"
        log_json "INFO" "yt-dlp attempt" "{\"attempt\":${attempt},\"config\":\"$(basename "$config")\"}"

        # item 1.8: capture exit code explicitly
        yt-dlp "${config_args[@]}" "$@" && {
            jok "Download complete."
            log_json "OK" "yt-dlp completed" "{\"attempt\":${attempt}}"
            return 0
        }
        exit_code=$?

        # item 5.2: exit codes 2-8 are fatal (config/format errors) — do not retry
        if (( exit_code >= 2 && exit_code <= 8 )); then
            jerr "yt-dlp fatal error (code ${exit_code}) — not retrying."
            log_json "ERROR" "yt-dlp fatal" "{\"exit_code\":${exit_code}}"
            return $exit_code
        fi

        if (( attempt < MAX_RETRIES )); then
            jwarn "yt-dlp failed (code ${exit_code}) — retry in ${RETRY_SLEEP}s..."
            log_json "WARN" "yt-dlp retry" "{\"exit_code\":${exit_code},\"attempt\":${attempt}}"
            sleep "$RETRY_SLEEP"
        fi
        (( attempt++ ))
    done

    jerr "yt-dlp failed after ${MAX_RETRIES} attempts."
    log_json "ERROR" "yt-dlp retries exhausted" "{\"max_retries\":${MAX_RETRIES}}"
    return 1
}

# ─── Update subcommand (item 5.5) ────────────────────────────────────────────
# yt-termux update
# Updates yt-dlp + Python plugins in Termux, then pulls latest bgutil server
# inside Alpine — replaces the four-step manual update sequence in the README.
do_update() {
    jlog "=== yt-dlp-termux update ==="

    jlog "Step 1/3: Updating yt-dlp and Python plugins (Termux)..."
    pip install -U --break-system-packages \
        yt-dlp \
        streamlink \
        "https://github.com/bradenhilton/yt-dlp-FixupMtime/archive/master.zip" \
        && jok "yt-dlp and plugins updated." \
        || { jerr "pip update failed."; return 1; }

    jlog "Step 2/3: Updating bgutil server inside Alpine..."
    proot-distro login alpine -- bash -c "
        set -e
        cd /root/bgutil-ytdlp-pot-provider
        git pull --quiet
        cd server
        npm install --ignore-scripts --quiet
        echo '[✓] bgutil server updated.'
    " && jok "bgutil server updated." \
      || { jerr "bgutil update failed — check Alpine proot."; return 1; }

    jlog "Step 3/3: Verifying bgutil build artifacts..."
    proot-distro login alpine -- test -f \
        /root/bgutil-ytdlp-pot-provider/server/build/main.js \
        && jok "build/main.js present — all good." \
        || { jerr "build/main.js missing after update."; return 1; }

    jlog "Update complete."
    log_json "OK" "yt-dlp-termux update completed"
}

# ─── Direct invocation — bypass menu when argument passed ────────────────────
if [[ $# -gt 0 ]]; then
    case "$1" in
        update|--update|-u)
            do_update
            exit $?
            ;;
        help|--help|-h)
            echo ""
            echo "Usage: yt-termux [URL]"
            echo "       yt-termux update"
            echo ""
            echo "  <URL>     Download directly, bypasses menu"
            echo "  update    Update yt-dlp, plugins, and bgutil server"
            echo "  help      Show this message"
            echo ""
            exit 0
            ;;
        *)
            # Treat as URL
            check_disk_space || exit 1
            start_server     || exit 1
            run_ytdlp "$CONFIG_SOLO" "$@"
            exit $?
            ;;
    esac
fi

# ─── Interactive menu ─────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════╗"
echo "║       yt-dlp-termux  launcher        ║"
echo "╠══════════════════════════════════════╣"
echo "║  1  Solo URL       (video)           ║"
echo "║  2  Playlist URL                     ║"
echo "║  3  Audio only URL                   ║"
echo "║  4  Batch          (batchfile.txt)   ║"
echo "║  q  Quit                             ║"
echo "╚══════════════════════════════════════╝"
echo ""
read -rp "Choice: " CHOICE

case "$CHOICE" in

    1)
        read -rp "URL: " URL
        [[ -z "$URL" ]] && die "No URL entered."
        check_disk_space || exit 1
        start_server     || exit 1
        run_ytdlp "$CONFIG_SOLO" "$URL"
        ;;

    2)
        read -rp "Playlist URL: " URL
        [[ -z "$URL" ]] && die "No URL entered."
        check_disk_space || exit 1
        start_server     || exit 1
        [[ -f "$CONFIG_PLAYLIST" ]] || {
            jwarn "termux-playlist.conf missing — falling back to termux-solo.conf"
            CONFIG_PLAYLIST="$CONFIG_SOLO"
        }
        run_ytdlp "$CONFIG_PLAYLIST" "$URL"
        ;;

    3)
        # item 2.2 Option B: audio option restored
        read -rp "Audio URL: " URL
        [[ -z "$URL" ]] && die "No URL entered."
        check_disk_space || exit 1
        start_server     || exit 1
        [[ -f "$CONFIG_AUDIO" ]] || {
            jwarn "termux-audio.conf missing — falling back to termux-solo.conf"
            CONFIG_AUDIO="$CONFIG_SOLO"
        }
        run_ytdlp "$CONFIG_AUDIO" "$URL"
        ;;

    4)
        # item 2.2 Option B: batch renumbered from 3 to 4
        [[ -f "$BATCHFILE" ]] || die "Batch file not found: ${BATCHFILE}\n    Create it at that path with one URL per line."
        local_count=$(grep -c '' "$BATCHFILE" 2>/dev/null || echo "?")
        echo ""
        echo "  File  : ${BATCHFILE}"
        echo "  Lines : ${local_count}"
        echo ""
        read -rp "Proceed? [y/N]: " CONFIRM
        [[ "$CONFIRM" =~ ^[Yy]$ ]] || { log "Cancelled."; exit 0; }
        check_disk_space || exit 1
        start_server     || exit 1
        run_ytdlp "$CONFIG_SOLO" --batch-file "$BATCHFILE"
        ;;

    q|Q)
        log "Bye."
        exit 0
        ;;

    *)
        die "Unknown choice: '${CHOICE}'"
        ;;
esac
