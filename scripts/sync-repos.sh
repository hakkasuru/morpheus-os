#!/usr/bin/env bash
# sync-repos.sh — clone or fetch every repository in config/repos.yaml.
# Writes nothing outside repos/.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: sync-repos.sh [--repo <id>]

Clone every repository listed in config/repos.yaml into repos/<id>, or fetch it
when it is already there, then fast-forward the local 'default_branch:' to
match origin. Idempotent; nothing outside repos/ is touched. repos/<id> is
never committed to directly, so the fast-forward can never lose work — if
that invariant is ever violated (local branch diverged, or a different
branch checked out), sync fails loud on that repo rather than guessing.

Options:
  --repo <id>   sync only this registry id
  -h, --help    show this help
EOF
}

repo_filter=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --repo)
      [ $# -ge 2 ] || mos_usage_error "--repo requires an id"
      repo_filter="$2"
      shift 2
      ;;
    --repo=*)
      repo_filter="${1#--repo=}"
      [ -n "$repo_filter" ] || mos_usage_error "--repo requires an id"
      shift
      ;;
    *) mos_usage_error "unexpected argument: $1" ;;
  esac
done

root=$(mos_root)
registry=$(mos_registry_path)

sync_one() {
  local id="$1" dest remote default_branch current
  dest="$root/repos/$id"

  default_branch=$(mos_yaml_repo_field "$id" default_branch || true)
  [ -n "$default_branch" ] || mos_die "repo '$id' has no 'default_branch:' in $registry"

  if [ -d "$dest/.git" ]; then
    git -C "$dest" fetch --prune ||
      mos_die "fetch failed for '$id' (repos/$id) — check the remote and your network"
    printf 'sync: %s fetched\n' "$id"
  else
    if [ -e "$dest" ]; then
      mos_die "repos/$id exists but is not a git repository — remove it, then re-run sync-repos.sh"
    fi
    remote=$(mos_yaml_repo_field "$id" remote || true)
    [ -n "$remote" ] || mos_die "repo '$id' has no 'remote:' in $registry"
    mkdir -p "$root/repos"
    git clone "$remote" "$dest" ||
      mos_die "clone failed for '$id' from $remote — check the URL and your credentials"
    printf 'sync: %s cloned\n' "$id"
  fi

  # Fast-forward the local default branch to origin's. repos/<id> is never
  # committed to directly (see AGENTS.md), so this can never lose work —
  # unless that invariant has somehow been violated, in which case fail loud
  # instead of guessing which side to keep.
  current=$(git -C "$dest" symbolic-ref --quiet --short HEAD || true)
  if [ "$current" = "$default_branch" ]; then
    if git -C "$dest" show-ref --verify --quiet "refs/remotes/origin/$default_branch"; then
      git -C "$dest" merge --ff-only "origin/$default_branch" >/dev/null ||
        mos_die "repos/$id: local '$default_branch' has diverged from 'origin/$default_branch' — repos/$id should never be committed to directly; fix it manually"
    else
      mos_warn "repos/$id: origin has no '$default_branch' branch — check 'default_branch:' in $registry"
    fi
  elif [ -n "$current" ]; then
    mos_warn "repos/$id: checked out branch '$current', not the registered default '$default_branch' — leaving it as-is; repos/$id should never be worked in directly"
  else
    mos_warn "repos/$id: HEAD is detached — leaving it as-is; repos/$id should never be worked in directly"
  fi

  mos_check_host_cli "$id"
}

ids=$(mos_yaml_repo_ids)
[ -n "$ids" ] || mos_die "no repositories found in $registry — add at least one entry"

if [ -n "$repo_filter" ]; then
  mos_repo_registered "$repo_filter" ||
    mos_die "repo '$repo_filter' is not in $registry — known ids: $(mos_yaml_repo_ids | tr '\n' ' ')"
  ids="$repo_filter"
fi

count=0
# fd 3 keeps stdin free for git (credential prompts).
while IFS= read -r id <&3; do
  [ -n "$id" ] || continue
  sync_one "$id"
  count=$((count + 1))
done 3<<EOF
$ids
EOF

printf 'sync: %s repo(s) up to date\n' "$count"
