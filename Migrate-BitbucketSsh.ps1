#Requires -Version 5.1
<#
.SYNOPSIS
  Migrate Bitbucket Cloud Git SSH remotes from bitbucket.org to ssh.bitbucket.org.

.DESCRIPTION
  Scans a folder for Git repositories and rewrites SSH remotes that still use
  git@bitbucket.org (or ssh://git@bitbucket.org) to ssh.bitbucket.org.
  HTTPS remotes are left unchanged.

  Reference:
  https://community.atlassian.com/forums/discussion/3234032/

.PARAMETER Path
  Folder to scan. Defaults to the current directory.

.PARAMETER Apply
  Apply remote URL changes. Without this switch the script is dry-run only.

.PARAMETER MaxDepth
  Limit how deep to search for repositories relative to Path.

.PARAMETER KnownHosts
  Also seed ~/.ssh/known_hosts (or $env:USERPROFILE\.ssh\known_hosts) for ssh.bitbucket.org.

.PARAMETER Quiet
  Only print changes and the summary.

.EXAMPLE
  .\Migrate-BitbucketSsh.ps1 -Path C:\Users\me\Herd

.EXAMPLE
  .\Migrate-BitbucketSsh.ps1 -Path C:\Users\me\projects -Apply -KnownHosts
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path = '.',

    [switch]$Apply,

    [ValidateRange(0, 64)]
    [Nullable[int]]$MaxDepth,

    [switch]$KnownHosts,

    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$OldHost = 'bitbucket.org'
$NewHost = 'ssh.bitbucket.org'
$KnownHostsSource = 'https://bitbucket.org/site/ssh'

function Write-Info {
    param([string]$Message)
    if (-not $Quiet) {
        Write-Host $Message
    }
}

function Test-GitAvailable {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'Required command not found: git'
    }
}

function Rewrite-BitbucketSshUrl {
    param([string]$Url)

    if ($Url.Contains("@$NewHost") -or $Url.Contains("://$NewHost")) {
        return $Url
    }

    $escapedOld = [regex]::Escape($OldHost)

    # SCP-style: git@bitbucket.org:workspace/repo.git
    $scp = [regex]::Match($Url, "^(?<prefix>[^@]*@)${escapedOld}:(?<rest>.+)$")
    if ($scp.Success) {
        return "$($scp.Groups['prefix'].Value)$NewHost:$($scp.Groups['rest'].Value)"
    }

    # ssh://git@bitbucket.org[:port]/path
    $sshUri = [regex]::Match($Url, "^(?<prefix>ssh://[^@]*@)${escapedOld}(?<rest>[:/].+)$")
    if ($sshUri.Success) {
        return "$($sshUri.Groups['prefix'].Value)$NewHost$($sshUri.Groups['rest'].Value)"
    }

    return $Url
}

function Test-NeedsRewrite {
    param([string]$Url)
    return (Rewrite-BitbucketSshUrl -Url $Url) -ne $Url
}

function Get-GitRepos {
    param(
        [string]$Root,
        [Nullable[int]]$Depth
    )

    $gitItems = Get-ChildItem -Path $Root -Filter '.git' -Force -Recurse -ErrorAction SilentlyContinue
    if ($null -ne $Depth) {
        $rootFull = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')
        $gitItems = $gitItems | Where-Object {
            $rel = $_.FullName.Substring($rootFull.Length).TrimStart('\', '/')
            $parts = @($rel -split '[\\/]' | Where-Object { $_ -ne '' })
            # parts include trailing ".git", so repo depth is parts.Count - 1
            ($parts.Count - 1) -le $Depth
        }
    }

    $gitItems |
        ForEach-Object {
            if ($_.PSIsContainer -or $_.Name -eq '.git') {
                Split-Path -Parent $_.FullName
            }
        } |
        Sort-Object -Unique
}

function Add-SshKnownHosts {
    param([bool]$DoApply)

    $sshDir = Join-Path $HOME '.ssh'
    $knownHostsPath = Join-Path $sshDir 'known_hosts'

    if (-not (Test-Path -LiteralPath $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir | Out-Null
    }
    if (-not (Test-Path -LiteralPath $knownHostsPath)) {
        New-Item -ItemType File -Path $knownHostsPath | Out-Null
    }

    $existing = Get-Content -LiteralPath $knownHostsPath -ErrorAction SilentlyContinue
    if ($existing | Where-Object { $_ -match '(^|[, ])ssh\.bitbucket\.org([, ]|$)' }) {
        Write-Info 'known_hosts: ssh.bitbucket.org already present — skipping'
        return
    }

    try {
        $raw = (Invoke-WebRequest -Uri $KnownHostsSource -UseBasicParsing).Content
    }
    catch {
        throw "Failed to download host keys from $KnownHostsSource. $_"
    }

    $keys = ($raw -replace [regex]::Escape($OldHost), $NewHost).Trim()
    if ([string]::IsNullOrWhiteSpace($keys)) {
        throw 'Downloaded host key list was empty'
    }

    if (-not $DoApply) {
        Write-Host "DRY-RUN known_hosts: would append ssh.bitbucket.org keys to $knownHostsPath"
        return
    }

    $block = @(
        ''
        "# Bitbucket Cloud SSH host keys ($NewHost) — added by Migrate-BitbucketSsh.ps1"
        $keys
        ''
    ) -join [Environment]::NewLine

    Add-Content -LiteralPath $knownHostsPath -Value $block -Encoding ascii
    Write-Host "known_hosts: appended keys for $NewHost"
}

function Update-RepoRemotes {
    param(
        [string]$Repo,
        [bool]$DoApply,
        [ref]$Touched
    )

    $remotes = @(git -C $Repo remote 2>$null)
    foreach ($remote in $remotes) {
        if ([string]::IsNullOrWhiteSpace($remote)) { continue }
        $url = (git -C $Repo remote get-url $remote 2>$null)
        if ([string]::IsNullOrWhiteSpace($url)) { continue }
        if (-not (Test-NeedsRewrite -Url $url)) { continue }

        $newUrl = Rewrite-BitbucketSshUrl -Url $url
        $Touched.Value++

        if ($DoApply) {
            git -C $Repo remote set-url $remote $newUrl
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to update remote '$remote' in $Repo"
            }
            Write-Host @"
UPDATED  $Repo
  remote $remote
  $url
  -> $newUrl
"@
        }
        else {
            Write-Host @"
DRY-RUN  $Repo
  remote $remote
  $url
  -> $newUrl
"@
        }
    }
}

Test-GitAvailable

$root = (Resolve-Path -LiteralPath $Path).Path
$doApply = [bool]$Apply

Write-Info 'Bitbucket Cloud SSH migration helper'
Write-Info "Scan path : $root"
if ($doApply) {
    Write-Info 'Mode      : apply'
}
else {
    Write-Info 'Mode      : dry-run (preview only — pass -Apply to change remotes)'
}
if ($null -ne $MaxDepth) {
    Write-Info "Max depth : $MaxDepth"
}
Write-Info ''

$repos = @(Get-GitRepos -Root $root -Depth $MaxDepth)
$remotesTouched = 0

foreach ($repo in $repos) {
    Update-RepoRemotes -Repo $repo -DoApply $doApply -Touched ([ref]$remotesTouched)
}

if ($KnownHosts) {
    Write-Info ''
    Add-SshKnownHosts -DoApply $doApply
}

Write-Info ''
Write-Info 'Summary'
Write-Info "  Git repos scanned : $($repos.Count)"
Write-Info "  Remotes to update : $remotesTouched"
if (-not $doApply -and $remotesTouched -gt 0) {
    Write-Info '  Re-run with -Apply to write changes.'
}
if (-not $KnownHosts) {
    Write-Info '  Tip: add -KnownHosts to pre-trust ssh.bitbucket.org (optional).'
}
