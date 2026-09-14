#!/usr/bin/env bash
# mr-check.sh — read-only state of every pending MR/PR: one line per MR
# recorded in `mr:` on a work item that is `awaiting-merge` or in
# `feedback`. Queries the host CLI (glab / gh) and reports merged, open,
# needs-attention (changes requested / unresolved threads), closed, or
# error. Never changes anything — closing or reopening a work item stays a
# human decision (workflow/phases/08-close.md, phases/07-feedback.md).
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: mr-check.sh [--porcelain] [--timeout <seconds>] [<work-id>...]

Report the live state of every pending MR/PR: work items under work/active/
(epic children included) whose status is awaiting-merge or feedback, using
the URL(s) in their task.md `mr:` field (several URLs: space-separated on
one line). Read-only.

Verdicts:
  merged     the MR/PR is merged — the item is ready to close
  attention  open, but changes were requested or threads are unresolved
  open       open, nothing flagged (may still have comments — count shown)
  closed     closed WITHOUT merging — decide: cancel the item or reopen
  error      could not be checked (CLI missing/unauthenticated, timeout,
             unknown host, no mr: recorded) — the reason is in the detail

Options:
  --porcelain          tab-separated, one line per MR:
                       <work-id> <status> <verdict> <url> <detail>
  --timeout <seconds>  per-MR CLI timeout (default 8)
  <work-id>...         only these items (default: all pending)
  -h, --help           show this help

Exit status is 0 whenever the scan ran; 2 on usage errors. Items in
verdict "error" are reported, not fatal.
EOF
}

porcelain=no
per_timeout=8
only_ids=""
while [ $# -gt 0 ]; do
  case "$1" in
    --porcelain) porcelain=yes ;;
    --timeout)
      [ $# -ge 2 ] || mos_usage_error "--timeout requires a number of seconds"
      per_timeout="$2"
      shift
      ;;
    --timeout=*) per_timeout="${1#--timeout=}" ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*) mos_usage_error "unknown option: $1" ;;
    *) only_ids="$only_ids $1" ;;
  esac
  shift
done
case "$per_timeout" in
  '' | *[!0-9]*) mos_usage_error "--timeout must be a whole number of seconds" ;;
esac

root=$(mos_root)

# with_timeout <seconds> <cmd...> — run cmd, killing it after N seconds.
# coreutils timeout / gtimeout when present; perl's alarm otherwise (macOS
# ships perl but not timeout). Exit 124 on timeout either way.
with_timeout() {
  local secs="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  elif command -v perl >/dev/null 2>&1; then
    perl -e '
      my $secs = shift @ARGV;
      $SIG{ALRM} = sub { exit 124 };
      alarm $secs;
      my $pid = fork();
      if ($pid == 0) { exec @ARGV or exit 127 }
      waitpid($pid, 0);
      exit($? >> 8);
    ' "$secs" "$@"
  else
    "$@"
  fi
}

# json_get <jq-filter> — read JSON on stdin, print the filter's raw result.
# jq when installed, python3 otherwise (filter limited to .a.b dotted paths
# and `| length` in the fallback — all this script uses).
json_get() {
  local filter="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r "$filter" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, sys
filt = sys.argv[1]
want_len = filt.endswith("| length")
path = filt.replace("| length", "").strip().strip(".")
try:
    v = json.load(sys.stdin)
    for part in [p for p in path.split(".") if p]:
        v = v.get(part) if isinstance(v, dict) else None
    if want_len:
        print(len(v) if isinstance(v, (list, dict)) else 0)
    elif v is None:
        print("null")
    elif isinstance(v, bool):
        print("true" if v else "false")
    else:
        print(v)
except Exception:
    sys.exit(1)
' "$filter" 2>/dev/null
  else
    return 1
  fi
}

# emit <work-id> <status> <verdict> <url> <detail>
emit() {
  if [ "$porcelain" = yes ]; then
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5"
  else
    printf '%-32s %-15s %-10s %s\n' "$1" "[$2]" "$3" "$5"
    printf '%-32s %-15s %-10s %s\n' "" "" "" "$4"
  fi
}

# cli_ready <cli> — "" when usable, else the reason it is not.
cli_ready() {
  local cli="$1"
  command -v "$cli" >/dev/null 2>&1 || { printf '%s is not installed\n' "$cli"; return 0; }
  # `auth status` needs no network for gh and is cheap for glab.
  with_timeout "$per_timeout" "$cli" auth status >/dev/null 2>&1 ||
    printf '%s is not authenticated (run: %s auth login)\n' "$cli" "$cli"
  return 0
}

# check_github <url> — prints "<verdict>\t<detail>"
check_github() {
  local url="$1" json state comments decision reason
  reason=$(cli_ready gh)
  if [ -n "$reason" ]; then printf 'error\t%s\n' "$reason"; return 0; fi
  json=$(with_timeout "$per_timeout" gh pr view "$url" --json state,mergedAt,reviewDecision,comments,isDraft 2>/dev/null) || {
    case $? in
      124) printf 'error\ttimed out after %ss\n' "$per_timeout" ;;
      *) printf 'error\tgh pr view failed — check the URL and your access\n' ;;
    esac
    return 0
  }
  state=$(printf '%s' "$json" | json_get '.state') || { printf 'error\tcannot parse gh output (need jq or python3)\n'; return 0; }
  comments=$(printf '%s' "$json" | json_get '.comments | length')
  decision=$(printf '%s' "$json" | json_get '.reviewDecision')
  case "$state" in
    MERGED) printf 'merged\tmerged — ready to close\n' ;;
    CLOSED) printf 'closed\tclosed without merging — cancel the item or reopen it\n' ;;
    OPEN)
      case "$decision" in
        CHANGES_REQUESTED) printf 'attention\topen, changes requested, %s comment(s)\n' "$comments" ;;
        APPROVED) printf 'open\topen, approved, %s comment(s) — waiting on merge\n' "$comments" ;;
        *) printf 'open\topen, no review decision yet, %s comment(s)\n' "$comments" ;;
      esac
      ;;
    *) printf 'error\tunexpected state "%s" from gh\n' "$state" ;;
  esac
}

# check_gitlab <url> — prints "<verdict>\t<detail>"
check_gitlab() {
  local url="$1" repo iid json state notes resolved reason
  repo="${url%%/-/merge_requests/*}"
  iid="${url##*/-/merge_requests/}"
  iid="${iid%%[!0-9]*}"
  if [ "$repo" = "$url" ] || [ -z "$iid" ]; then
    printf 'error\tnot a merge request URL (expected .../-/merge_requests/<iid>)\n'
    return 0
  fi
  reason=$(cli_ready glab)
  if [ -n "$reason" ]; then printf 'error\t%s\n' "$reason"; return 0; fi
  json=$(with_timeout "$per_timeout" glab mr view "$iid" -R "$repo" -F json 2>/dev/null) || {
    case $? in
      124) printf 'error\ttimed out after %ss\n' "$per_timeout" ;;
      *) printf 'error\tglab mr view failed — check the URL and your access\n' ;;
    esac
    return 0
  }
  state=$(printf '%s' "$json" | json_get '.state') || { printf 'error\tcannot parse glab output (need jq or python3)\n'; return 0; }
  notes=$(printf '%s' "$json" | json_get '.user_notes_count')
  resolved=$(printf '%s' "$json" | json_get '.blocking_discussions_resolved')
  case "$state" in
    merged) printf 'merged\tmerged — ready to close\n' ;;
    closed) printf 'closed\tclosed without merging — cancel the item or reopen it\n' ;;
    opened | locked)
      if [ "$resolved" = false ]; then
        printf 'attention\topen, unresolved threads, %s note(s)\n' "$notes"
      else
        printf 'open\topen, no unresolved threads, %s note(s)\n' "$notes"
      fi
      ;;
    *) printf 'error\tunexpected state "%s" from glab\n' "$state" ;;
  esac
}

# check_url <url> — prints "<verdict>\t<detail>"
check_url() {
  local url="$1"
  case "$url" in
    https://github.com/*/pull/* | http://github.com/*/pull/*) check_github "$url" ;;
    */-/merge_requests/*) check_gitlab "$url" ;;
    *) printf 'error\tcannot tell the host from this URL — expected github.com/.../pull/N or .../-/merge_requests/N\n' ;;
  esac
}

wanted() {
  # wanted <work-id> — true when no filter was given or the id is in it
  [ -z "$only_ids" ] && return 0
  case " $only_ids " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

n_items=0
dir="$root/work/active"
if [ -d "$dir" ]; then
  while IFS= read -r doc; do
    [ -n "$doc" ] || continue
    status=$(mos_frontmatter_field "$doc" status || true)
    case "$status" in
      awaiting-merge | feedback) : ;;
      *) continue ;;
    esac
    id=$(basename "$(dirname "$doc")")
    wanted "$id" || continue
    n_items=$((n_items + 1))
    mr=$(mos_frontmatter_field "$doc" mr || true)
    if [ -z "$mr" ] || [ "$mr" = null ]; then
      emit "$id" "$status" error "-" "no mr: recorded in $(basename "$doc") — record the MR URL (phases/06-deliver.md step 3)"
      continue
    fi
    # several MRs: space- or comma-separated on one line
    for url in $(printf '%s' "$mr" | tr ',' ' '); do
      result=$(check_url "$url")
      verdict="${result%%$'\t'*}"
      detail="${result#*$'\t'}"
      emit "$id" "$status" "$verdict" "$url" "$detail"
    done
  done < <(find "$dir" -type f \( -name task.md -o -name epic.md \) 2>/dev/null | LC_ALL=C sort)
fi

if [ "$n_items" -eq 0 ] && [ "$porcelain" = no ]; then
  if [ -n "$only_ids" ]; then
    printf 'No pending MRs for:%s (not awaiting-merge or feedback under work/active/).\n' "$only_ids"
  else
    printf 'No pending MRs: no work item is awaiting-merge or in feedback.\n'
  fi
fi
exit 0
