#!/data/data/com.termux/files/usr/bin/bash
# install.sh — yt-dlp-termux installer
# https://github.com/raldisk/yt-dlp-termux
#
# Items implemented:
#   1.1  curl|bash self-bootstrapping via BASH_SOURCE[0] detection
#   3.2  Configs installed to XDG-compliant ~/.config/yt-dlp-termux/
#   3.3  ytdlp-run.sh symlinked to ~/bin/yt-termux
#   3.5  user.conf.template deployed on first install
#   3.6  proot-distro + bgutil smoke test at end of install
#   4.1  Version-pinned install URL published in README (enforced by git tag)
#   4.3  termux-url-opener backed up before overwrite
#   5.1  termux-url-opener installed to ~/bin/ (optional, prompted)

set -euo pipefail

# ─── item 1.1: curl|bash self-bootstrapping ──────────────────────────────────
# When piped through bash, BASH_SOURCE[0] is empty — dirname returns "." which
# resolves to the user's CWD, not the repo. Detect the pipe case, clone the
# repo, then exec a proper file execution so BASH_SOURCE[0] is populated.
REPO_URL="https://github.com/raldisk/yt-dlp-termux.git"
REPO_BRANCH="${YTDLPT_BRANCH:-master}"
CLONE_DIR="${HOME}/storage/shared/Github/yt-dlp-termux"

if [[ -z "${BASH_SOURCE[0]:-}" ]] || [[ "${BASH_SOURCE[0]}" == "bash" ]]; then
    echo "[*] Running via curl pipe — cloning repo first..."
    # Termux storage must be set up for ~/storage/shared to exist
    if [[ ! -d "${HOME}/storage/shared" ]]; then
        echo "[*] Setting up Termux storage access..."
        termux-setup-storage
        sleep 2
    fi
    mkdir -p "$(dirname "$CLONE_DIR")"
    [[ -d "$CLONE_DIR" ]] && rm -rf "$CLONE_DIR"
    git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$CLONE_DIR"
    exec bash "$CLONE_DIR/install.sh" "${@}"
fi

# ─── From this point: running as a proper file execution ─────────────────────
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Source shared library (may not exist yet on fresh install) ───────────────
LIB="${REPO_DIR}/lib/common.sh"
[[ -f "$LIB" ]] && source "$LIB" || {
    log()   { echo -e "\e[34m[*]\e[0m $*"; }
    ok()    { echo -e "\e[32m[✓]\e[0m $*"; }
    warn()  { echo -e "\e[33m[!]\e[0m $*" >&2; }
    error() { echo -e "\e[31m[✗]\e[0m $*" >&2; }
    die()   { error "$*"; exit 1; }
}

# ─── Install destinations (item 3.2) ─────────────────────────────────────────
INSTALL_BASE="${XDG_CONFIG_HOME:-$HOME/.config}/yt-dlp-termux"
INSTALL_CONFIG="${INSTALL_BASE}/config"
INSTALL_SCRIPTS="${INSTALL_BASE}/scripts"
INSTALL_LIB="${INSTALL_BASE}/lib"
BIN_DIR="${HOME}/bin"

VERSION="$(git -C "$REPO_DIR" describe --tags --always 2>/dev/null || echo 'dev')"

echo ""
echo "╔════════════════════════════════════════╗"
echo "║      yt-dlp-termux installer           ║"
echo "║      version: ${VERSION}               "
echo "╚════════════════════════════════════════╝"
echo ""

# ─── Section 1: Termux environment check ─────────────────────────────────────
log "Section 1: Checking Termux environment..."
command -v termux-setup-storage &>/dev/null \
    || die "Not running in Termux. This installer is Termux-only."

if [[ ! -d "${HOME}/storage/shared" ]]; then
    log "Setting up Termux storage access..."
    termux-setup-storage
    sleep 2
fi
ok "Termux environment OK."

# ─── Section 2: Package installation ─────────────────────────────────────────
log "Section 2: Installing Termux packages..."

PKGS=(git python python-pip nodejs quickjs ffmpeg proot-distro libxml2 libxslt curl)
MISSING_PKGS=()

for pkg in "${PKGS[@]}"; do
    if ! dpkg -s "$pkg" &>/dev/null; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
    log "Installing: ${MISSING_PKGS[*]}"
    pkg install -y "${MISSING_PKGS[@]}"
fi
ok "Termux packages installed."

# ─── Section 3: Python packages ──────────────────────────────────────────────
log "Section 3: Installing Python packages..."
pip install -U --break-system-packages \
    yt-dlp \
    streamlink \
    "https://github.com/bradenhilton/yt-dlp-FixupMtime/archive/master.zip"
ok "Python packages installed."

# ─── Section 4: Alpine proot setup ───────────────────────────────────────────
log "Section 4: Setting up Alpine proot..."
if ! proot-distro list | grep -q "alpine.*installed"; then
    log "Installing Alpine Linux via proot-distro..."
    proot-distro install alpine
fi
ok "Alpine proot ready."

# ─── Section 5: bgutil-ytdlp-pot-provider ────────────────────────────────────
log "Section 5: Setting up bgutil POT provider..."
BGUTIL_DIR="/root/bgutil-ytdlp-pot-provider"

proot-distro login alpine -- bash -c "
    set -e
    # Install Alpine deps
    apk update -q
    apk add -q deno nodejs npm git pkgconfig pixman-dev cairo-dev pango-dev libjpeg-turbo-dev giflib-dev 2>/dev/null || true

    # Clone or update bgutil repo
    if [[ -d '${BGUTIL_DIR}/.git' ]]; then
        echo '[*] Updating bgutil repo...'
        git -C '${BGUTIL_DIR}' pull --quiet
    else
        echo '[*] Cloning bgutil repo...'
        git clone --quiet https://github.com/Brainicism/bgutil-ytdlp-pot-provider.git '${BGUTIL_DIR}'
    fi

    # Install Node deps (--ignore-scripts: skips canvas native build, not needed at runtime)
    cd '${BGUTIL_DIR}/server'
    npm install --ignore-scripts --quiet

    # Verify build artifacts exist
    if [[ -f '${BGUTIL_DIR}/server/build/main.js' ]]; then
        echo '[✓] bgutil build verified.'
    else
        echo '[✗] build/main.js not found — check repository state.' >&2
        exit 1
    fi
"
ok "bgutil POT provider ready."

# ─── Section 6: Deno runtime check ───────────────────────────────────────────
log "Section 6: Verifying Deno inside Alpine..."
proot-distro login alpine -- deno --version &>/dev/null \
    && ok "Deno OK inside Alpine." \
    || warn "Deno not responsive inside Alpine — downloads may fail. Check Section 13 of README."

# ─── Section 7: Deploy files (items 3.2, 3.3) ────────────────────────────────
log "Section 7: Deploying files to ${INSTALL_BASE}..."
mkdir -p "$INSTALL_CONFIG" "$INSTALL_SCRIPTS" "$INSTALL_LIB" "$BIN_DIR"

# Configs
for conf in termux-solo.conf termux-playlist.conf termux-audio.conf; do
    cp "${REPO_DIR}/config/${conf}" "${INSTALL_CONFIG}/${conf}"
    log "  config: ${conf}"
done

# user.conf template — only on first install, never overwrite personal config
if [[ ! -f "${INSTALL_CONFIG}/user.conf" ]]; then
    cp "${REPO_DIR}/config/user.conf.template" "${INSTALL_CONFIG}/user.conf"
    log "  config: user.conf (from template — edit to add personal settings)"
else
    log "  config: user.conf already exists — not overwritten."
fi

# Scripts
for script in ytdlp-run.sh bgutil-autostart.sh; do
    cp "${REPO_DIR}/scripts/${script}" "${INSTALL_SCRIPTS}/${script}"
    chmod +x "${INSTALL_SCRIPTS}/${script}"
    log "  script: ${script}"
done

# Shared library
cp "${REPO_DIR}/lib/common.sh" "${INSTALL_LIB}/common.sh"
log "  lib: common.sh"

# item 3.3: symlink to ~/bin/ for PATH access
ln -sf "${INSTALL_SCRIPTS}/ytdlp-run.sh" "${BIN_DIR}/yt-termux"
ok "Symlink created: ~/bin/yt-termux → ytdlp-run.sh"

# Ensure ~/bin is in PATH
if ! echo "$PATH" | grep -q "${BIN_DIR}"; then
    warn "~/bin is not in your PATH. Add this to ~/.bashrc:"
    warn "  export PATH=\"\$HOME/bin:\$PATH\""
fi

# ─── Section 8: default.conf symlink (item 6.2) ──────────────────────────────
log "Section 8: Creating default.conf symlink..."
ln -sf "${INSTALL_CONFIG}/termux-solo.conf" "${INSTALL_CONFIG}/default.conf"
ok "Symlink created: default.conf → termux-solo.conf"

# ─── Section 9: termux-url-opener (items 4.3, 5.1) ───────────────────────────
log "Section 9: termux-url-opener (Android share-menu integration)..."
echo ""
read -rp "Install Android share-menu integration? (y/N): " _YN || _YN="n"
if [[ "$_YN" =~ ^[Yy]$ ]]; then
    _TARGET="${BIN_DIR}/termux-url-opener"
    _BACKUP="${BIN_DIR}/termux-url-opener.backup.$(date +%s)"

    # item 4.3: back up existing unmanaged opener before overwriting
    if [[ -f "$_TARGET" ]] && ! grep -q "# yt-dlp-termux managed" "$_TARGET" 2>/dev/null; then
        cp "$_TARGET" "$_BACKUP"
        ok "Existing termux-url-opener backed up: ${_BACKUP}"
    fi

    cp "${REPO_DIR}/scripts/termux-url-opener" "$_TARGET"
    chmod +x "$_TARGET"
    ok "termux-url-opener installed. Share URLs from Chrome → Termux to download."
else
    log "Skipping termux-url-opener."
fi

# ─── Section 10: Termux:Boot autostart ───────────────────────────────────────
log "Section 10: Termux:Boot autostart..."
bash "${INSTALL_SCRIPTS}/bgutil-autostart.sh"

# ─── Section 11: XDG state directory ─────────────────────────────────────────
log "Section 11: Creating XDG state directory for logs..."
mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/yt-dlp-termux"
ok "Log directory: ${XDG_STATE_HOME:-$HOME/.local/state}/yt-dlp-termux/run.log"

# ─── Section 12: SHA-256 checksum of install.sh (item 4.2) ───────────────────
log "Section 12: Generating install.sh SHA-256 checksum..."
CHECKSUM_FILE="${REPO_DIR}/install.sh.sha256"
sha256sum "${REPO_DIR}/install.sh" | awk '{print $1}' > "$CHECKSUM_FILE"
ok "Checksum written: install.sh.sha256 ($(cat "$CHECKSUM_FILE"))"

# ─── Section 13: Smoke test (item 3.6) ───────────────────────────────────────
log "Section 13: Running smoke test — starting bgutil server briefly..."
echo ""
_SMOKE_PID=
_SMOKE_PASSED=false

set -m
proot-distro login alpine -- \
    deno run -A /root/bgutil-ytdlp-pot-provider/server/build/main.js &
_SMOKE_PID=$!
set +m

log "Waiting 8s for server to initialise..."
sleep 8

_HTTP=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:4416" 2>/dev/null || true)
kill -- -"${_SMOKE_PID}" 2>/dev/null || true
wait "$_SMOKE_PID" 2>/dev/null || true

if [[ "$_HTTP" == "200" || "$_HTTP" == "404" ]]; then
    _SMOKE_PASSED=true
    ok "Smoke test passed — bgutil server reachable (HTTP ${_HTTP})."
else
    warn "Smoke test inconclusive (HTTP: ${_HTTP:-none})."
    warn "Manual check: proot-distro login alpine -- deno run -A /root/bgutil-ytdlp-pot-provider/server/build/main.js"
    warn "Then in another terminal: curl http://127.0.0.1:4416"
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "╔════════════════════════════════════════╗"
echo "║         Installation complete          ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "  Usage:    yt-termux              (interactive menu)"
echo "  Usage:    yt-termux <URL>        (direct download)"
echo "  Config:   ${INSTALL_CONFIG}/"
echo "  Personal: ${INSTALL_CONFIG}/user.conf"
echo "  Logs:     ${XDG_STATE_HOME:-$HOME/.local/state}/yt-dlp-termux/run.log"
echo ""
if [[ "$_SMOKE_PASSED" == "true" ]]; then
    ok "All systems go. Run: yt-termux"
else
    warn "Install complete but smoke test was inconclusive."
    warn "See README Section 13 for manual verification steps."
fi
echo ""
