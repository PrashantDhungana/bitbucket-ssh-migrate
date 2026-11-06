# Bitbucket SSH Migrate — `bitbucket.org` → `ssh.bitbucket.org`

**Fix Bitbucket Cloud Git SSH before it breaks.** Scan a folder of local clones and rewrite remotes from the legacy host `git@bitbucket.org` to the new host `git@ssh.bitbucket.org`.

> **Deadline:** Atlassian brownouts start **12/Nov/2026**. Final removal of SSH on `bitbucket.org` is **10/Dec/2026**.
>
> Official announcement: [Upcoming change to Bitbucket Cloud SSH access](https://community.atlassian.com/forums/discussion/3234032/upcoming-change-to-bitbucket-cloud-ssh-access-move-from-bitbucket-org-to-ssh-bitbucket-org)

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Linux%20%7C%20Windows-informational)](#quick-start)
[![GitHub stars](https://img.shields.io/github/stars/PrashantDhungana/bitbucket-ssh-migrate?style=social)](https://github.com/PrashantDhungana/bitbucket-ssh-migrate)

**Keywords:** Bitbucket Cloud SSH migration, `ssh.bitbucket.org`, update `git@bitbucket.org` remotes, Git remote URL rewrite, Atlassian SSH hostname change, Bitbucket brownout, host key verification, known_hosts.

---

## Why this exists

Bitbucket Cloud is splitting HTTPS and SSH traffic:

| Protocol | Host |
| --- | --- |
| HTTPS (web, API, `git clone` HTTPS) | `bitbucket.org` — unchanged |
| Git over SSH (`clone` / `fetch` / `pull` / `push`) | **`ssh.bitbucket.org`** — required |

If your remotes still look like this:

```text
git@bitbucket.org:<workspace>/<repo>.git
```

you need:

```text
git@ssh.bitbucket.org:<workspace>/<repo>.git
```

Doing that one repo at a time is slow. This tool walks a projects folder (or any path you pass) and updates every matching Git remote in one go — dry-run first, apply when ready.

---

## Quick start

### One-liner (Bash — macOS / Linux / Git Bash / WSL)

Preview changes under a projects folder (safe — no writes):

```bash
git clone https://github.com/PrashantDhungana/bitbucket-ssh-migrate.git
cd bitbucket-ssh-migrate
chmod +x migrate-bitbucket-ssh.sh
./migrate-bitbucket-ssh.sh ~/projects
```

Apply the migration + seed `known_hosts` for `ssh.bitbucket.org`:

```bash
./migrate-bitbucket-ssh.sh ~/projects --apply --known-hosts
```

### PowerShell (Windows)

```powershell
git clone https://github.com/PrashantDhungana/bitbucket-ssh-migrate.git
cd bitbucket-ssh-migrate
.\Migrate-BitbucketSsh.ps1 -Path C:\Users\you\projects
.\Migrate-BitbucketSsh.ps1 -Path C:\Users\you\projects -Apply -KnownHosts
```

### Single-repo manual alternative

If you only have one clone:

```bash
git remote set-url origin git@ssh.bitbucket.org:<workspace>/<repo>.git
git remote -v
```

Use this repo when you have **many local Bitbucket clones** to update.

---

## What it does

1. Recursively finds Git repositories under the folder you pass
2. Rewrites SSH remotes still pointing at `bitbucket.org` → `ssh.bitbucket.org`
3. Skips remotes already on `ssh.bitbucket.org`
4. Leaves HTTPS remotes (`https://bitbucket.org/...`) untouched
5. Optionally seeds `~/.ssh/known_hosts` from [Atlassian’s published SSH keys](https://bitbucket.org/site/ssh)

### URL rewrites

| Before | After |
| --- | --- |
| `git@bitbucket.org:ws/repo.git` | `git@ssh.bitbucket.org:ws/repo.git` |
| `ssh://git@bitbucket.org/ws/repo.git` | `ssh://git@ssh.bitbucket.org/ws/repo.git` |
| `ssh://git@bitbucket.org:22/ws/repo.git` | `ssh://git@ssh.bitbucket.org:22/ws/repo.git` |
| `https://bitbucket.org/ws/repo.git` | unchanged |

---

## Options

### Bash — `migrate-bitbucket-ssh.sh`

| Option | Meaning |
| --- | --- |
| `FOLDER` or `-p` / `--path DIR` | Folder to scan (default: current directory) |
| `-n` / `--dry-run` | Preview only (**default**) |
| `-a` / `--apply` | Write remote URL changes |
| `-d` / `--max-depth N` | Limit how deep to search for repos |
| `-k` / `--known-hosts` | Seed SSH known hosts for `ssh.bitbucket.org` |
| `-q` / `--quiet` | Less chatter |
| `-h` / `--help` | Help |

```bash
./migrate-bitbucket-ssh.sh /Users/shared/dev --max-depth 2
./migrate-bitbucket-ssh.sh ~/Herd --apply --known-hosts
```

### PowerShell — `Migrate-BitbucketSsh.ps1`

| Parameter | Meaning |
| --- | --- |
| `-Path` | Folder to scan (default: current directory) |
| *(no `-Apply`)* | Preview only (**default**) |
| `-Apply` | Write remote URL changes |
| `-MaxDepth` | Limit search depth |
| `-KnownHosts` | Seed SSH known hosts |
| `-Quiet` | Less chatter |

```powershell
.\Migrate-BitbucketSsh.ps1 -Path C:\dev -MaxDepth 2
.\Migrate-BitbucketSsh.ps1 -Path C:\dev -Apply -KnownHosts
```

---

## Verify after migration

```bash
git remote -v
ssh -T git@ssh.bitbucket.org
```

You should see remotes using `git@ssh.bitbucket.org:` and a successful SSH handshake (or Bitbucket’s authenticated greeting).

---

## FAQ / searchable errors

### “SSH access via bitbucket.org is deprecated” / brownout failures

During Atlassian’s brownout windows, SSH to `bitbucket.org` is temporarily blocked. Migrate remotes to `ssh.bitbucket.org` with this script, then retry `git fetch` / `git push`.

### `Host key verification failed` for `ssh.bitbucket.org`

Trust the new host (same keys as `bitbucket.org`, new hostname):

```bash
./migrate-bitbucket-ssh.sh --known-hosts --apply
# or Atlassian's one-liner:
curl -s https://bitbucket.org/site/ssh | sed 's/bitbucket.org/ssh.bitbucket.org/' >> ~/.ssh/known_hosts
```

### `git push` / `git pull` suddenly fails only on Bitbucket SSH

Check remotes:

```bash
git remote -v | grep bitbucket
```

If you still see `git@bitbucket.org:`, rewrite them (or run this tool on your projects folder).

### Does this affect HTTPS remotes?

No. `https://bitbucket.org/<workspace>/<repo>.git` keeps working.

### Do I need new SSH keys or deploy keys?

No. Only the **hostname** changes. Existing user SSH keys and deploy keys still apply.

### Will this touch Bitbucket Server / Data Center?

No. Only Bitbucket Cloud hostnames (`bitbucket.org` / `ssh.bitbucket.org`).

### What about CI/CD, Docker, and deploy scripts?

This tool updates **local Git remotes**. Also search pipelines and automation for:

```text
git@bitbucket.org:
ssh://git@bitbucket.org
```

and replace with `ssh.bitbucket.org`. Allowlist `ssh.bitbucket.org` on port 22 if your network filters outbound SSH.

---

## Requirements

- Git
- Bash script: macOS, Linux, Windows (Git Bash or WSL)
- PowerShell script: Windows PowerShell 5.1+ or PowerShell 7+

---

## Contributing

Issues and PRs welcome — especially docs for team rollout, CI snippets, and edge-case remotes.

If this saves you time before the **10/Dec/2026** cut-over, a ⭐ helps other developers find it.

---

## Licence

MIT — see [LICENSE](LICENSE).

**Not affiliated with Atlassian.** Built for developers dealing with the Bitbucket Cloud SSH hostname migration.
