#!/usr/bin/env bash
# worktree.sh — manage per-work-item git worktrees under worktrees/.
# Naming: worktrees/<repo-id>--<work-id>. The branch defaults to
# <branch_prefix><work-id> (prefix from the repo's registry entry, "work/"
# when unset); --branch overrides it entirely for org naming schemes.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: worktree.sh add    <repo-id> <work-id> [--branch <name>]
       worktree.sh remove <repo-id> <work-id> [--delete-branch]
       worktree.sh list

add     create worktrees/<repo-id>--<work-id> on a new branch, branched from
        origin/<default_branch> of the registered repo. The branch is named
        <branch_prefix><work-id> — prefix from the repo's 'branch_prefix:'
        registry field, "work/" when unset — unless --branch names it
        outright.
remove  remove that worktree (and, with --delete-branch, the branch it has
        checked out).
list    print "<repo-id>  <work-id>  <path>" for every existing worktree.

Options:
  --branch <name>   add only: exact branch name to create (overrides the
                    registry prefix; for org-enforced naming schemes)
  --delete-branch   remove only: also delete the worktree's branch
  -h, --help        show this help

Neither repo ids nor work ids may contain "--" (the folder-name separator).
EOF
}

# check_id <kind> <value> — reject empty ids, "--" and path separators.
check_id() {
  local kind="$1" value="$2"
  [ -n "$value" ] || mos_usage_error "missing $kind"
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
  local repo_id="$1" work_id="$2" branch="$3" dir branch_base worktree prefix
  check_id "repo-id" "$repo_id"
  check_id "work-id" "$work_id"
  # Checked here, at top level: a die inside the $(repo_dir ...) substitution
  # below cannot stop helpers there from each printing their own error.
  [ -f "$(mos_registry_path)" ] || mos_die "registry not found: $(mos_registry_path)"
  dir=$(repo_dir "$repo_id")

  branch_base=$(mos_yaml_repo_field "$repo_id" default_branch || true)
  [ -n "$branch_base" ] ||
    mos_die "repo '$repo_id' has no 'default_branch:' in $(mos_registry_path)"

  worktree="$(mos_root)/worktrees/${repo_id}--${work_id}"
  [ ! -e "$worktree" ] || mos_die "$worktree already exists — remove it first: scripts/worktree.sh remove $repo_id $work_id"

  if [ -z "$branch" ]; then
    prefix=$(mos_repo_branch_prefix "$repo_id")
    branch="${prefix}${work_id}"
  fi
  git check-ref-format "refs/heads/$branch" ||
    mos_die "'$branch' is not a valid git branch name"

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
  [ -f "$(mos_registry_path)" ] || mos_die "registry not found: $(mos_registry_path)"
  dir=$(repo_dir "$repo_id")

  worktree="$(mos_root)/worktrees/${repo_id}--${work_id}"
  if [ ! -d "$worktree" ]; then
    # The directory may have been deleted by hand, leaving a stale git
    # registration behind — clean that up before reporting.
    git -C "$dir" worktree prune
    mos_die "no worktree at $worktree (stale git registrations pruned)"
  fi

  # The branch name is configurable (branch_prefix / --branch at add time),
  # so ask the worktree what it actually has checked out — before removing it.
  branch=""
  if [ "$delete_branch" = "yes" ]; then
    branch=$(git -C "$worktree" symbolic-ref --short HEAD 2>/dev/null) ||
      mos_die "cannot determine the branch of $worktree (detached HEAD?) — remove without --delete-branch, then delete the branch yourself"
  fi

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

[ $# -ge 1 ] || mos_usage_error "missing subcommand"
subcommand="$1"
shift

case "$subcommand" in
  -h | --help)
    usage
    exit 0
    ;;
  add)
    add_branch=""
    add_repo_id=""
    add_work_id=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --branch)
          [ $# -ge 2 ] || mos_usage_error "--branch requires a name"
          add_branch="$2"
          shift
          ;;
        --branch=*)
          add_branch="${1#--branch=}"
          [ -n "$add_branch" ] || mos_usage_error "--branch requires a name"
          ;;
        -*) mos_usage_error "unknown option: $1" ;;
        *)
          if [ -z "$add_repo_id" ]; then
            add_repo_id="$1"
          elif [ -z "$add_work_id" ]; then
            add_work_id="$1"
          else
            mos_usage_error "unexpected argument: $1"
          fi
          ;;
      esac
      shift
    done
    [ -n "$add_repo_id" ] || mos_usage_error "add takes <repo-id> <work-id> [--branch <name>]"
    [ -n "$add_work_id" ] || mos_usage_error "add takes <repo-id> <work-id> [--branch <name>]"
    cmd_add "$add_repo_id" "$add_work_id" "$add_branch"
    ;;
  remove)
    delete_branch="no"
    rm_repo_id=""
    rm_work_id=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --delete-branch) delete_branch="yes" ;;
        -*) mos_usage_error "unknown option: $1" ;;
        *)
          if [ -z "$rm_repo_id" ]; then
            rm_repo_id="$1"
          elif [ -z "$rm_work_id" ]; then
            rm_work_id="$1"
          else
            mos_usage_error "unexpected argument: $1"
          fi
          ;;
      esac
      shift
    done
    [ -n "$rm_repo_id" ] || mos_usage_error "remove takes <repo-id> <work-id> [--delete-branch]"
    [ -n "$rm_work_id" ] || mos_usage_error "remove takes <repo-id> <work-id> [--delete-branch]"
    cmd_remove "$rm_repo_id" "$rm_work_id" "$delete_branch"
    ;;
  list)
    [ $# -eq 0 ] || mos_usage_error "list takes no arguments"
    cmd_list
    ;;
  *) mos_usage_error "unknown subcommand: $subcommand" ;;
esac
