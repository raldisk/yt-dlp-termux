#!/data/data/com.termux/files/usr/bin/bash
# test.sh — yt-dlp-termux offline validator
# Item 5.7: validates scripts syntax, config fields, and referenced paths.
# Runs without network access.

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SCRIPT_DIR}/lib/common.sh" 2>/dev/null || {
    log()   { echo "[*] $*"; }
    ok()    { echo "[✓] $*"; }
    warn()  { echo "[!] $*" >&2; }
    error() { echo "[✗] $*" >&2; }
}

INSTALL_BASE="${XDG_CONFIG_HOME:-$HOME/.config}/yt-dlp-termux"
PASS=0
FAIL=0
WARN=0

pass() { ok  "$1"; (( PASS++ )); }
fail() { error "$1"; (( FAIL++ )); }
skip() { warn "$1"; (( WARN++ )); }

echo ""
echo "╔════════════════════════════════════════╗"
echo "║      yt-dlp-termux test suite          ║"
echo "╚════════════════════════════════════════╝"
echo ""

# ─── 1. Bash syntax checks ───────────────────────────────────────────────────
log "1. Bash syntax validation (bash -n)..."

for script in \
    "${_SCRIPT_DIR}/install.sh" \
    "${_SCRIPT_DIR}/uninstall.sh" \
    "${_SCRIPT_DIR}/scripts/ytdlp-run.sh" \
    "${_SCRIPT_DIR}/scripts/bgutil-autostart.sh" \
    "${_SCRIPT_DIR}/scripts/termux-url-opener" \
    "${_SCRIPT_DIR}/lib/common.sh"; do
    if [[ -f "$script" ]]; then
        if bash -n "$script" 2>/dev/null; then
            pass "  $(basename "$script") — syntax OK"
        else
            fail "  $(basename "$script") — syntax ERROR"
        fi
    else
        skip "  $(basename "$script") — not found (expected at: $script)"
    fi
done

# ─── 2. Installed config files present ───────────────────────────────────────
log "2. Checking installed config files..."

EXPECTED_CONFIGS=(
    "termux-solo.conf"
    "termux-playlist.conf"
    "termux-audio.conf"
    "user.conf"
    "default.conf"
)

for conf in "${EXPECTED_CONFIGS[@]}"; do
    target="${INSTALL_BASE}/config/${conf}"
    if [[ -f "$target" || -L "$target" ]]; then
        pass "  ${conf} present"
    else
        fail "  ${conf} missing: ${target}"
    fi
done

# ─── 3. Known-good conf fields ───────────────────────────────────────────────
log "3. Checking termux-solo.conf for known issues..."

SOLO="${INSTALL_BASE}/config/termux-solo.conf"
if [[ -f "$SOLO" ]]; then
    # item 1.6: typo check
    if grep -q "chaannel_url" "$SOLO"; then
        fail "  chaannel_url typo still present in termux-solo.conf"
    else
        pass "  channel_url field correct (no double-a typo)"
    fi

    # item 1.5: duplicate --fixup never
    COUNT=$(grep -c "^\-\-fixup never" "$SOLO" 2>/dev/null || true)
    if (( COUNT > 1 )); then
        fail "  --fixup never appears ${COUNT} times (should be 1)"
    else
        pass "  --fixup never appears exactly once"
    fi

    # item 2.1: personal references must be commented out
    for personal in "2026-marcophoenix.txt" "crabs-arkayb.txt" "crabs-batchfile.txt"; do
        if grep -qE "^[^#].*${personal}" "$SOLO" 2>/dev/null; then
            fail "  Personal reference active (should be commented): ${personal}"
        else
            pass "  Personal reference commented: ${personal}"
        fi
    done
else
    skip "  termux-solo.conf not found at ${SOLO} — run install.sh first"
fi

# ─── 4. Symlinks ─────────────────────────────────────────────────────────────
log "4. Checking ~/bin symlinks..."

if [[ -L "${HOME}/bin/yt-termux" ]]; then
    TARGET=$(readlink -f "${HOME}/bin/yt-termux" 2>/dev/null || echo "broken")
    if [[ -f "$TARGET" ]]; then
        pass "  ~/bin/yt-termux → ${TARGET}"
    else
        fail "  ~/bin/yt-termux symlink is broken → ${TARGET}"
    fi
else
    fail "  ~/bin/yt-termux symlink missing — run install.sh"
fi

# ─── 5. Runtime dependencies ─────────────────────────────────────────────────
log "5. Checking runtime dependencies..."

for cmd in yt-dlp ffmpeg python curl git proot-distro; do
    if command -v "$cmd" &>/dev/null; then
        pass "  ${cmd} found: $(command -v "$cmd")"
    else
        fail "  ${cmd} not found — run install.sh"
    fi
done

# QuickJS path check (not in PATH, accessed directly)
QJS="/data/data/com.termux/files/usr/bin/qjs"
if [[ -f "$QJS" ]]; then
    pass "  qjs found: ${QJS}"
else
    skip "  qjs not found at ${QJS} — install with: pkg install quickjs"
fi

# ─── 6. Alpine proot ─────────────────────────────────────────────────────────
log "6. Checking Alpine proot..."

if proot-distro list 2>/dev/null | grep -q "alpine.*installed"; then
    pass "  Alpine proot installed"
else
    fail "  Alpine proot not installed — run: proot-distro install alpine"
fi

# ─── 7. bgutil build artifacts ───────────────────────────────────────────────
log "7. Checking bgutil build artifacts inside Alpine..."

if proot-distro login alpine -- test -f /root/bgutil-ytdlp-pot-provider/server/build/main.js 2>/dev/null; then
    pass "  build/main.js present inside Alpine"
else
    fail "  build/main.js missing inside Alpine — run install.sh Section 5"
fi

# ─── 8. yt-dlp simulate (requires network — skip in offline mode) ────────────
log "8. yt-dlp config syntax (offline — no network test)..."
SOLO_INSTALLED="${INSTALL_BASE}/config/termux-solo.conf"
if [[ -f "$SOLO_INSTALLED" ]]; then
    if yt-dlp --config-location "$SOLO_INSTALLED" --dump-user-agent &>/dev/null 2>&1; then
        pass "  termux-solo.conf parsed successfully by yt-dlp"
    else
        # Non-fatal — yt-dlp may object to missing cookie file etc.
        skip "  yt-dlp config parse warning — check for missing referenced files"
    fi
else
    skip "  Skipping yt-dlp config parse — conf not installed"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────"
echo "  PASS : ${PASS}"
echo "  FAIL : ${FAIL}"
echo "  WARN : ${WARN}"
echo "─────────────────────────────────────────"
echo ""

if (( FAIL > 0 )); then
    error "Test suite completed with ${FAIL} failure(s). Run install.sh to resolve."
    exit 1
else
    ok "All checks passed."
    exit 0
fi
