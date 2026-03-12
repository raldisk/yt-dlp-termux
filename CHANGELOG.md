# Changelog

All notable changes to this project will be documented in this file.

---

## [1.0.0] — 2026-03-12

### Initial release

#### `config/termux-solo.conf`
- Adapted from `laptop_NEW-solo.conf` for Android / Termux (aarch64)
- All Windows backslash path separators converted to forward slashes across all `-o`, `--print-to-file`, and output path templates
- `youtubepot-bgutilhttp` (HTTP server mode) set as **active** POT provider — connects to bgutil server running inside Alpine proot at `http://127.0.0.1:4416`
- `youtubepot-bgutilscript` (Node.js script mode) retained as a commented-out fallback — requires no server, invokes Node.js per download
- bgutil script path updated to correct Termux absolute path
- All Windows absolute JS runtime paths (`C:\Users\Username\...`) removed
- `--js-runtimes node` — active, installed via `pkg install nodejs`
- `--js-runtimes quickjs` — active with explicit Termux binary path (`qjs`, not `quickjs`)
- `--js-runtimes deno` — active via `~/.deno/bin/deno`
- `--js-runtimes bun` — **disabled**, ABI mismatch confirmed on test device
- `-N` reduced from `64` (laptop) to `4` (mobile CPU/RAM safety)
- `--ffmpeg-location` removed — ffmpeg in Termux PATH via `pkg install ffmpeg`
- Output archive root renamed from `Laptop-Extension-Archive` to `Termux-Extension-Archive`
- All cookie paths converted from Windows absolute paths to relative paths

#### `scripts/ytdlp-run.sh`
- Automation wrapper managing full bgutil HTTP server lifecycle
- `termux-wake-lock` acquired at startup to prevent Android from killing background processes
- Starts bgutil server inside Alpine proot as a background process
- Polls port 4416 for up to 30 seconds before proceeding
- Passes all arguments directly through to yt-dlp
- Kills bgutil server and releases `termux-wake-unlock` on exit

---

## Compatibility Notes

| Component | Version |
|-----------|---------|
| yt-dlp | 2026.3.3+ (pre-release) |
| bgutil-ytdlp-pot-provider server | latest from `main` branch |
| Node.js (Termux) | v25.3.0 |
| QuickJS (Termux) | 2025-09-13 |
| Deno (Alpine proot) | latest |
| Python | 3.13 |
| Alpine Linux | 3.21+ |
