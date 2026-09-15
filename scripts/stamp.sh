#!/usr/bin/env bash
# stamp.sh — write the harness version stamp (harness: <semver>+<template
# commit>, workspace_rev: <workspace HEAD>) into a work item's frontmatter,
# print the current stamp, or backfill every unstamped item from git history.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: stamp.sh <work-id | folder>
       stamp.sh --print
       stamp.sh --backfill [--dry-run]

Stamp a work item with the harness version that runs it:
  harness:        <VERSION>+<template commit> — the template commit is the
                  merge-base of HEAD and upstream/main when an `upstream`
                  remote exists, else HEAD, else "unknown"
  workspace_rev:  the workspace HEAD (local modifications stay traceable)

  <work-id | folder>  (re)write both fields with the CURRENT values
  --print             print the current stamp and exit
  --backfill          for every work item (epic children included) with no
                      harness: field, derive the stamp in effect on its
                      created: date from git history and write it. Items
                      older than VERSION get 0.0.0+<commit>; items older than
                      any commit get 0.0.0+unknown. One-time per workspace.
  --dry-run           with --backfill: print what would be written, change nothing
  -h, --help          show this help
EOF
}

mode=item
dry=no
target=""
while [ $# -gt 0 ]; do
  case "$1" in
    --print) mode=print ;;
    --backfill) mode=backfill ;;
    --dry-run) dry=yes ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*) mos_usage_error "unknown option: $1" ;;
    *)
      [ -z "$target" ] || mos_usage_error "unexpected argument: $1"
      target="$1"
      ;;
  esac
  shift
done
[ "$dry" = no ] || [ "$mode" = backfill ] || mos_usage_error "--dry-run only applies to --backfill"

root=$(mos_root)

# stamp_item <folder> <harness> <workspace_rev> — write both fields.
stamp_item() {
  local doc
  doc=$(mos_work_item_doc "$1")
  mos_frontmatter_set "$doc" harness "$2"
  mos_frontmatter_set "$doc" workspace_rev "$3"
  printf 'stamped: %s harness=%s workspace_rev=%s\n' "${doc#"$root"/}" "$2" "$3"
}

# stamp_at_date <YYYY-MM-DD> — "<harness>\t<workspace_rev>" in effect at the
# end of that UTC day: the first-parent workspace commit current then, its
# merge-base with upstream/main (if any) as the template commit, and VERSION
# as it existed at that template commit (0.0.0 before the file existed).
stamp_at_date() {
  local day="$1" ws="" tmpl="" ver="0.0.0"
  if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ws=$(git -C "$root" log -1 --format=%h --first-parent --before="$day 23:59:59 +0000" HEAD 2>/dev/null || true)
  fi
  if [ -z "$ws" ]; then
    printf '0.0.0+unknown\tunknown\n'
    return 0
  fi
  if git -C "$root" rev-parse --verify -q upstream/main >/dev/null 2>&1; then
    tmpl=$(git -C "$root" merge-base "$ws" upstream/main 2>/dev/null || true)
  fi
  [ -n "$tmpl" ] || tmpl="$ws"
  tmpl=$(git -C "$root" rev-parse --short "$tmpl")
  if git -C "$root" cat-file -e "$tmpl:VERSION" 2>/dev/null; then
    ver=$(git -C "$root" show "$tmpl:VERSION" | head -1 | tr -d ' \t\r')
    mos_semver_ok "$ver" || ver="0.0.0"
  fi
  printf '%s+%s\t%s\n' "$ver" "$tmpl" "$ws"
}

case "$mode" in
  print)
    [ -z "$target" ] || mos_usage_error "--print takes no work id"
    mos_harness_version
    ;;
  item)
    [ -n "$target" ] || mos_usage_error "missing <work-id | folder> (or use --print / --backfill)"
    dir=$(mos_work_item_dir "$target")
    harness=$(mos_harness_version)
    wsrev=$(mos_workspace_rev)
    stamp_item "$dir" "$harness" "$wsrev"
    ;;
  backfill)
    [ -z "$target" ] || mos_usage_error "--backfill takes no work id"
    [ -d "$root/work" ] || mos_die "no work/ directory at $root"
    n=0
    while IFS= read -r doc; do
      [ -n "$doc" ] || continue
      if [ -n "$(mos_frontmatter_field "$doc" harness || true)" ]; then
        continue
      fi
      created=$(mos_frontmatter_field "$doc" created || true)
      case "$created" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) : ;;
        *)
          mos_warn "${doc#"$root"/}: created '$created' is not a date — skipped"
          continue
          ;;
      esac
      pair=$(stamp_at_date "$created")
      harness=${pair%%	*}
      wsrev=${pair#*	}
      n=$((n + 1))
      if [ "$dry" = yes ]; then
        printf 'would stamp: %s harness=%s workspace_rev=%s (created %s)\n' "${doc#"$root"/}" "$harness" "$wsrev" "$created"
      else
        stamp_item "$(dirname "$doc")" "$harness" "$wsrev"
      fi
      # .trace-unassigned/ holds captured transcripts, not work items.
    done < <(find "$root/work" -type f \( -name task.md -o -name epic.md \) ! -path "$root/work/.trace-unassigned/*" | LC_ALL=C sort)
    printf '%s: %s item(s)\n' "$([ "$dry" = yes ] && printf 'backfill dry-run' || printf 'backfilled')" "$n"
    ;;
esac
