# Security Policy

## ⚠️ CRITICAL — Never Commit Cookies

This repository's `.gitignore` excludes `*.txt` files specifically to prevent accidental cookie commits. YouTube cookies (`*.txt`) contain session tokens that grant full access to your Google account.

**Never:**
- Add cookie files to this repository
- Push a fork that includes cookie files
- Share your `termux-solo.conf` with active `--cookies` lines pointing to real files

---

## Sensitive Files in This Repo

| File | Sensitivity | Notes |
|------|------------|-------|
| `config/termux-solo.conf` | Low | Contains no secrets — paths only |
| `scripts/ytdlp-run.sh` | Low | Generic script, no credentials |
| `*.txt` (gitignored) | **CRITICAL** | Cookie files — never commit |
| `crabs-arkayb.txt` (gitignored) | Medium | Download archive — personal data |

---

## Reporting Issues

Open a GitHub issue for bugs or compatibility problems. For security concerns, contact the repository owner directly.
