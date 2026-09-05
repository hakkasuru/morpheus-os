#!/usr/bin/env bash
# session-brief.sh — read-only "what should I pick up?" brief, meant to run
# at agent session start (wired as a Claude Code SessionStart hook in
# .claude/settings.json and a Copilot CLI sessionStart hook in
# .github/hooks/session-brief.json). Reports open work items, knowledge docs that need
# maintenance (past stale_after, long-lived drafts, agent-authored docs not
# yet human-verified) and an ordered priority list — or says plainly that
# there is nothing to pick up. Never writes anything.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: session-brief.sh [--hook [claude|copilot]]

Print a short session-start brief: open work items (flagging gates waiting
on you and blocked items), knowledge docs due for maintenance or review,
and an ordered list of priorities. States explicitly when there is nothing
to pick up.

Options:
  --hook [client]  emit the brief as session-start hook JSON for the given
                   client instead of plain text:
                     claude   Claude Code SessionStart
                              ({"hookSpecificOutput":{"additionalContext":..}})
                              — the default when no client is given
                     copilot  GitHub Copilot CLI sessionStart
                              ({"additionalContext":..})
  -h, --help       show this help
EOF
}

mode=text
client=claude
case "${1:-}" in
  '') : ;;
  --hook)
    mode=hook
    case "${2:-}" in
      '' | claude) : ;;
      copilot) client=copilot ;;
      *) mos_usage_error "unknown hook client '$2' — expected claude or copilot" ;;
    esac
    [ $# -le 2 ] || mos_usage_error "unexpected argument: $3"
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) mos_usage_error "unexpected argument: $1" ;;
esac
[ "$mode" = hook ] || [ $# -le 1 ] || mos_usage_error "session-brief.sh takes at most one option"

root=$(mos_root)
today=$(mos_today)
cutoff30=$(mos_days_ago_iso 30 || true)

# Each bucket is a newline-separated list of pre-formatted lines. Built with
# plain string appends so the script stays bash 3.2 compatible (no arrays
# of arrays, no associative arrays).
waiting=""    # gates on the human's desk
blocked=""    # items with status blocked
active=""     # active items the agent can resume on its own
backlog=""    # items not started yet
kb_stale=""   # stale_after has passed
kb_drafts=""  # status draft for more than 30 days
kb_unverified="" # agent-authored, never human-verified

append() {
  # append <var-name> <line>
  local var="$1" line="$2"
  eval "$var=\"\${$var}\${$var:+
}\$line\""
}

count() {
  # count <text> — number of non-empty lines
  if [ -z "$1" ]; then
    printf '0\n'
  else
    printf '%s\n' "$1" | grep -c .
  fi
}

# --- Work items -------------------------------------------------------------
for state in active backlog; do
  dir="$root/work/$state"
  [ -d "$dir" ] || continue
  while IFS= read -r doc; do
    [ -n "$doc" ] || continue
    folder=$(dirname "$doc")
    id=$(basename "$folder")
    status=$(mos_frontmatter_field "$doc" status || true)
    title=$(mos_frontmatter_field "$doc" title || true)
    updated=$(mos_frontmatter_field "$doc" updated || true)
    line="$id — ${title:-untitled} [${status:-?}, updated ${updated:-?}]"
    case "$status" in
      plan-review | impl-review)
        gate_doc="$folder/02-plan.md"
        [ "$status" = "impl-review" ] && gate_doc="$folder/03-implementation-plan.md"
        gate_state=""
        [ -f "$gate_doc" ] && gate_state=$(mos_frontmatter_field "$gate_doc" status || true)
        if [ "$gate_state" = "in-review" ]; then
          append waiting "$line — approve or revise $(basename "$gate_doc")"
        else
          append active "$line"
        fi
        ;;
      delivering)
        append waiting "$line — confirm delivery (push + MR/PR)"
        ;;
      blocked)
        # Activity-log convention (WORKFLOW.md § States):
        #   - YYYY-MM-DD — blocked (was: <status>; unblock: <condition>)
        reason=$(grep -E -- '- [0-9]{4}-[0-9]{2}-[0-9]{2} — blocked' "$doc" 2>/dev/null | tail -1 || true)
        reason="${reason#*— blocked}"
        reason="${reason#"${reason%%[! :]*}"}"
        append blocked "$line${reason:+ — $reason}"
        ;;
      done | cancelled)
        # a finished item still sitting outside work/done/ — validate.sh
        # reports the folder/status mismatch; nothing to pick up here
        ;;
      *)
        if [ "$state" = backlog ]; then
          append backlog "$line"
        else
          append active "$line"
        fi
        ;;
    esac
  done < <(find "$dir" -type f \( -name task.md -o -name epic.md \) 2>/dev/null | LC_ALL=C sort)
done

# --- Knowledge base ---------------------------------------------------------
kb="$root/knowledge"
if [ -d "$kb" ]; then
  while IFS= read -r doc; do
    [ -n "$doc" ] || continue
    rel="${doc#"$root"/}"
    # only docs with frontmatter are knowledge docs; index.md files are not
    head -1 "$doc" 2>/dev/null | grep -q '^---[[:space:]]*$' || continue
    stale=$(mos_frontmatter_field "$doc" stale_after || true)
    status=$(mos_frontmatter_field "$doc" status || true)
    created=$(mos_frontmatter_field "$doc" created || true)
    generated_by=$(mos_frontmatter_field "$doc" generated_by || true)
    verified=$(mos_frontmatter_field "$doc" verified || true)

    case "$stale" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
        [[ "$stale" < "$today" ]] && append kb_stale "$rel — stale_after $stale passed; re-verify, then bump or deprecate"
        ;;
    esac

    if [ "$status" = draft ] && [ -n "$cutoff30" ]; then
      case "$created" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
          [[ "$created" < "$cutoff30" ]] && append kb_drafts "$rel — draft since $created; finish it or mark it stable"
          ;;
      esac
    fi

    if [ -n "$generated_by" ] && [ "$generated_by" != null ] &&
      { [ -z "$verified" ] || [ "$verified" = null ]; } &&
      [ "$status" != deprecated ]; then
      append kb_unverified "$rel — written by $generated_by, not yet human-verified"
    fi
  done < <(find "$kb" -type f -name '*.md' ! -name index.md ! -path "$kb/bundles/*" 2>/dev/null | LC_ALL=C sort)
fi

# --- Render -----------------------------------------------------------------
n_waiting=$(count "$waiting")
n_blocked=$(count "$blocked")
n_active=$(count "$active")
n_backlog=$(count "$backlog")
n_stale=$(count "$kb_stale")
n_drafts=$(count "$kb_drafts")
n_unverified=$(count "$kb_unverified")
n_open=$((n_waiting + n_blocked + n_active + n_backlog))
n_kb=$((n_stale + n_drafts + n_unverified))

section() {
  # section <heading> <lines> — print a heading and its bullet lines
  printf '%s\n' "$1"
  printf '%s\n' "$2" | sed 's/^/  - /'
}

brief=$(
  printf 'Session brief — %s\n\n' "$today"

  if [ "$n_open" -eq 0 ] && [ "$n_kb" -eq 0 ]; then
    printf 'Nothing to pick up: no open work items and the knowledge base is fresh.\n'
  else
    printf '== Open work (%s) ==\n' "$n_open"
    if [ "$n_open" -eq 0 ]; then
      printf '  (none)\n'
    else
      [ -n "$waiting" ] && section "Waiting on you:" "$waiting"
      [ -n "$blocked" ] && section "Blocked:" "$blocked"
      [ -n "$active" ] && section "In progress:" "$active"
      [ -n "$backlog" ] && section "Backlog:" "$backlog"
    fi

    printf '\n== Knowledge base maintenance (%s) ==\n' "$n_kb"
    if [ "$n_kb" -eq 0 ]; then
      printf '  (none — nothing stale, no old drafts, nothing awaiting review)\n'
    else
      [ -n "$kb_stale" ] && section "Stale (re-verify):" "$kb_stale"
      [ -n "$kb_drafts" ] && section "Old drafts (30+ days):" "$kb_drafts"
      [ -n "$kb_unverified" ] && section "Awaiting human review:" "$kb_unverified"
    fi

    printf '\n== Priorities ==\n'
    n=0
    if [ "$n_waiting" -gt 0 ]; then n=$((n + 1)); printf '  %s. Clear the %s gate(s) waiting on you.\n' "$n" "$n_waiting"; fi
    if [ "$n_blocked" -gt 0 ]; then n=$((n + 1)); printf '  %s. Unblock the %s blocked item(s).\n' "$n" "$n_blocked"; fi
    if [ "$n_active" -gt 0 ]; then n=$((n + 1)); printf '  %s. Resume the %s item(s) in progress.\n' "$n" "$n_active"; fi
    if [ "$n_stale" -gt 0 ]; then n=$((n + 1)); printf '  %s. Re-verify the %s stale knowledge doc(s) (kb-review runbook).\n' "$n" "$n_stale"; fi
    if [ "$n_drafts" -gt 0 ]; then n=$((n + 1)); printf '  %s. Finish or promote the %s old draft(s).\n' "$n" "$n_drafts"; fi
    if [ "$n_backlog" -gt 0 ]; then n=$((n + 1)); printf '  %s. Pick up the next backlog item (%s waiting).\n' "$n" "$n_backlog"; fi
    if [ "$n_unverified" -gt 0 ]; then n=$((n + 1)); printf '  %s. Review the %s agent-authored doc(s) and stamp verified:.\n' "$n" "$n_unverified"; fi
  fi

  printf '\nFull dashboard: scripts/status.sh\n'
)

if [ "$mode" = text ]; then
  printf '%s\n' "$brief"
  exit 0
fi

# --hook: session-start hook JSON. Escaped here rather than with jq so the
# hook has no dependency beyond bash + awk. Claude Code nests the context
# under hookSpecificOutput; Copilot CLI reads a top-level additionalContext.
preamble='Morpheus OS session brief (scripts/session-brief.sh, read-only). In your first reply, relay this brief to the human as-is — open work, knowledge-base maintenance due, and the priority list, or the fact that there is nothing to pick up — then continue with whatever they asked.'
escaped=$(printf '%s\n\n%s\n' "$preamble" "$brief" | awk '
BEGIN { ORS = "" }
{
  line = $0
  gsub(/\\/, "\\\\", line)
  gsub(/"/, "\\\"", line)
  gsub(/\t/, "\\t", line)
  gsub(/\r/, "\\r", line)
  if (NR > 1) print "\\n"
  print line
}
')
case "$client" in
  claude) printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$escaped" ;;
  copilot) printf '{"additionalContext":"%s"}\n' "$escaped" ;;
esac
