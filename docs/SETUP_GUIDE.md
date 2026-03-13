# yt-dlp on Termux (Android)
### Complete Setup Guide — bgutil POT Provider + Alpine proot + HTTP Server Mode

> **Platform:** Android / Termux (aarch64)
> **Tested on:** Android with Termux from F-Droid
> **yt-dlp config:** `termux-solo.conf`
> **Automation wrapper:** `ytdlp-run.sh`

> **Just want to install?** Run the one-liner from the [main README](../README.md) and let `install.sh` handle everything. This guide exists for users who want to understand each step, troubleshoot a partial setup, or build the environment manually.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
> Jump to: [Credits and Attribution](../README.md#credits-and-attribution) | [License](../README.md#license)
2. [Termux Initial Setup](#2-termux-initial-setup)
3. [Grant Storage Access](#3-grant-storage-access)
4. [Install Core Packages](#4-install-core-packages)
5. [Install JS Runtimes](#5-install-js-runtimes)
6. [Install Python Packages](#6-install-python-packages)
7. [Install Alpine Linux via proot-distro](#7-install-alpine-linux-via-proot-distro)
8. [Build bgutil HTTP Server Inside Alpine](#8-build-bgutil-http-server-inside-alpine)
9. [Verify the HTTP Server](#9-verify-the-http-server)
10. [Configure yt-dlp](#10-configure-yt-dlp)
11. [Automated Setup — install.sh](#11-automated-setup--installsh)
12. [Automation Script — ytdlp-run.sh](#12-automation-script--ytdlp-runsh)
13. [bgutil Auto-Start on Launch — bgutil-autostart.sh](#13-bgutil-auto-start-on-launch--bgutil-autostartsh)
14. [Config Variants](#14-config-variants)
15. [Updating Everything](#15-updating-everything)
16. [Known Errors and Fixes](#16-known-errors-and-fixes)
17. [Runtime Status Summary](#17-runtime-status-summary)
18. [Architecture Overview](#18-architecture-overview)

---

## 1. Prerequisites

- **Termux** installed from [F-Droid](https://f-droid.org/packages/com.termux/) — **not** the Play Store version, which is outdated and unsupported.
- Active internet connection.
- At least **1.5 GB** free storage (Alpine + Node + Deno + dependencies).
- A YouTube cookies file if downloading age-restricted or logged-in content.

---

## 2. Termux Initial Setup

Update the package index and upgrade all packages immediately after a fresh install.

```bash
pkg update && pkg upgrade
```

When prompted about `openssl.cnf`, type `N` and press Enter to keep your currently-installed version. Overwriting it risks breaking TLS for `curl`, `pip`, and `yt-dlp`.

**Change mirror (optional but recommended):**

```bash
termux-change-repo
```

Select a mirror geographically close to you. For the Philippines, any Asia-Pacific mirror works well. After selecting, run `pkg update` to refresh the index.

---

## 3. Grant Storage Access

Termux cannot access shared Android storage by default. Run this once:

```bash
termux-setup-storage
```

Tap **Allow** on the permission dialog. Your shared storage will then be accessible at `~/storage/shared/` — **not** at `/storage/emulated/0/`, which remains permission-denied even after granting access.

```bash
# Correct path
cd ~/storage/shared/Github

# Wrong — will always fail
cd /storage/emulated/0/Github
```

---

## 4. Install Core Packages

```bash
pkg install git python python-pip nodejs quickjs ffmpeg proot-distro libxml2 libxslt
```

**What each package does:**

- `git` — clone repositories
- `python` + `python-pip` — required for yt-dlp and plugins
- `nodejs` — primary JS runtime for yt-dlp's JS extractor features
- `quickjs` — secondary JS runtime (binary is `qjs`, not `quickjs`)
- `ffmpeg` — mux/remux video and audio, embed thumbnails and metadata
- `proot-distro` — run a full Linux distribution (Alpine) inside Termux
- `libxml2` + `libxslt` — required to compile `lxml` for `streamlink`

**Verify FFmpeg installed correctly:**

```bash
ffmpeg
```

A successful install prints FFmpeg's version header and build configuration to the terminal. No arguments are needed — the default output confirms the binary is functional.

> **Note on cookies:** The recommended workflow is to export cookies from a desktop browser on your PC (using a browser extension such as *Get cookies.txt LOCALLY*), then transfer the resulting `cookies.txt` file directly to your yt-dlp working directory in Termux via USB or any file transfer method. This is more reliable than any on-device extraction approach.

---

## 5. Install JS Runtimes

### Node.js
Installed via `pkg install nodejs` above. Verify:

```bash
node --version
```

### QuickJS
Installed via `pkg install quickjs` above. The binary name is `qjs`, not `quickjs`:

```bash
qjs --version
# Prints help text — this is normal. The binary is functional.
```

### Deno
No stable Termux package exists. Install via the official script:

```bash
curl -fsSL https://deno.land/install.sh | sh
```

Add to PATH:

```bash
echo 'export DENO_INSTALL="$HOME/.deno"' >> ~/.bashrc
echo 'export PATH="$DENO_INSTALL/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

> **Note:** The installer prints `sh: not found` after extraction — this is the installer's own post-install self-check failing because PATH is not yet updated in the running shell. The binary is correctly extracted. After `source ~/.bashrc`, `deno --version` will work.

> **Note:** If `deno --version` returns `cannot execute: required file not found` despite the PATH being correct, this indicates a Bionic libc / glibc ABI mismatch on your specific Android kernel. Deno will still work inside Alpine proot where glibc is available.

### Bun
```bash
curl -fsSL https://bun.sh/install | bash
echo 'export BUN_INSTALL="$HOME/.bun"' >> ~/.bashrc
echo 'export PATH="$BUN_INSTALL/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

> **Note:** Bun may fail with `cannot execute: required file not found` on some Android kernels due to the same ABI mismatch. If this occurs, leave it disabled — Node and QuickJS are sufficient.

---

## 6. Install Python Packages

```bash
pip install -U yt-dlp streamlink https://github.com/bradenhilton/yt-dlp-FixupMtime/archive/master.zip --break-system-packages
```

**What `--break-system-packages` means:** Python 3.11+ marks its environment as externally managed, blocking direct `pip install` calls to protect system Python. This flag bypasses that restriction. On Termux specifically, it is the standard and expected way to install packages — the name is dramatic but the flag is harmless in this context.

**What each package does:**

- `yt-dlp` — the downloader
- `streamlink` — live stream extraction (supplements yt-dlp for certain sources)
- `yt-dlp-FixupMtime` — post-processor plugin that fixes file modification timestamps

> **bgutil-ytdlp-pot-provider is intentionally not included here.** The pip plugin is the client-side bridge between yt-dlp and the bgutil HTTP server. Since we run the HTTP server inside Alpine proot and yt-dlp connects to it via `http://127.0.0.1:4416`, the pip plugin is not required for HTTP mode. It is only needed if you switch to script mode (Node.js, no server).

---

## 7. Install Alpine Linux via proot-distro

```bash
proot-distro install alpine
```

Alpine downloads approximately 3–5 MB and expands to ~30 MB on disk at baseline. With all bgutil dependencies installed, the total grows to approximately 300–500 MB.

Enter Alpine:

```bash
proot-distro login alpine
```

Inside Alpine, install all required dependencies:

```bash
apk update && apk add deno nodejs npm git \
  pkgconfig pixman-dev cairo-dev pango-dev \
  libjpeg-turbo-dev giflib-dev
```

> **Why the extra packages?** The bgutil server's `npm install` attempts to compile the `canvas` native module from source. Without `pixman-dev`, `cairo-dev`, and `pango-dev`, this fails with `Package pixman-1 was not found`. Even with them installed, a secondary build error `clang++: error: unsupported argument '4' to option '-flto='` may occur. The fix is `npm install --ignore-scripts` — see [Section 8](#8-build-bgutil-http-server-inside-alpine).

---

## 8. Build bgutil HTTP Server Inside Alpine

Still inside Alpine:

```bash
git clone https://github.com/Brainicism/bgutil-ytdlp-pot-provider.git /root/bgutil-ytdlp-pot-provider
cd /root/bgutil-ytdlp-pot-provider/server
```

**Install Node dependencies — use `--ignore-scripts` to bypass canvas build failures:**

```bash
npm install --ignore-scripts
```

> **Do not use `npm install` without `--ignore-scripts`.** The `canvas` package will attempt a native compilation that fails on Alpine/arm64 with either a missing `pixman-1` error or a `clang++ -flto=4` unsupported argument error. The `canvas` module is not used at runtime by bgutil, making `--ignore-scripts` safe and correct here.

**Check if pre-compiled JS output already exists:**

```bash
ls build/
```

If `generate_once.js`, `main.js`, `session_manager.js`, and `utils.js` are all present, no build step is needed — skip to Step 9.

If the `build/` directory is missing or empty, compile with:

```bash
npx tsc
```

Exit Alpine when done:

```bash
exit
```

---

## 9. Verify the HTTP Server

Start the server from Termux without entering Alpine interactively:

```bash
proot-distro login alpine -- deno run -A /root/bgutil-ytdlp-pot-provider/server/build/main.js
```

On **first run**, Deno downloads and caches its remote module dependencies. This is normal and may take 30–90 seconds depending on connection speed. Watch for output like `Download [84/338]` progressing to completion.

Open a **second Termux session** (swipe right from the left edge → New Session) and confirm the server is responding:

```bash
curl -s http://127.0.0.1:4416
```

Expected response:

```html
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Error</title></head>
<body><pre>Cannot GET /</pre></body>
</html>
```

`Cannot GET /` is the correct response. It is an Express server confirming it is alive — the root path `/` has no handler by design. The actual bgutil endpoint is on a different route that yt-dlp calls internally.

---

## 10. Configure yt-dlp

From v2.0.1, configs are deployed to `~/.config/yt-dlp-termux/config/` by `install.sh`. Invoke yt-dlp with:

```bash
yt-dlp --config-location ~/.config/yt-dlp-termux/config/termux-solo.conf "URL"
```

Or use `yt-termux` directly, which resolves the config path automatically.

**Key settings in `termux-solo.conf` relevant to this setup:**

```bash
# HTTP server mode — ACTIVE
--extractor-args "youtubepot-bgutilhttp:base_url=http://127.0.0.1:4416"

# Script mode — fallback if HTTP server is unavailable
#--extractor-args 'youtubepot-bgutilscript:script_path=/data/data/com.termux/files/home/storage/shared/Github/bgutil-ytdlp-pot-provider/server/build/generate_once.js'

# JS runtimes
--js-runtimes node
--js-runtimes 'quickjs:/data/data/com.termux/files/usr/bin/qjs'
--js-runtimes 'deno:/data/data/com.termux/files/home/.deno/bin/deno'

# Concurrent fragments — reduced from 64 (laptop) to 4 for mobile safety
-N 4
```

**Switching between HTTP mode and script mode:**

To use the bgutil HTTP server (recommended — requires Alpine server running):
```bash
# Active:
--extractor-args "youtubepot-bgutilhttp:base_url=http://127.0.0.1:4416"
# Commented out:
#--extractor-args 'youtubepot-bgutilscript:...'
```

To use script mode (no server needed, Node.js only):
```bash
# Commented out:
#--extractor-args "youtubepot-bgutilhttp:base_url=http://127.0.0.1:4416"
# Active:
--extractor-args 'youtubepot-bgutilscript:script_path=/data/data/com.termux/files/home/storage/shared/Github/bgutil-ytdlp-pot-provider/server/build/generate_once.js'
```

> **Personal settings** such as cookies, download archive, and batch file paths belong in `~/.config/yt-dlp-termux/config/user.conf` — never in `termux-solo.conf`. See [user.conf.template](../config/user.conf.template) for available options.

---

## 11. Automated Setup — install.sh

`install.sh` runs the entire setup sequence from a fresh Termux environment in a single command. From v2.0.1 it is fully self-bootstrapping — when piped through bash via `curl | bash`, it detects the pipe, clones the repo automatically, and re-executes itself from disk so all file paths resolve correctly.

Every step is **idempotent** — it checks whether it has already been completed before running, so re-executing the script on a partially-configured device is safe and will not re-clone or re-install anything already present.

**Usage — one-liner (recommended):**

```bash
curl -L https://raw.githubusercontent.com/raldisk/yt-dlp-termux/v2.0.1/install.sh | bash
```

**Usage — manual (from a cloned repo):**

```bash
bash ~/storage/shared/Github/yt-dlp-termux/install.sh
```

After the script completes, configs are deployed to `~/.config/yt-dlp-termux/`, a `~/bin/yt-termux` symlink is created, and a live smoke test confirms the bgutil server starts and responds on port 4416.

---

## 12. Automation Script — ytdlp-run.sh

`ytdlp-run.sh` manages the full bgutil server lifecycle automatically. When invoked **without arguments**, it presents an interactive menu. When invoked **with a URL**, it runs a direct single-video download. When invoked with `update`, it updates all components in sequence.

**Interactive menu:**

```
╔══════════════════════════════════════╗
║       yt-dlp-termux  launcher        ║
╠══════════════════════════════════════╣
║  1  Solo URL       (video)           ║
║  2  Playlist URL                     ║
║  3  Audio only URL                   ║
║  4  Batch          (batchfile.txt)   ║
║  q  Quit                             ║
╚══════════════════════════════════════╝
```

Option 1 downloads a single video using `termux-solo.conf` with full metadata, thumbnails, and chapters embedded. Option 2 downloads full playlists via `termux-playlist.conf`. Option 3 downloads audio only as m4a via `termux-audio.conf`. Option 4 reads `~/.config/yt-dlp-termux/batchfile.txt`, displays a line count, and asks for confirmation before proceeding.

**Direct URL mode:**

```bash
yt-termux "https://www.youtube.com/watch?v=VIDEOID"
```

**Update subcommand:**

```bash
yt-termux update
```

**Help:**

```bash
yt-termux help
```

In all download modes the script follows the same lifecycle: disk space check → acquire wake lock → start bgutil server → health check port 4416 → run yt-dlp with retry → kill entire process group → release wake lock. A trap covering `EXIT INT TERM HUP` ensures the server is always shut down cleanly even if yt-dlp fails mid-download or the session is interrupted.

> **Important:** `ytdlp-run.sh` requires HTTP mode to be active in the config. Ensure `--extractor-args "youtubepot-bgutilhttp:..."` is uncommented and the `bgutilscript` line is commented out.

---

## 13. bgutil Auto-Start on Launch — bgutil-autostart.sh

By default the bgutil HTTP server must be started manually before each download session. `bgutil-autostart.sh` is a **one-time installer** that eliminates this step by writing a persistent boot hook.

**Run once:**

```bash
bash ~/.config/yt-dlp-termux/scripts/bgutil-autostart.sh
```

**What it installs:**

A `~/.termux/boot/start-bgutil.sh` script is written for users with the **Termux:Boot** app installed, which fires the server on device reboot. Detection uses the presence of the `~/.termux/boot/` directory — the only reliable signal that Termux:Boot is installed and has been opened at least once.

**To verify the server is running after a new session opens:**

```bash
curl http://127.0.0.1:4416
# Expected: Cannot GET /
```

**To undo:** Delete `~/.termux/boot/start-bgutil.sh`.

---

## 14. Config Variants

Three config files are provided under `~/.config/yt-dlp-termux/config/`. Each shares the same POT provider, JS runtime, and error-handling settings but is purpose-built for a specific download mode.

**`termux-solo.conf`** — Single video downloads. H.264 (AVC) preferred for low-CPU mobile playback. Output nested under `%(channel)s [%(channel_id)s]/` with metadata, thumbnails, chapters, and subtitles embedded. Default config for `yt-termux` direct URL mode and menu option 1.

**`termux-playlist.conf`** — Full playlist or channel downloads. Output nested under `%(channel)s [%(channel_id)s]/%(playlist_title)s [%(playlist_id)s]/` with `playlist_index` prefixes for ordered filenames.

**`termux-audio.conf`** — Audio-only downloads. Extracts best m4a audio, saves to `%(channel)s [%(channel_id)s]/Audio/` with thumbnail and metadata embedded.

**`user.conf`** — Personal overrides. Sourced after the base config. Never tracked by git. Place cookies, archive files, and custom output paths here. See [user.conf.template](../config/user.conf.template).

Each config can be invoked manually:

```bash
yt-dlp --config-location ~/.config/yt-dlp-termux/config/termux-playlist.conf "PLAYLIST_URL"
```

Or override the default at runtime:

```bash
YTDLPTERMUX_CONFIG=~/.config/yt-dlp-termux/config/termux-audio.conf yt-termux "URL"
```

---

## 15. Updating Everything

From v2.0.1, a single command handles all update steps:

```bash
yt-termux update
```

This runs three stages in sequence: updates yt-dlp and Python plugins via pip, pulls the latest bgutil server inside Alpine and reinstalls Node dependencies, then verifies `build/main.js` is present. Each stage reports pass or fail and exits early on any error.

**Manual steps (if needed):**

```bash
# Termux packages
pkg upgrade

# yt-dlp and Python plugins
pip install -U yt-dlp streamlink https://github.com/bradenhilton/yt-dlp-FixupMtime/archive/master.zip --break-system-packages

# bgutil server inside Alpine
proot-distro login alpine
cd /root/bgutil-ytdlp-pot-provider && git pull
cd server && npm install --ignore-scripts
exit
```

> Keep pip packages and the Alpine server updated together. A mismatch between the client plugin and server protocol can cause silent POT token failures.

---

## 16. Known Errors and Fixes

### `bash: cd: /storage/emulated/0/Github: Permission denied`
**Cause:** Direct access to `/storage/emulated/0/` is blocked by Android's sandbox.
**Fix:**
```bash
termux-setup-storage
cd ~/storage/shared/Github
```

---

### `The program pip is not installed`
**Fix:**
```bash
pkg install python-pip
```

---

### `pip install` fails with `externally-managed-environment`
**Fix:** Always append `--break-system-packages` to pip commands on Termux.

---

### `ERROR: Failed to build 'lxml'`
**Fix:**
```bash
pkg install libxml2 libxslt
```
Then retry the pip install command.

---

### `npm install` fails — `Package pixman-1 was not found`
**Context:** Inside Alpine, building the bgutil server.
**Fix:**
```bash
apk add pkgconfig pixman-dev cairo-dev pango-dev libjpeg-turbo-dev giflib-dev
```
Then retry `npm install`.

---

### `npm install` fails — `clang++: error: unsupported argument '4' to option '-flto='`
**Context:** Inside Alpine — `canvas` native module build failure.
**Fix:**
```bash
npm install --ignore-scripts
```

---

### `npm run build` fails — `Missing script: "build"`
**Cause:** The pre-compiled `build/` directory already exists in the repository.
**Fix:**
```bash
ls build/
```
If `generate_once.js` and `main.js` are present, no build step is needed.

---

### `deno: cannot execute: required file not found`
**Cause:** Deno targets glibc; Android uses Bionic libc.
**Fix:** Deno works correctly inside Alpine proot. The HTTP server architecture is the correct solution — Deno runs inside Alpine and exposes port 4416 to the Termux host.

---

### `sh: not found` during Deno install script
**Cause:** The install script self-verifies before PATH is updated.
**Fix:** False alarm — binary is correctly installed. Run `source ~/.bashrc` and `deno --version` will work.

---

### `curl http://127.0.0.1:4416` returns `Cannot GET /`
**This is not an error.** It confirms the Express server is live. The root path has no handler by design — yt-dlp calls the correct internal endpoint automatically.

---

### bgutil server killed mid-download by Android
**Cause:** Android battery optimization terminates background processes.
**Fix:** Always use `yt-termux` — it calls `termux-wake-lock` at startup and `termux-wake-unlock` on exit.

---

## 17. Runtime Status Summary

| Runtime | Status | Binary Path |
|---------|--------|-------------|
| Node.js | ✅ Working | in PATH via `pkg install nodejs` |
| QuickJS | ✅ Working | `/data/data/com.termux/files/usr/bin/qjs` |
| Deno (native Termux) | ⚠️ ABI mismatch on some devices | `~/.deno/bin/deno` |
| Deno (inside Alpine) | ✅ Working | Used by bgutil HTTP server |
| Bun | ❌ ABI mismatch | `~/.bun/bin/bun` |

---

## 18. Architecture Overview

```
┌─────────────────────────────────────────────┐
│               Termux (main shell)           │
│                                             │
│  yt-termux (~/bin symlink)                  │
│    └── ytdlp-run.sh                         │
│          ├── check_disk_space()             │
│          ├── termux-wake-lock               │
│          ├── start_server()                 │
│          │     ├── setsid BGUTIL_CMD[@] &   │
│          │     ├── kill -0 $SERVER_PID      │
│          │     └── curl :4416 health check  │
│          ├── run_ytdlp()                    │
│          │     ├── base.conf + user.conf    │
│          │     └── retry (max 3 attempts)   │
│          └── stop_server()                  │
│                └── kill -- -$PGID           │
└─────────────────────────────────────────────┘
                        │ localhost :4416
┌─────────────────────────────────────────────┐
│         Alpine proot (background)           │
│                                             │
│  deno run -A .../server/build/main.js       │
│    └── Express HTTP server :4416            │
│          └── bgutil challenge solver        │
│                └── PO token → response      │
└─────────────────────────────────────────────┘
```

The two environments communicate exclusively through `http://127.0.0.1:4416`. Localhost ports are shared between proot containers and the Termux host, making this architecture possible without any additional networking configuration.

---

## Quick Reference — Full Manual Install Sequence

```bash
# 1. Termux setup
pkg update && pkg upgrade
termux-setup-storage

# 2. Core packages
pkg install git python python-pip nodejs quickjs ffmpeg proot-distro libxml2 libxslt

# 3. Deno (native Termux)
curl -fsSL https://deno.land/install.sh | sh
echo 'export DENO_INSTALL="$HOME/.deno"' >> ~/.bashrc
echo 'export PATH="$DENO_INSTALL/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# 4. Python packages
pip install -U yt-dlp streamlink https://github.com/bradenhilton/yt-dlp-FixupMtime/archive/master.zip --break-system-packages

# 5. Alpine proot
proot-distro install alpine
proot-distro login alpine

# --- Inside Alpine ---
apk update && apk add deno nodejs npm git pkgconfig pixman-dev cairo-dev pango-dev libjpeg-turbo-dev giflib-dev
git clone https://github.com/Brainicism/bgutil-ytdlp-pot-provider.git /root/bgutil-ytdlp-pot-provider
cd /root/bgutil-ytdlp-pot-provider/server
npm install --ignore-scripts
ls build/   # verify generate_once.js and main.js exist
exit
# --- Back in Termux ---

# 6. Test the server
proot-distro login alpine -- deno run -A /root/bgutil-ytdlp-pot-provider/server/build/main.js &
sleep 10
curl -s http://127.0.0.1:4416   # should return "Cannot GET /"

# 7. Install via install.sh
curl -L https://raw.githubusercontent.com/raldisk/yt-dlp-termux/v2.0.1/install.sh | bash

# 8. Test download
yt-termux "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```
