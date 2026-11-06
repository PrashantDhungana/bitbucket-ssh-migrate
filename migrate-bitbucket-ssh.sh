#!/usr/bin/env bash
# Migrate Bitbucket Cloud Git SSH remotes from bitbucket.org to ssh.bitbucket.org
# See: https://community.atlassian.com/forums/discussion/3234032/
#
# Works on macOS, Linux, and Windows (Git Bash / WSL). Requires: git, bash, find.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
OLD_HOST="bitbucket.org"
NEW_HOST="ssh.bitbucket.org"
KNOWN_HOSTS_SOURCE="https://bitbucket.org/site/ssh"

DRY_RUN=1
SEED_KNOWN_HOSTS=0
MAX_DEPTH=""
SCAN_PATH=""
QUIET=0

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS] [FOLDER]

Scan FOLDER (default: current directory) for Git repositories and rewrite
Bitbucket Cloud SSH remotes from git@bitbucket.org to git@ssh.bitbucket.org.

HTTPS remotes are left unchanged. Remotes already using ssh.bitbucket.org are skipped.

Options:
  -p, --path DIR       Folder to scan (same as positional FOLDER)
  -a, --apply          Apply changes (default is dry-run / preview only)
  -n, --dry-run        Preview only; do not change remotes (default)
  -d, --max-depth N    Limit how deep to search for .git directories
  -k, --known-hosts    Also seed ~/.ssh/known_hosts for ssh.bitbucket.org
  -q, --quiet          Only print changes and the summary
  -h, --help           Show this help

Examples:
  $SCRIPT_NAME ~/Herd
  $SCRIPT_NAME --path ~/projects --dry-run
  $SCRIPT_NAME --path ~/projects --apply
  $SCRIPT_NAME --path ~/projects --apply --known-hosts --max-depth 3
EOF
}

log() {
  if [[ "$QUIET" -eq 0 ]]; then
    printf '%s\n' "$*"
  fi
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

# Rewrite only SSH URLs that still point at bitbucket.org (not ssh.bitbucket.org).
rewrite_url() {
  local url="$1"
  # Already migrated
  if [[ "$url" == *"@${NEW_HOST}"* ]] || [[ "$url" == *"://${NEW_HOST}/"* ]] || [[ "$url" == *"://${NEW_HOST}:"* ]]; then
    printf '%s\n' "$url"
    return 0
  fi
  # SCP-style: git@bitbucket.org:workspace/repo.git
  if [[ "$url" =~ ^([^@]*@)${OLD_HOST}:(.+)$ ]]; then
    printf '%s%s:%s\n' "${BASH_REMATCH[1]}" "$NEW_HOST" "${BASH_REMATCH[2]}"
    return 0
  fi
  # ssh://git@bitbucket.org[:port]/path
  if [[ "$url" =~ ^(ssh://[^@]*@)${OLD_HOST}([:/].+)$ ]]; then
    printf '%s%s%s\n' "${BASH_REMATCH[1]}" "$NEW_HOST" "${BASH_REMATCH[2]}"
    return 0
  fi
  # Unchanged (HTTPS, other hosts, etc.)
  printf '%s\n' "$url"
}

needs_rewrite() {
  local url="$1" new
  new="$(rewrite_url "$url")"
  [[ "$new" != "$url" ]]
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p|--path)
        [[ $# -ge 2 ]] || die "--path requires a directory"
        SCAN_PATH="$2"
        shift 2
        ;;
      -a|--apply)
        DRY_RUN=0
        shift
        ;;
      -n|--dry-run)
        DRY_RUN=1
        shift
        ;;
      -d|--max-depth)
        [[ $# -ge 2 ]] || die "--max-depth requires a number"
        [[ "$2" =~ ^[0-9]+$ ]] || die "--max-depth must be a non-negative integer"
        MAX_DEPTH="$2"
        shift 2
        ;;
      -k|--known-hosts)
        SEED_KNOWN_HOSTS=1
        shift
        ;;
      -q|--quiet)
        QUIET=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        die "Unknown option: $1 (try --help)"
        ;;
      *)
        if [[ -n "$SCAN_PATH" ]]; then
          die "Unexpected argument: $1 (folder already set to $SCAN_PATH)"
        fi
        SCAN_PATH="$1"
        shift
        ;;
    esac
  done

  if [[ -z "$SCAN_PATH" ]]; then
    SCAN_PATH="."
  fi
}

seed_known_hosts() {
  local ssh_dir="${HOME}/.ssh"
  local known_hosts="${ssh_dir}/known_hosts"
  local tmp keys

  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir" 2>/dev/null || true
  touch "$known_hosts"
  chmod 600 "$known_hosts" 2>/dev/null || true

  if grep -qE '(^|[, ])ssh\.bitbucket\.org[, ]' "$known_hosts" 2>/dev/null \
    || grep -qF "ssh.bitbucket.org " "$known_hosts" 2>/dev/null; then
    log "known_hosts: ssh.bitbucket.org already present — skipping"
    return 0
  fi

  require_cmd curl
  tmp="$(mktemp)"
  # Atlassian publishes host keys for bitbucket.org; rewrite hostname for the new SSH endpoint.
  if ! curl -fsSL "$KNOWN_HOSTS_SOURCE" | sed "s/${OLD_HOST}/${NEW_HOST}/g" >"$tmp"; then
    rm -f "$tmp"
    die "Failed to download host keys from $KNOWN_HOSTS_SOURCE"
  fi

  keys="$(cat "$tmp")"
  rm -f "$tmp"
  [[ -n "$keys" ]] || die "Downloaded host key list was empty"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN known_hosts: would append ssh.bitbucket.org keys to %s\n' "$known_hosts"
    return 0
  fi

  printf '\n# Bitbucket Cloud SSH host keys (%s) — added by %s\n%s\n' \
    "$NEW_HOST" "$SCRIPT_NAME" "$keys" >>"$known_hosts"
  printf 'known_hosts: appended keys for %s\n' "$NEW_HOST"
}

find_git_dirs() {
  local root="$1"
  local -a find_args=("$root")

  if [[ -n "$MAX_DEPTH" ]]; then
    # .git may sit at depth N+1 relative to root when repos are nested under projects/
    find_args+=(-maxdepth "$((MAX_DEPTH + 1))")
  fi

  # Match work trees (.git directory) and some bare/file layouts via -name .git
  find "${find_args[@]}" \( -type d -name .git -o -type f -name .git \) 2>/dev/null \
    | sed 's|/\.git$||' \
    | sort -u
}

migrate_repo() {
  local repo="$1"
  local remotes remote url new_url changed=0

  if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    && ! git -C "$repo" rev-parse --is-bare-repository >/dev/null 2>&1; then
    return 0
  fi

  remotes="$(git -C "$repo" remote 2>/dev/null || true)"
  [[ -n "$remotes" ]] || return 0

  while IFS= read -r remote; do
    [[ -n "$remote" ]] || continue
    url="$(git -C "$repo" remote get-url "$remote" 2>/dev/null || true)"
    [[ -n "$url" ]] || continue

    if ! needs_rewrite "$url"; then
      continue
    fi

    new_url="$(rewrite_url "$url")"
    changed=1

    if [[ "$DRY_RUN" -eq 1 ]]; then
      printf 'DRY-RUN  %s\n  remote %s\n  %s\n  -> %s\n' "$repo" "$remote" "$url" "$new_url"
    else
      git -C "$repo" remote set-url "$remote" "$new_url"
      printf 'UPDATED  %s\n  remote %s\n  %s\n  -> %s\n' "$repo" "$remote" "$url" "$new_url"
    fi
  done <<<"$remotes"

  return 0
}

main() {
  parse_args "$@"
  require_cmd git
  require_cmd find

  local root
  root="$(cd "$SCAN_PATH" 2>/dev/null && pwd)" || die "Folder not found: $SCAN_PATH"

  log "Bitbucket Cloud SSH migration helper"
  log "Scan path : $root"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "Mode      : dry-run (preview only — pass --apply to change remotes)"
  else
    log "Mode      : apply"
  fi
  [[ -n "$MAX_DEPTH" ]] && log "Max depth : $MAX_DEPTH"
  log ""

  local repos_found=0 remotes_touched=0
  local repo

  while IFS= read -r repo; do
    [[ -n "$repo" ]] || continue
    repos_found=$((repos_found + 1))

    # Count potential changes for summary
    local remotes remote url
    remotes="$(git -C "$repo" remote 2>/dev/null || true)"
    while IFS= read -r remote; do
      [[ -n "$remote" ]] || continue
      url="$(git -C "$repo" remote get-url "$remote" 2>/dev/null || true)"
      if needs_rewrite "$url"; then
        remotes_touched=$((remotes_touched + 1))
      fi
    done <<<"$remotes"

    migrate_repo "$repo"
  done < <(find_git_dirs "$root")

  if [[ "$SEED_KNOWN_HOSTS" -eq 1 ]]; then
    log ""
    seed_known_hosts
  fi

  log ""
  log "Summary"
  log "  Git repos scanned : $repos_found"
  log "  Remotes to update : $remotes_touched"
  if [[ "$DRY_RUN" -eq 1 && "$remotes_touched" -gt 0 ]]; then
    log "  Re-run with --apply to write changes."
  fi
  if [[ "$SEED_KNOWN_HOSTS" -eq 0 ]]; then
    log "  Tip: add --known-hosts to pre-trust ssh.bitbucket.org (optional)."
  fi
}

main "$@"
