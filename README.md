# yt-dlp-termux

A complete yt-dlp environment for Android Termux with bgutil PO token generation,
automated server lifecycle management, and a menu-driven launcher.

[![CI](https://github.com/raldisk/yt-dlp-termux/actions/workflows/ci.yml/badge.svg)](https://github.com/raldisk/yt-dlp-termux/actions)

---

## Quick Install

```bash
# Stable (recommended)
curl -L https://raw.githubusercontent.com/raldisk/yt-dlp-termux/v2.0.0/install.sh | bash

# Latest development
curl -L https://raw.githubusercontent.com/raldisk/yt-dlp-termux/main/install.sh | bash
```

The installer detects when it is piped through bash, clones the repo automatically,
and re-executes from disk — so all file paths resolve correctly on any device.

### Verify Install Script Integrity (optional)

```bash
curl -fsSL https://raw.githubusercontent.com/raldisk/yt-dlp-termux/v2.0.0/install.sh \
    -o install.sh

EXPECTED=$(curl -fsSL \
    https://raw.githubusercontent.com/raldisk/yt-dlp-termux/v2.0.0/install.sh.sha256)
ACTUAL=$(sha256sum install.sh | awk '{print $1}')

[[ "$EXPECTED" == "$ACTUAL" ]] && echo "OK — verified" || echo "MISMATCH — do not proceed"
bash install.sh
```

---

## What Gets Installed

| Location | Contents |
|----------|----------|
| `~/.config/yt-dlp-termux/config/` | `termux-solo.conf`, `termux-playlist.conf`, `termux-audio.conf`, `user.conf`, `default.conf` (symlink) |
| `~/.config/yt-dlp-termux/scripts/` | `ytdlp-run.sh`, `bgutil-autostart.sh` |
| `~/.config/yt-dlp-termux/lib/` | `common.sh` (shared logging) |
| `~/bin/yt-termux` | Symlink → `ytdlp-run.sh` |
| `~/.local/state/yt-dlp-termux/run.log` | Structured JSON session log |

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

## Personal Configuration

Never edit `termux-solo.conf` directly for personal settings — it is managed by the
repo and overwritten on update. Place cookies, archives, and custom paths in your
personal override file instead:

```bash
nano ~/.config/yt-dlp-termux/config/user.conf
```

`user.conf` is applied after the base config and is excluded from git.
A fully commented template is at `config/user.conf.template`.

---

## Runtime Architecture

```
Android browser (share URL)
        │
        ▼
~/bin/termux-url-opener
        │
        ▼
scripts/ytdlp-run.sh
        ├── check_disk_space()          2 GB default, configurable
        ├── start_server()
        │     ├── setsid BGUTIL_CMD[@] &    own process group
        │     ├── kill -0 $SERVER_PID       early-death detection
        │     └── curl :4416 health check   200 or 404 = alive
        ├── run_ytdlp()
        │     ├── base.conf + user.conf overlay (layered config)
        │     └── retry loop — max 3 attempts, skip fatal codes 2–8
        └── stop_server()
              └── kill -- -$PGID            entire process group

Alpine proot (background)
        └── deno run build/main.js :4416   bgutil HTTP server
```

---

## Section 13 — Manual Verification

If the smoke test at the end of install is inconclusive:

```bash
# Terminal 1 — start the bgutil server
proot-distro login alpine -- \
    deno run -A /root/bgutil-ytdlp-pot-provider/server/build/main.js

# Terminal 2 — health check (expected: Cannot GET /)
curl http://127.0.0.1:4416
```

A `Cannot GET /` response with HTTP 404 confirms the server is alive and accepting
connections. Any non-response after 30 s indicates an Alpine or Deno issue.

---

## Update

```bash
yt-termux update
```

Runs three steps in sequence: updates yt-dlp and Python plugins via pip in Termux, pulls the latest bgutil server inside Alpine and reinstalls Node dependencies, then verifies `build/main.js` is present. Each step reports pass or fail and exits early on any error.

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
issues (typos, duplicates, active personal references), verifies symlinks, and
confirms runtime dependencies are present.

---

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `YTDLPTERMUX_CONFIG` | `~/.config/yt-dlp-termux/config/termux-solo.conf` | Override default config |
| `YTDLPT_MIN_FREE_MB` | `2048` | Minimum free storage before download (MB) |
| `YTDLPT_MAX_RETRIES` | `3` | yt-dlp retry attempts on network error |
| `YTDLPT_RETRY_SLEEP` | `5` | Seconds between retries |
| `YTDLPT_BRANCH` | `main` | Repo branch used during curl-pipe install |

---

## License

MIT — see [LICENSE](LICENSE).
