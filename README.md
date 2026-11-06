# Bitbucket Cloud SSH migrate

Helper scripts that rewrite local Git remotes from the legacy Bitbucket Cloud SSH host (`bitbucket.org`) to the new host (`ssh.bitbucket.org`).

Atlassian is splitting HTTPS and SSH traffic. After the cut-over (final removal **10/Dec/2026**, with brownouts from **12/Nov/2026**), Git over SSH must use:

```text
git@ssh.bitbucket.org:<workspace>/<repo>.git
```

instead of:

```text
git@bitbucket.org:<workspace>/<repo>.git
```

HTTPS remotes are **not** affected and are left alone.

Source announcement: [Upcoming change to Bitbucket Cloud SSH access](https://community.atlassian.com/forums/discussion/3234032/upcoming-change-to-bitbucket-cloud-ssh-access-move-from-bitbucket-org-to-ssh-bitbucket-org)

## Requirements

- Git
- Bash script: macOS, Linux, or Windows via Git Bash / WSL
- PowerShell script: Windows PowerShell 5.1+ or PowerShell 7+

## Quick start

### Preview (safe — no changes)

**Bash**

```bash
chmod +x migrate-bitbucket-ssh.sh
./migrate-bitbucket-ssh.sh ~/projects
```

**PowerShell**

```powershell
.\Migrate-BitbucketSsh.ps1 -Path C:\Users\you\projects
```

### Apply changes

**Bash**

```bash
./migrate-bitbucket-ssh.sh ~/projects --apply
```

**PowerShell**

```powershell
.\Migrate-BitbucketSsh.ps1 -Path C:\Users\you\projects -Apply
```

### Apply and trust the new SSH host key

**Bash**

```bash
./migrate-bitbucket-ssh.sh ~/projects --apply --known-hosts
```

**PowerShell**

```powershell
.\Migrate-BitbucketSsh.ps1 -Path C:\Users\you\projects -Apply -KnownHosts
```

## What it does

1. Recursively finds Git repositories under the folder you pass
2. For each remote URL that still uses SSH against `bitbucket.org`, rewrites it to `ssh.bitbucket.org`
3. Skips remotes that already use `ssh.bitbucket.org`
4. Skips HTTPS / other hosts
5. Optionally seeds `~/.ssh/known_hosts` using Atlassian’s published keys (hostname rewritten to `ssh.bitbucket.org`)

Supported URL shapes:

| Before | After |
| --- | --- |
| `git@bitbucket.org:ws/repo.git` | `git@ssh.bitbucket.org:ws/repo.git` |
| `ssh://git@bitbucket.org/ws/repo.git` | `ssh://git@ssh.bitbucket.org/ws/repo.git` |
| `ssh://git@bitbucket.org:22/ws/repo.git` | `ssh://git@ssh.bitbucket.org:22/ws/repo.git` |
| `https://bitbucket.org/ws/repo.git` | unchanged |

## Options

### Bash (`migrate-bitbucket-ssh.sh`)

| Option | Meaning |
| --- | --- |
| `FOLDER` or `-p` / `--path DIR` | Folder to scan (default: current directory) |
| `-n` / `--dry-run` | Preview only (default) |
| `-a` / `--apply` | Write remote URL changes |
| `-d` / `--max-depth N` | Limit search depth for repos |
| `-k` / `--known-hosts` | Seed SSH known hosts for `ssh.bitbucket.org` |
| `-q` / `--quiet` | Less chatter |
| `-h` / `--help` | Help |

### PowerShell (`Migrate-BitbucketSsh.ps1`)

| Parameter | Meaning |
| --- | --- |
| `-Path` | Folder to scan (default: current directory) |
| *(no `-Apply`)* | Preview only (default) |
| `-Apply` | Write remote URL changes |
| `-MaxDepth` | Limit search depth for repos |
| `-KnownHosts` | Seed SSH known hosts for `ssh.bitbucket.org` |
| `-Quiet` | Less chatter |

## Examples for teams

Scan a shared projects directory without changing anything:

```bash
./migrate-bitbucket-ssh.sh /Users/shared/dev --max-depth 2
```

Update only one machine’s clones, then verify:

```bash
./migrate-bitbucket-ssh.sh ~/Herd --apply
cd ~/Herd/some-repo && git remote -v
```

## What this script does **not** do

- It does not edit CI/CD YAML, Dockerfiles, or deploy scripts. Search those separately for `git@bitbucket.org` / `ssh://git@bitbucket.org`.
- It does not change firewall / allowlist rules for `ssh.bitbucket.org`.
- It does not regenerate SSH keys or deploy keys (not required for this hostname change).
- It does not migrate Bitbucket Server / Data Center hosts — only Bitbucket Cloud (`bitbucket.org`).

## Verify after migration

```bash
git remote -v
ssh -T git@ssh.bitbucket.org
```

The SSH host key fingerprints published by Atlassian (same keys, new hostname) are listed in the community post linked above.

## Licence

MIT — see [LICENSE](LICENSE).
