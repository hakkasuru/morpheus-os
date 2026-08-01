#!/usr/bin/env bash
# worktree.sh — manage per-work-item git worktrees under worktrees/.
# Naming: worktrees/<repo-id>--<work-id> on branch work/<work-id>.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: worktree.sh add    <repo-id> <work-id>
       worktree.sh remove <repo-id> <work-id> [--delete-branch]
       worktree.sh list

add     create worktrees/<repo-id>--<work-id> on a new branch work/<work-id>,
        branched from origin/<default_branch> of the registered repo.
remove  remove that worktree (and, with --delete-branch, its branch).
list    print "<repo-id>  <work-id>  <path>" for every existing worktree.

Options:
  --delete-branch   remove only: also delete the work/<work-id> branch
  -h, --help        show this help

Neither repo ids nor work ids may contain "--" (the folder-name separator).
EOF
}

usage_error() {
  printf 'error: %s\n' "$*" >&2
  usage >&2
  exit 2
}

# check_id <kind> <value> — reject empty ids, "--" and path separators.
check_id() {
  local kind="$1" value="$2"
  [ -n "$value" ] || usage_error "missing $kind"
  case "$value" in
    *--*) mos_die "$kind '$value' contains '--', which is the worktrees/<repo-id>--<work-id> separator — rename it" ;;
    */* | .* ) mos_die "$kind '$value' must be a plain name (no '/' and no leading '.')" ;;
  esac
}

# repo_dir <repo-id> — validated path of the local clone.
repo_dir() {
  local id="$1" dir
  mos_repo_registered "$id" ||
    mos_die "repo '$id' is not in $(mos_registry_path) — known ids: $(mos_yaml_repo_ids | tr '\n' ' ')"
  dir="$(mos_root)/repos/$id"
  [ -d "$dir/.git" ] ||
    mos_die "repos/$id is missing — run: scripts/sync-repos.sh --repo $id"
  printf '%s\n' "$dir"
}

cmd_add() {
  local repo_id="$1" work_id="$2" dir branch_base worktree branch
  check_id "repo-id" "$repo_id"
  check_id "work-id" "$work_id"
  dir=$(repo_dir "$repo_id")

  branch_base=$(mos_yaml_repo_field "$repo_id" default_branch || true)
  [ -n "$branch_base" ] ||
    mos_die "repo '$repo_id' has no 'default_branch:' in $(mos_registry_path)"

  worktree="$(mos_root)/worktrees/${repo_id}--${work_id}"
  [ ! -e "$worktree" ] || mos_die "$worktree already exists — remove it first: scripts/worktree.sh remove $repo_id $work_id"
  branch="work/$work_id"

  git -C "$dir" fetch --prune ||
    mos_die "fetch failed for '$repo_id' — check the remote and your network"

  mkdir -p "$(mos_root)/worktrees"
  git -C "$dir" worktree add "$worktree" -b "$branch" "origin/$branch_base" ||
    mos_die "worktree add failed — does origin/$branch_base exist and is branch '$branch' free? (git -C repos/$repo_id branch -D '$branch')"

  printf '%s\n' "$worktree"
}

cmd_remove() {
  local repo_id="$1" work_id="$2" delete_branch="$3" dir worktree branch
  check_id "repo-id" "$repo_id"
  check_id "work-id" "$work_id"
  dir=$(repo_dir "$repo_id")

  worktree="$(mos_root)/worktrees/${repo_id}--${work_id}"
  branch="work/$work_id"
  [ -d "$worktree" ] || mos_die "no worktree at $worktree"

  git -C "$dir" worktree remove "$worktree" ||
    mos_die "git refused to remove $worktree — --force not supported; commit or clean the worktree first"

  if [ "$delete_branch" = "yes" ]; then
    git -C "$dir" branch -D "$branch" ||
      mos_die "could not delete branch '$branch' in repos/$repo_id"
  fi

  git -C "$dir" worktree prune
  printf 'removed: %s\n' "$worktree"
}

cmd_list() {
  local dir name repo_id work_id
  for dir in "$(mos_root)"/worktrees/*--*; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    repo_id="${name%%--*}"
    work_id="${name#*--}"
    printf '%s  %s  %s\n' "$repo_id" "$work_id" "$dir"
  done
}

[ $# -ge 1 ] || usage_error "missing subcommand"
subcommand="$1"
shift

case "$subcommand" in
  -h | --help)
    usage
    exit 0
    ;;
  add)
    [ $# -eq 2 ] || usage_error "add takes <repo-id> <work-id>"
    cmd_add "$1" "$2"
    ;;
  remove)
    delete_branch="no"
    rm_repo_id=""
    rm_work_id=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --delete-branch) delete_branch="yes" ;;
        -*) usage_error "unknown option: $1" ;;
        *)
          if [ -z "$rm_repo_id" ]; then
            rm_repo_id="$1"
          elif [ -z "$rm_work_id" ]; then
            rm_work_id="$1"
          else
            usage_error "unexpected argument: $1"
          fi
          ;;
      esac
      shift
    done
    [ -n "$rm_repo_id" ] || usage_error "remove takes <repo-id> <work-id> [--delete-branch]"
    [ -n "$rm_work_id" ] || usage_error "remove takes <repo-id> <work-id> [--delete-branch]"
    cmd_remove "$rm_repo_id" "$rm_work_id" "$delete_branch"
    ;;
  list)
    [ $# -eq 0 ] || usage_error "list takes no arguments"
    cmd_list
    ;;
  *) usage_error "unknown subcommand: $subcommand" ;;
esac
