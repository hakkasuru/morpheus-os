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
when it is already there. Idempotent; nothing outside repos/ is touched.

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
  local id="$1" dest remote
  dest="$root/repos/$id"

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
