# yt-dlp-termux

A complete yt-dlp environment for Android Termux with bgutil PO token generation,
automated server lifecycle management, and a menu-driven launcher.

[![CI](https://github.com/raldisk/yt-dlp-termux/actions/workflows/ci.yml/badge.svg)](https://github.com/raldisk/yt-dlp-termux/actions)

> **New to this setup?** See the [Complete Setup Guide](./docs/SETUP_GUIDE.md) for step-by-step installation instructions, known errors, and architecture details.

---

## Quick Install

```bash
# Stable (recommended)
curl -L https://raw.githubusercontent.com/raldisk/yt-dlp-termux/v2.0.1/install.sh | bash

# Latest development
curl -L https://raw.githubusercontent.com/raldisk/yt-dlp-termux/master/install.sh | bash
```

The installer detects when it is piped through bash, clones the repo automatically,
and re-executes from disk — so all file paths resolve correctly on any device.

### Verify Install Script Integrity (optional)

```bash
curl -fsSL https://raw.githubusercontent.com/raldisk/yt-dlp-termux/v2.0.1/install.sh \
    -o install.sh

EXPECTED=$(curl -fsSL \
    https://raw.githubusercontent.com/raldisk/yt-dlp-termux/v2.0.1/install.sh.sha256)
ACTUAL=$(sha256sum install.sh | awk '{print $1}')

[[ "$EXPECTED" == "$ACTUAL" ]] && echo "OK — verified" || echo "MISMATCH — do not proceed"
bash install.sh
```

---

## Usage

```bash
yt-termux                          # interactive menu
yt-termux "https://youtube.com/…"  # direct download, bypasses menu
yt-termux update                   # update yt-dlp, plugins, and bgutil server
yt-termux help                     # show usage
```

**Menu options:**

| # | Config | Description |
|---|--------|-------------|
| 1 | `termux-solo.conf` | Single video or URL |
| 2 | `termux-playlist.conf` | Full playlist |
| 3 | `termux-audio.conf` | Audio only (m4a) |
| 4 | `termux-solo.conf` | Batch from `batchfile.txt` |
| q | — | Quit |

---

## What `install.sh` Does

The installer runs 13 sequential stages. Every stage is idempotent — re-running on a partially configured device is safe and skips anything already present.

**Stage 1 — Termux environment check.** Confirms the script is running inside Termux and sets up storage access (`termux-setup-storage`) so `~/storage/shared/` is reachable.

**Stage 2 — Termux package installation.** Installs the following via `pkg`: `git`, `python`, `python-pip`, `nodejs`, `quickjs`, `ffmpeg`, `proot-distro`, `libxml2`, `libxslt`. Only packages not already present are installed.

**Stage 3 — Python package installation.** Installs `yt-dlp`, `streamlink`, and `yt-dlp-FixupMtime` via pip with `--break-system-packages`. All three are upgraded if already present.

**Stage 4 — Alpine proot setup.** Installs Alpine Linux via `proot-distro install alpine` if not already present.

**Stage 5 — bgutil POT provider setup.** Enters Alpine, installs Alpine dependencies (`deno`, `nodejs`, `npm`, `git`, and native build libraries), clones the `bgutil-ytdlp-pot-provider` repository to `/root/`, and runs `npm install --ignore-scripts` to avoid the `canvas` native compilation failure on arm64.

**Stage 6 — Deno verification.** Confirms Deno is responsive inside Alpine with `deno --version`.

**Stage 7 — File deployment.** Copies configs (`termux-solo.conf`, `termux-playlist.conf`, `termux-audio.conf`) and scripts (`ytdlp-run.sh`, `bgutil-autostart.sh`) to `~/.config/yt-dlp-termux/`. Deploys `lib/common.sh`. Creates `user.conf` from the template on first install only — never overwrites an existing personal config.

**Stage 8 — `default.conf` symlink.** Creates `~/.config/yt-dlp-termux/config/default.conf` as a symlink to `termux-solo.conf`.

**Stage 9 — `termux-url-opener` (optional).** Prompted. Installs `termux-url-opener` to `~/bin/` to enable sharing URLs directly from the Android browser to Termux for immediate download. Backs up any existing unmanaged opener before overwriting.

**Stage 10 — Termux:Boot autostart.** Runs `bgutil-autostart.sh`, which installs a boot script to `~/.termux/boot/` if the Termux:Boot app is detected.

**Stage 11 — XDG state directory.** Creates `~/.local/state/yt-dlp-termux/` for structured JSON session logs.

**Stage 12 — SHA-256 checksum.** Generates `install.sh.sha256` for integrity verification.

**Stage 13 — Smoke test.** Starts the bgutil server briefly, polls port 4416, and reports whether the server responds — confirming the entire stack is functional before the install exits.

### What Gets Installed

| Location | Contents |
|----------|----------|
| `~/.config/yt-dlp-termux/config/` | `termux-solo.conf`, `termux-playlist.conf`, `termux-audio.conf`, `user.conf`, `default.conf` (symlink) |
| `~/.config/yt-dlp-termux/scripts/` | `ytdlp-run.sh`, `bgutil-autostart.sh` |
| `~/.config/yt-dlp-termux/lib/` | `common.sh` (shared logging) |
| `~/bin/yt-termux` | Symlink → `ytdlp-run.sh` |
| `~/.local/state/yt-dlp-termux/run.log` | Structured JSON session log |
| `~/.termux/boot/start-bgutil.sh` | Termux:Boot autostart (if applicable) |

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `YTDLPTERMUX_CONFIG` | `~/.config/yt-dlp-termux/config/termux-solo.conf` | Override default config |
| `YTDLPT_MIN_FREE_MB` | `2048` | Minimum free storage before download (MB) |
| `YTDLPT_MAX_RETRIES` | `3` | yt-dlp retry attempts on network error |
| `YTDLPT_RETRY_SLEEP` | `5` | Seconds between retries |
| `YTDLPT_BRANCH` | `main` | Repo branch used during curl-pipe install |

---

## Personal Configuration

Never edit `termux-solo.conf` directly for personal settings — it is managed by the
repo and overwritten on update. Place cookies, archives, and custom paths in:

```bash
nano ~/.config/yt-dlp-termux/config/user.conf
```

`user.conf` is applied after the base config and is excluded from git.
A fully commented template is at [`config/user.conf.template`](./config/user.conf.template).

---

## Uninstall

```bash
bash uninstall.sh
```

Removes all installed files, symlinks, and the Termux:Boot script. Prompts before
removing `user.conf`, logs, and the Alpine proot environment.

---

## Test Suite

```bash
bash test.sh
```

Runs offline: validates bash syntax on all scripts, checks config fields for known
issues, verifies symlinks, and confirms runtime dependencies are present.

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

Authored by [bradenhilton](https://github.com/bradenhilton). A small but precise plugin that sets file modification time to the video's actual upload date rather than the download date.

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

All release assets are published with a SHA-256 checksum. After downloading `yt-dlp-termux.tar.gz`, verify it before extracting:

```bash
sha256sum -c yt-dlp-termux.tar.gz.sha256
```

Expected output: `yt-dlp-termux.tar.gz: OK`. Any other result means the file is corrupted or has been tampered with — do not proceed. The canonical checksum is published as `yt-dlp-termux.tar.gz.sha256` alongside the archive in each GitHub Release.

---

## License

The scripts and configuration files in this repository are copyright © 2026 [raldisk](https://github.com/raldisk) and released under the [MIT License](./LICENSE).

This repository **does not include, bundle, or redistribute** any code from yt-dlp, bgutil, Termux, or any other upstream project. All such tools are fetched directly from their official sources during installation.
