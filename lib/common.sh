#!/data/data/com.termux/files/usr/bin/bash
# lib/common.sh — shared logging and utility functions
# Sourced by: install.sh, ytdlp-run.sh, bgutil-autostart.sh, uninstall.sh, test.sh
# Item 6.1: eliminates log()/error() duplication across all scripts
# Item 5.4: structured JSON logging to XDG state directory

# ─── XDG Base Directories ────────────────────────────────────────────────────
export YTDLPT_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/yt-dlp-termux"
export YTDLPT_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/yt-dlp-termux"
export YTDLPT_LOG_FILE="${YTDLPT_STATE_DIR}/run.log"

# ─── Console Logging ─────────────────────────────────────────────────────────
log()   { echo -e "\e[34m[*]\e[0m $*"; }
ok()    { echo -e "\e[32m[✓]\e[0m $*"; }
warn()  { echo -e "\e[33m[!]\e[0m $*" >&2; }
error() { echo -e "\e[31m[✗]\e[0m $*" >&2; }
die()   { error "$*"; exit 1; }

# ─── Structured JSON Logging (item 5.4) ──────────────────────────────────────
# Writes newline-delimited JSON to ~/.local/state/yt-dlp-termux/run.log
# Query with: jq 'select(.level=="ERROR")' ~/.local/state/yt-dlp-termux/run.log
log_json() {
    local level="$1"
    local message="$2"
    local extra="${3:-}"

    mkdir -p "$YTDLPT_STATE_DIR"

    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    local entry
    if [[ -n "$extra" ]]; then
        entry="{\"ts\":\"${ts}\",\"level\":\"${level}\",\"msg\":$(printf '%s' "$message" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),\"extra\":${extra}}"
    else
        entry="{\"ts\":\"${ts}\",\"level\":\"${level}\",\"msg\":$(printf '%s' "$message" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}"
    fi

    echo "$entry" >> "$YTDLPT_LOG_FILE"
}

jlog()  { log   "$*"; log_json "INFO"  "$*"; }
jok()   { ok    "$*"; log_json "OK"    "$*"; }
jwarn() { warn  "$*"; log_json "WARN"  "$*"; }
jerr()  { error "$*"; log_json "ERROR" "$*"; }
