# yt-dlp on Termux (Android)
### Complete Setup Guide — bgutil POT Provider + Alpine proot + HTTP Server Mode

> **Platform:** Android / Termux (aarch64)  
> **Tested on:** Android with Termux from F-Droid  
> **yt-dlp config:** `termux-solo.conf`  
> **Automation wrapper:** `ytdlp-run.sh`

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
> Jump to: [Credits and Attribution](#credits-and-attribution) | [License](#license)
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

Place `termux-solo.conf` in your working directory (e.g. `~/storage/shared/Github/`) and invoke yt-dlp with:

```bash
yt-dlp --config-location ~/storage/shared/Github/termux-solo.conf "URL"
```

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

To use the bgutil HTTP server (recommended, requires Alpine server running):
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

---

## 11. Automated Setup — install.sh

`install.sh` runs the entire setup sequence from a fresh Termux environment in a single command. It covers all nine stages: package update, storage access, core packages, Deno, Python packages, Alpine proot, bgutil server build, config placement, and script permissions.

Every step is **idempotent** — it checks whether it has already been completed before running, so re-executing the script on a partially-configured device is safe and will not re-clone or re-install anything already present.

**Usage:**

```bash
chmod +x ~/storage/shared/Github/yt-dlp-termux/install.sh
~/storage/shared/Github/yt-dlp-termux/install.sh
```

After the script completes, it prints a summary of next steps: placing your cookies file, running the server smoke test, and optionally setting up bgutil auto-start via `bgutil-autostart.sh`.

> **Note:** `install.sh` must be run from within the cloned `yt-dlp-termux/` directory so the relative paths to config files and scripts resolve correctly.

---

## 12. Automation Script — ytdlp-run.sh

`ytdlp-run.sh` manages the full bgutil server lifecycle automatically so you never need to handle two Termux sessions manually. When invoked **without arguments**, it presents an interactive menu. When invoked **with a URL**, it runs a direct single-video download using `termux-solo.conf`.

**Interactive menu:**

```
  yt-dlp Termux Runner
  ─────────────────────────────────────────
  1) Single video   (termux-solo.conf)
  2) Playlist       (termux-playlist.conf)
  3) Batch file     (edit batchfile.txt → run)
  4) Audio only     (termux-audio.conf)
  ─────────────────────────────────────────
  Select [1-4]:
```

Selecting **option 3** opens `batchfile.txt` in `nano`. Add one URL per line, save with `Ctrl+O`, exit with `Ctrl+X`. The script counts non-empty lines and asks for confirmation before starting the server and running the batch.

**Direct URL mode (bypasses menu):**

```bash
chmod +x ~/storage/shared/Github/ytdlp-run.sh
~/storage/shared/Github/ytdlp-run.sh "https://www.youtube.com/watch?v=VIDEOID"
```

In both modes the script follows the same lifecycle: acquire wake lock → start bgutil server → poll port 4416 for up to 30 seconds → run yt-dlp → kill server → release wake lock. A `trap` on `EXIT` ensures the server is always shut down cleanly even if yt-dlp fails mid-download.

> **Important:** `ytdlp-run.sh` requires HTTP mode to be active in the config file being used. Ensure `--extractor-args "youtubepot-bgutilhttp:..."` is uncommented and the `bgutilscript` line is commented out.

---

## 13. bgutil Auto-Start on Launch — bgutil-autostart.sh

By default the bgutil HTTP server must be started manually before each download session. `bgutil-autostart.sh` is a **one-time installer** that eliminates this step by writing two persistent hooks.

**Run once:**

```bash
chmod +x ~/storage/shared/Github/bgutil-autostart.sh
~/storage/shared/Github/bgutil-autostart.sh
```

**What it installs:**

A guard block is appended to `~/.bashrc` that checks whether the server is already responding on `:4416` before attempting to start a new instance — preventing duplicate processes if you open multiple Termux sessions. A `~/.termux/boot/start-bgutil.sh` script is written for users with the **Termux:Boot** app installed, which fires the server on device reboot.

**To verify the server is running after a new session opens:**

```bash
curl http://127.0.0.1:4416
# Expected: Cannot GET /
```

**Logs:** `/tmp/bgutil.log` for session starts, `/tmp/bgutil-boot.log` for boot starts.

**To undo:** Remove the `# bgutil-autostart` block from `~/.bashrc` and delete `~/.termux/boot/start-bgutil.sh`.

---

## 14. Config Variants

Three config files are provided under `config/`. Each is purpose-built for a specific download mode and shares the same POT provider, JS runtime, and error-handling settings as the base config.

**`termux-solo.conf`** — Single video downloads. `--no-playlist` is active. Output is nested under `%(channel)s/%(title)s/`. This is the default config used by `ytdlp-run.sh` in direct URL mode and menu option 1.

**`termux-playlist.conf`** — Full playlist or channel downloads. `--yes-playlist` is active. Output is nested under `%(channel)s/%(playlist)s/` with zero-padded index prefixes (`001.`, `002.`, ...). Uncomment `--playlist-items 1-50` in the file to restrict the range.

**`termux-audio.conf`** — Audio-only downloads. Targets native `opus` streams directly — no transcoding or ffmpeg extraction required. Output is scoped to an `Audio/` subfolder with a simplified filename template that omits resolution and fps fields.

Each config can be invoked manually with `--config-location` or selected automatically through the `ytdlp-run.sh` menu:

```bash
yt-dlp --config-location ~/storage/shared/Github/config/termux-playlist.conf "PLAYLIST_URL"
```

---

## 15. Updating Everything

**Update Termux packages:**
```bash
pkg upgrade
```

**Update yt-dlp and Python plugins:**
```bash
pip install -U yt-dlp streamlink https://github.com/bradenhilton/yt-dlp-FixupMtime/archive/master.zip --break-system-packages
```

**Update the bgutil HTTP server inside Alpine:**
```bash
proot-distro login alpine
cd /root/bgutil-ytdlp-pot-provider
git pull
cd server
npm install --ignore-scripts
exit
```

> Keep the pip packages and the Alpine server updated together. They are separate components but must remain version-compatible — a mismatch between the client plugin and server protocol can cause silent POT token failures.

---

## 16. Known Errors and Fixes

### `bash: cd: /storage/emulated/0/Github: Permission denied`
**Cause:** Direct access to `/storage/emulated/0/` is blocked by Android's sandbox.
**Fix:** Use the Termux symlink instead:
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

### `ERROR: Failed to build 'lxml'` — `libxml2 and libxslt development packages are installed`
**Fix:**
```bash
pkg install libxml2 libxslt
```
Then retry the pip install command.

---

### `npm install` fails — `Package pixman-1 was not found in the pkg-config search path`
**Context:** Inside Alpine, building the bgutil server.
**Fix:**
```bash
apk add pkgconfig pixman-dev cairo-dev pango-dev libjpeg-turbo-dev giflib-dev
```
Then retry `npm install`.

---

### `npm install` fails — `clang++: error: unsupported argument '4' to option '-flto='`
**Context:** Inside Alpine, `canvas` native module build error that persists even after installing system dependencies.
**Fix:** Bypass native compilation entirely — `canvas` is not needed at runtime:
```bash
npm install --ignore-scripts
```

---

### `npm run build` fails — `Missing script: "build"`
**Context:** Inside Alpine bgutil server directory.
**Cause:** The pre-compiled `build/` output directory already exists in the repository.
**Fix:** Check first before attempting to build:
```bash
ls build/
```
If `generate_once.js` and `main.js` are present, no build step is needed.

---

### `deno: cannot execute: required file not found`
**Cause:** Deno's prebuilt binary targets glibc; Android uses Bionic libc. The binary exists but the kernel cannot execute it.
**Fix:** Deno works correctly inside Alpine proot where glibc is available. The HTTP server architecture exploits this — Deno runs inside Alpine and exposes port 4416 to the Termux host. No fix is needed for native Termux Deno execution; the Alpine approach is the correct solution.

---

### `sh: not found` during Deno install script
**Cause:** The Deno install script attempts to self-verify the binary within the same shell session before PATH is updated.
**Fix:** This is a false alarm. The binary is correctly installed. Run `source ~/.bashrc` and `deno --version` will work.

---

### `curl http://127.0.0.1:4416` returns `Cannot GET /`
**This is not an error.** It is the correct response confirming the Express HTTP server is live and accepting connections. The root path `/` has no handler — yt-dlp calls the correct internal endpoint automatically.

---

### bgutil server killed mid-download by Android
**Cause:** Android's battery optimization aggressively terminates background processes.
**Fix:** Use `ytdlp-run.sh`, which calls `termux-wake-lock` at startup and `termux-wake-unlock` on exit, preventing Android from killing the server process during active downloads.

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
│  ytdlp-run.sh                               │
│    ├── termux-wake-lock                     │
│    ├── start bgutil server (background)     │
│    ├── wait for port 4416                   │
│    ├── yt-dlp --config termux-solo.conf     │
│    │     └── youtubepot-bgutilhttp          │
│    │           └── GET http://127.0.0.1:4416│──────┐
│    ├── kill bgutil server                   │      │
│    └── termux-wake-unlock                   │      │
└─────────────────────────────────────────────┘      │
                                                      │ localhost
┌─────────────────────────────────────────────┐      │
│         Alpine proot (background)           │      │
│                                             │      │
│  deno run -A .../server/build/main.js       │      │
│    └── Express HTTP server :4416  ◄─────────────────┘
│          └── bgutil challenge solver        │
│                └── PO token → response      │
└─────────────────────────────────────────────┘
```

The two environments communicate exclusively through `http://127.0.0.1:4416`. Localhost ports are shared between proot containers and the Termux host, making this architecture possible without any additional networking configuration.

---

## Quick Reference — Full Install Sequence

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

# 7. Place config and script
# Copy termux-solo.conf and ytdlp-run.sh to ~/storage/shared/Github/
chmod +x ~/storage/shared/Github/ytdlp-run.sh

# 8. Test download
~/storage/shared/Github/ytdlp-run.sh "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

---

## Credits and Attribution

### Inspired by scrape-youtube-termux

This project would not exist in its current form without [inotia00](https://github.com/inotia00)'s **[scrape-youtube-termux](https://github.com/inotia00/scrape-youtube-termux)** — the original proof of concept that demonstrated YouTube downloading via yt-dlp inside Termux on Android. The core idea of running yt-dlp within a Termux environment, including the proot-based architecture for handling JavaScript dependencies, traces directly back to that work. This repository builds on that foundation by extending it with the bgutil POT provider, a hardened yt-dlp config, and an automation wrapper suited for long-running downloads.

---

This repository is a **configuration and automation guide**, not a fork or redistribution of any upstream tool. All scripts and config files are original work authored by [raldisk](https://github.com/raldisk) and released under the MIT License. The following projects make this entire setup possible and deserve direct acknowledgment.

---

### yt-dlp

> The core downloader this entire repository is built around.

**yt-dlp** is maintained by the [yt-dlp team](https://github.com/yt-dlp/yt-dlp/graphs/contributors) and is a feature-rich fork of [youtube-dl](https://github.com/ytdl-org/youtube-dl). It is released into the public domain under [The Unlicense](https://github.com/yt-dlp/yt-dlp/blob/master/LICENSE).

- Repository: [https://github.com/yt-dlp/yt-dlp](https://github.com/yt-dlp/yt-dlp)
- License: [The Unlicense](https://unlicense.org/) (public domain)

If this guide saved you time, consider contributing to yt-dlp directly — bug reports, PRs, or just starring the repo.

---

### bgutil-ytdlp-pot-provider

> The plugin that solves YouTube's Proof-of-Origin token (POT) challenge.

Authored and maintained by [Brainicism](https://github.com/Brainicism). Without this provider, yt-dlp cannot authenticate properly with YouTube's newer bot-detection mechanisms, making it effectively the critical dependency for any modern Android/Termux setup.

- Repository: [https://github.com/Brainicism/bgutil-ytdlp-pot-provider](https://github.com/Brainicism/bgutil-ytdlp-pot-provider)
- License: [MIT License](https://github.com/Brainicism/bgutil-ytdlp-pot-provider/blob/master/LICENSE)

---

### yt-dlp-FixupMtime

> Post-processor plugin that preserves original upload timestamps on downloaded files.

Authored by [bradenhilton](https://github.com/bradenhilton). A small but useful plugin that sets file modification time to the video's actual upload date rather than the download date.

- Repository: [https://github.com/bradenhilton/yt-dlp-FixupMtime](https://github.com/bradenhilton/yt-dlp-FixupMtime)

---

### Termux

> The Android terminal emulator and Linux environment that makes all of this possible on mobile.

Maintained by the [Termux team](https://github.com/termux). Install from [F-Droid](https://f-droid.org/packages/com.termux/) — **not** the Play Store.

- Repository: [https://github.com/termux/termux-app](https://github.com/termux/termux-app)
- License: [GPL-3.0](https://github.com/termux/termux-app/blob/master/LICENSE.md)

---

### proot-distro

> The utility that enables running a full Alpine Linux guest inside Termux without root.

Maintained by the [Termux team](https://github.com/termux).

- Repository: [https://github.com/termux/proot-distro](https://github.com/termux/proot-distro)
- License: [GPL-3.0](https://github.com/termux/proot-distro/blob/master/LICENSE)

---

## Release Integrity

All release assets are signed with a SHA256 checksum. After downloading `yt-dlp-termux.tar.gz`, verify it before extracting:

```bash
# Download the checksum file alongside the archive, then verify
sha256sum -c yt-dlp-termux.tar.gz.sha256
```

Expected output: `yt-dlp-termux.tar.gz: OK`. Any other result means the file is corrupted or has been tampered with — do not proceed.

The canonical checksum is published as `yt-dlp-termux.tar.gz.sha256` alongside the archive in each GitHub Release. Always fetch both files from the same release tag.

---

## License

The scripts and configuration files in this repository (`ytdlp-run.sh`, `termux-solo.conf`, and all documentation) are copyright © 2026 [raldisk](https://github.com/raldisk) and released under the [MIT License](./LICENSE).

This repository **does not include, bundle, or redistribute** any code from yt-dlp, bgutil, Termux, or any other upstream project. All such tools are fetched directly from their official sources during the installation process described in this guide.
