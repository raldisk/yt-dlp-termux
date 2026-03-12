# Changelog

All notable changes to this project will be documented in this file.

---

## [2.0.0] — 2026-03-12

Full implementation of all accepted items from the peer review action plan.
29 items addressed across bugs, stale references, architecture, security, and enhancements.

### Critical Bug Fixes

**`install.sh` — item 1.1: `curl | bash` self-bootstrapping fix**
When piped through bash, `BASH_SOURCE[0]` is empty, causing `REPO_DIR` to resolve
to the user's current working directory. The install appeared to succeed but
placed no files. Fixed by detecting the pipe case, cloning the repo, and using
`exec` to replace the piped shell with a proper file execution.

**`ytdlp-run.sh` — item 1.2: `SERVER_PID` unbound variable**
`stop_server()` referenced `$SERVER_PID` before it was guaranteed to be assigned,
causing an `unbound variable` abort under `set -u` if the `EXIT` trap fired
before `start_server()` completed. Fixed by initializing `SERVER_PID=` at the
top of the script.

**`config/termux-solo.conf` — item 2.1: personal references commented out**
`--cookies`, `--download-archive`, and `-a` batchfile lines were active in the
public repo, producing immediate errors for any user who is not the repo owner.
All three lines are now commented out with a note directing users to `user.conf`.

### Major Fixes

**`ytdlp-run.sh` — item 1.3: `BGUTIL_CMD` converted to bash array**
The server launch command was stored as a plain string and word-split at
execution time. Converted to a proper bash array to eliminate the fragility.

**`bgutil-autostart.sh` — item 1.4: Termux:Boot detection corrected**
`command -v termux-reload-settings` checked for a binary that ships with
`termux-tools` on every Termux instance, making the condition unconditionally
true. Replaced with `[[ -d "$BOOT_DIR" ]]`, which only proceeds when the
Termux:Boot app is installed and the directory has been created.

**`ytdlp-run.sh` — item 1.7: `start_server()` health check with early-death detection**
The previous polling loop continued regardless of whether the server process was
still alive. Added `kill -0 $SERVER_PID` before each HTTP probe to detect
immediate process death, and treated timeout as a hard error rather than a warning.

**`config/termux-solo.conf` — item 2.2 Option B: `termux-audio.conf` restored**
`termux-audio.conf` was installed but unreachable from the launcher menu. Restored
as option 3. Batch download renumbered from option 3 to option 4.

**`ytdlp-run.sh` / `install.sh` — items 3.1, 3.2, 3.3: XDG-compliant paths**
All hardcoded `~/storage/shared/Github/yt-dlp-termux/` references replaced with
`${XDG_CONFIG_HOME:-$HOME/.config}/yt-dlp-termux/`. `install.sh` now deploys
configs and scripts to that location. `ytdlp-run.sh` is symlinked to `~/bin/yt-termux`.
Config path is overridable via `YTDLPTERMUX_CONFIG` environment variable.

**`ytdlp-run.sh` — item 3.4: process group kill and full signal trap**
`kill $SERVER_PID` only killed the proot-distro parent, leaving Alpine and Deno
as orphans across sessions. Replaced with `setsid` launch and `kill -- -$PGID`
to terminate the entire process group. Trap expanded from `EXIT` only to
`EXIT INT TERM HUP` so Ctrl+C no longer leaves the server running with the
wake lock held.

**`install.sh` — item 3.6: proot-distro and bgutil smoke test**
Added a smoke test as the final install step: starts the bgutil server briefly,
polls port 4416, and reports pass or fail. Closes the gap between "packages
installed" and "server actually starts and responds."

**`README.md` — item 4.1: version-pinned install URLs**
Published both a stable (`v2.0.0` tagged) and a development (`main`) install URL.
The stable URL ensures users can install a known-good version independently of
ongoing main-branch commits.

### Minor Fixes

**`config/termux-solo.conf` — item 1.5: duplicate `--fixup never` removed**
A copy-paste artifact from merging the changelog block. One instance removed.

**`config/termux-solo.conf` — item 1.6: `chaannel_url` typo corrected**
`%(chaannel_url|)s` had a double-`a`, silently producing an empty `channel_url`
field in every `.factsheet.nfo` file. Fixed to `%(channel_url|)s`.

**`ytdlp-run.sh` — item 1.8: `run_ytdlp()` exit code propagation**
`yt-dlp` exit codes were not explicitly captured and returned. Added
`|| return $?` to ensure the caller receives the correct exit status.

**`install.sh` — item 4.2: SHA-256 checksum generation**
`install.sh` now writes `install.sh.sha256` at the end of each install run.
README documents an optional pre-execution verification step.

**`install.sh` — item 4.3: `termux-url-opener` backup before overwrite**
Termux supports only one `termux-url-opener`. The installer now checks for an
existing unmanaged script and backs it up with a timestamp suffix before
overwriting. Restore is automatic on uninstall.

### New Features

**`lib/common.sh` — item 6.1: shared logging extracted**
`log()`, `error()`, `warn()`, and `ok()` were duplicated across all scripts.
Extracted to `lib/common.sh` sourced by all scripts. Includes `jlog()` / `jerr()`
variants that write structured JSON to `~/.local/state/yt-dlp-termux/run.log`.

**`ytdlp-run.sh` / `install.sh` — item 3.5: layered config system**
`user.conf` is now sourced after the base config, allowing personal settings
(cookies, archive file, output paths) to override base values without modifying
tracked conf files. `user.conf` is excluded from git. A fully commented template
is deployed at `config/user.conf.template`.

**`install.sh` — item 4.3 / `scripts/termux-url-opener` — item 5.1: share-menu integration**
`termux-url-opener` installed to `~/bin/` allows sharing a URL from Chrome
directly to Termux. The install step is prompted and optional.

**`ytdlp-run.sh` — item 5.2: mobile network retry logic**
`run_ytdlp()` now retries up to 3 times on transient failures (exit code 1),
with a 5-second sleep between attempts. Exit codes 2–8 (fatal yt-dlp errors)
are not retried. Both limits are configurable via environment variables.

**`ytdlp-run.sh` — item 5.3: disk space pre-flight check**
`check_disk_space()` verifies at least 2 GB of free storage before starting a
download. Threshold is configurable via `YTDLPT_MIN_FREE_MB`.

**`lib/common.sh` — item 5.4: structured JSON logging**
`jlog()`, `jok()`, `jwarn()`, `jerr()` write newline-delimited JSON entries to
`~/.local/state/yt-dlp-termux/run.log`. Filterable with `jq`.

**`ytdlp-run.sh` — item 5.5: `yt-termux update` subcommand**
`yt-termux update` updates yt-dlp and Python plugins in Termux (step 1), pulls
the latest bgutil server inside Alpine (step 2), and verifies `build/main.js`
is present (step 3). Replaces the four-step manual update sequence.

**`uninstall.sh` — item 5.6: clean removal script**
Removes symlinks, Termux:Boot script, installed files, and optionally the Alpine
proot environment. Prompts before removing `user.conf`, logs, and Alpine.
Automatically restores a backed-up `termux-url-opener` if one exists.

**`test.sh` — item 5.7: offline validation suite**
Runs `bash -n` on all scripts, checks config fields for known issues, verifies
symlinks, confirms runtime dependencies, and checks bgutil build artifacts inside
Alpine. No network access required.

**`.github/workflows/ci.yml` — item 5.8: GitHub Actions CI**
Runs on every push and pull request: `bash -n` syntax check, shellcheck,
config field validation (typo check, duplicate flag, active personal references),
secret pattern scan, and install.sh SHA-256 integrity check.

**`install.sh` — item 6.2: `default.conf` symlink**
`default.conf` is created as a symlink to `termux-solo.conf` during install.
Allows `--config-location default.conf` to reference a stable name that can be
redirected to any preset without modifying scripts.

---

## [1.0.0] — 2026-03-12

Initial release — Termux adaptation from `laptop_NEW-solo.conf`.

All Windows path separators converted to forward slashes. `youtubepot-bgutilhttp`
set as active POT provider connecting to bgutil running in Alpine proot at
`http://127.0.0.1:4416`. JS runtimes configured for Termux: node, qjs (explicit
binary path), deno (Alpine). `-N` reduced from 64 to 4 for mobile stability.
Output root renamed to `Termux-Extension-Archive`.

---

## Compatibility

| Component | Tested Version |
|-----------|----------------|
| yt-dlp | 2026.3.3+ |
| bgutil-ytdlp-pot-provider | latest `main` |
| Node.js (Termux) | v25.3.0 |
| QuickJS (Termux) | 2025-09-13 |
| Deno (Alpine proot) | latest |
| Python | 3.13 |
| Alpine Linux | 3.21+ |
| Android | 11+ (Termux F-Droid) |
