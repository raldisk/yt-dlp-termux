#!/data/data/com.termux/files/usr/bin/bash
# install.sh — full idempotent setup for yt-dlp on Termux
#
# Covers the entire install sequence from the README:
#   Section 2  — Termux initial setup (pkg update/upgrade)
#   Section 3  — Storage access grant
#   Section 4  — Core packages
#   Section 5  — JS runtimes (Deno)
#   Section 6  — Python packages (yt-dlp, streamlink, FixupMtime)
#   Section 7  — Alpine Linux via proot-distro
#   Section 8  — bgutil HTTP server build inside Alpine
#   Section 10 — Config and script placement
#   Section 11 — Script permissions
#
# Idempotent: every step checks whether it has already been completed
# before running. Re-running on a partially-configured system is safe.
#
# Usage:
#   chmod +x install.sh && ./install.sh

set -euo pipefail

GITHUB_DIR="$HOME/storage/shared/Github"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================
# HELPERS
# ============================================
step() { echo ""; echo "────────────────────────────────────────"; echo "[STEP] $1"; echo "────────────────────────────────────────"; }
ok()   { echo "[OK]  $1"; }
skip() { echo "[--]  $1 — already done, skipping."; }
warn() { echo "[!!]  $1"; }

command_exists() { command -v "$1" &>/dev/null; }

# ============================================
# STEP 1 — pkg update and upgrade
# ============================================
step "1/9 — Termux package update and upgrade"
echo "    Updating package index and upgrading installed packages."
echo "    If prompted about openssl.cnf, press N to keep your current version."
echo ""
pkg update -y && pkg upgrade -y
ok "Package index updated."

# ============================================
# STEP 2 — Storage access
# ============================================
step "2/9 — Storage access"
if [[ -d "$HOME/storage/shared" ]]; then
    skip "~/storage/shared already exists"
else
    echo "    Requesting storage permission. Accept the Android dialog."
    termux-setup-storage
    ok "Storage access granted."
fi

# ============================================
# STEP 3 — Core packages
# ============================================
step "3/9 — Core packages"
PACKAGES=(git python python-pip nodejs quickjs ffmpeg proot-distro libxml2 libxslt)
MISSING=()

for pkg in "${PACKAGES[@]}"; do
    if dpkg -s "$pkg" &>/dev/null; then
        skip "$pkg"
    else
        MISSING+=("$pkg")
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "    Installing: ${MISSING[*]}"
    pkg install -y "${MISSING[@]}"
    ok "Core packages installed."
else
    ok "All core packages already present."
fi

# Verify ffmpeg
if command_exists ffmpeg; then
    ok "ffmpeg is functional."
else
    warn "ffmpeg not found in PATH after install. Try: pkg install ffmpeg"
fi

# ============================================
# STEP 4 — Deno
# ============================================
step "4/9 — Deno JS runtime"
if command_exists deno; then
    skip "Deno already installed at $(command -v deno)"
else
    echo "    Installing Deno via curl script..."
    curl -fsSL https://deno.land/install.sh | sh

    # Write PATH entries to ~/.bashrc if not already there
    if ! grep -q 'DENO_INSTALL' "$HOME/.bashrc" 2>/dev/null; then
        echo 'export DENO_INSTALL="$HOME/.deno"' >> "$HOME/.bashrc"
        echo 'export PATH="$DENO_INSTALL/bin:$PATH"' >> "$HOME/.bashrc"
    fi

    export DENO_INSTALL="$HOME/.deno"
    export PATH="$DENO_INSTALL/bin:$PATH"
    ok "Deno installed."
fi

# ============================================
# STEP 5 — Python packages
# ============================================
step "5/9 — Python packages (yt-dlp, streamlink, FixupMtime)"

if python3 -m pip show yt-dlp &>/dev/null; then
    skip "yt-dlp already installed (pip)"
    echo "    Upgrading yt-dlp to latest..."
    pip install -U yt-dlp --break-system-packages -q
    ok "yt-dlp upgraded."
else
    echo "    Installing yt-dlp..."
    pip install -U yt-dlp --break-system-packages
    ok "yt-dlp installed."
fi

if python3 -m pip show streamlink &>/dev/null; then
    skip "streamlink already installed"
else
    echo "    Installing streamlink..."
    pip install streamlink --break-system-packages
    ok "streamlink installed."
fi

if python3 -m pip show yt-dlp-FixupMtime &>/dev/null; then
    skip "yt-dlp-FixupMtime already installed"
else
    echo "    Installing yt-dlp-FixupMtime..."
    pip install https://github.com/bradenhilton/yt-dlp-FixupMtime/archive/master.zip --break-system-packages
    ok "yt-dlp-FixupMtime installed."
fi

# ============================================
# STEP 6 — Alpine Linux via proot-distro
# ============================================
step "6/9 — Alpine Linux (proot-distro)"
if proot-distro list 2>/dev/null | grep -q "alpine.*installed"; then
    skip "Alpine already installed"
else
    echo "    Installing Alpine (~3-5 MB download)..."
    proot-distro install alpine
    ok "Alpine installed."
fi

# ============================================
# STEP 7 — bgutil server build inside Alpine
# ============================================
step "7/9 — bgutil HTTP server (inside Alpine proot)"

# Check if bgutil is already built by testing for main.js
BGUTIL_MAIN="/root/bgutil-ytdlp-pot-provider/server/build/main.js"
if proot-distro login alpine -- test -f "$BGUTIL_MAIN" 2>/dev/null; then
    skip "bgutil server already built at $BGUTIL_MAIN"
else
    echo "    Installing Alpine build dependencies..."
    proot-distro login alpine -- apk update
    proot-distro login alpine -- apk add --no-cache \
        deno nodejs npm git pkgconfig \
        pixman-dev cairo-dev pango-dev \
        libjpeg-turbo-dev giflib-dev

    echo "    Cloning bgutil-ytdlp-pot-provider..."
    proot-distro login alpine -- git clone \
        https://github.com/Brainicism/bgutil-ytdlp-pot-provider.git \
        /root/bgutil-ytdlp-pot-provider

    echo "    Running npm install (--ignore-scripts to avoid canvas build failure)..."
    proot-distro login alpine -- sh -c \
        "cd /root/bgutil-ytdlp-pot-provider/server && npm install --ignore-scripts"

    # Verify build output
    if proot-distro login alpine -- test -f "$BGUTIL_MAIN"; then
        ok "bgutil server built successfully."
    else
        warn "bgutil build may have failed — $BGUTIL_MAIN not found."
        warn "See Section 8 and Section 13 of the README for manual steps."
    fi
fi

# ============================================
# STEP 8 — Config and script placement
# ============================================
step "8/9 — Config and script placement"
mkdir -p "$GITHUB_DIR/config"

for conf in termux-solo.conf termux-playlist.conf termux-audio.conf; do
    DEST="$GITHUB_DIR/config/$conf"
    SRC="$REPO_DIR/config/$conf"
    if [[ -f "$DEST" ]]; then
        skip "$conf already at $DEST"
    elif [[ -f "$SRC" ]]; then
        cp "$SRC" "$DEST"
        ok "Copied $conf to $GITHUB_DIR/config/"
    else
        warn "Source $SRC not found — skipping $conf"
    fi
done

# ============================================
# STEP 9 — Script permissions
# ============================================
step "9/9 — Script permissions"
for script in ytdlp-run.sh bgutil-autostart.sh; do
    DEST="$GITHUB_DIR/$script"
    SRC="$REPO_DIR/scripts/$script"
    if [[ -f "$DEST" ]]; then
        chmod +x "$DEST"
        ok "$script — permissions set on existing file"
    elif [[ -f "$SRC" ]]; then
        cp "$SRC" "$DEST"
        chmod +x "$DEST"
        ok "Copied and set permissions: $script"
    else
        warn "Source $SRC not found — skipping $script"
    fi
done

# ============================================
# SUMMARY
# ============================================
echo ""
echo "════════════════════════════════════════════"
echo "  Install complete."
echo "════════════════════════════════════════════"
echo ""
echo "  Next steps:"
echo ""
echo "  1. Place your cookies.txt file in:"
echo "     $GITHUB_DIR/"
echo "     Then update --cookies in config/termux-solo.conf"
echo ""
echo "  2. Test the bgutil server manually:"
echo "     proot-distro login alpine -- \\"
echo "       deno run -A /root/bgutil-ytdlp-pot-provider/server/build/main.js &"
echo "     sleep 10 && curl http://127.0.0.1:4416"
echo "     Expected: 'Cannot GET /'"
echo ""
echo "  3. Run the launcher:"
echo "     $GITHUB_DIR/ytdlp-run.sh"
echo ""
echo "  4. Optionally set up bgutil auto-start:"
echo "     $GITHUB_DIR/bgutil-autostart.sh"
echo ""
echo "  Full setup guide: README.md"
echo ""
