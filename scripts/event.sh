#!/usr/bin/env bash
# event.sh — record one work-item event: append a TAB-separated line to the
# item's events.log, append the dated prose line to its ## Activity section,
# apply the event's status effect (status: field), and bump updated:. The
# ONLY sanctioned way to change a work item's status (AGENTS.md § 2).
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: event.sh <work-id | folder> <event> [key=value ...] [-- "<prose>"]

Record an event on a work item. All-or-nothing: on any validation error
nothing is written and the exit status is 1.

Events and their required keys (optional keys in brackets; the status
effect is what event.sh also writes to the doc's status: field):

  created                                       -
  status             from to                    status := to
  gate-review        gate round confidence barred inherent review
  gate-approved      gate by confidence         (by: human | auto)
  changes-requested  gate by
  blocked            was unblock                status := blocked
  unblocked          [to]                       status := to, or the was of the last blocked event
  step               step result attempts [repo agent]   (result: pass | fail)
  diff-review        repo verdict findings      (verdict: PASS | FAIL)
  verification       gates verdict              (gates: <passed>/<total>)
  delivered          mode mr                    status := awaiting-merge  (mode: human | auto)
  merged             mr                         status := done
  closed-unmerged    mr
  feedback           round reason               status := feedback  (reason: mr | human)
  reverted           mr [by]
  correction         what
  harvest            new updated
  cancelled          reason                     status := cancelled

Values may contain spaces (quote the argument) but never a TAB or newline.
When -- "<prose>" is omitted, a prose line is generated from the fields.

Options:
  -h, --help   show this help
EOF
}

# --- vocabulary (scripts/lib.sh mos_event_vocab) ---------------------------
VOCAB=$(mos_event_vocab)

vocab_row() {
  printf '%s\n' "$VOCAB" | awk -F'|' -v e="$1" '$1 == e { print; found = 1 } END { exit (found ? 0 : 1) }'
}

# --- arguments ---------------------------------------------------------------
[ $# -ge 1 ] || mos_usage_error "missing <work-id | folder>"
case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
esac
[ $# -ge 2 ] || mos_usage_error "missing <event>"
target="$1"
event="$2"
shift 2

prose=""
have_prose=no
kv=""       # newline-separated key=value pairs, validated below
keys=""     # space-separated keys seen
nl=$(printf '\n.'); nl=${nl%.}
while [ $# -gt 0 ]; do
  if [ "$1" = -- ]; then
    shift
    [ $# -eq 1 ] || mos_usage_error "-- must be followed by exactly one prose argument"
    prose="$1"
    have_prose=yes
    break
  fi
  case "$1" in
    *=*) : ;;
    *) mos_usage_error "expected key=value, got '$1'" ;;
  esac
  k=${1%%=*}
  v=${1#*=}
  case "$k" in
    [a-z]*) : ;;
    *) mos_usage_error "bad key '$k' — keys are [a-z][a-z0-9_-]*" ;;
  esac
  case "$k" in *[!a-z0-9_-]*) mos_usage_error "bad key '$k' — keys are [a-z][a-z0-9_-]*" ;; esac
  case "$v" in
    *'	'*) mos_die "value for '$k' contains a TAB" ;;
  esac
  case "$v" in *"$nl"*) mos_die "value for '$k' contains a newline" ;; esac
  case " $keys " in *" $k "*) mos_die "key '$k' given twice" ;; esac
  keys="$keys $k"
  kv="${kv}${kv:+$nl}$k=$v"
  shift
done
[ "$have_prose" = yes ] || [ $# -eq 0 ] || mos_usage_error "unexpected arguments after key=value pairs"
case "$prose" in
  *'	'*) mos_die "prose contains a TAB" ;;
esac
case "$prose" in *"$nl"*) mos_die "prose contains a newline" ;; esac

row=$(vocab_row "$event") || mos_die "unknown event '$event' — see event.sh --help for the vocabulary"
required=$(printf '%s' "$row" | cut -d'|' -f2)
optional=$(printf '%s' "$row" | cut -d'|' -f3)
effect=$(printf '%s' "$row" | cut -d'|' -f4)

for k in $required; do
  case " $keys " in
    *" $k "*) : ;;
    *) mos_die "event '$event': missing required key '$k' (required: $required)" ;;
  esac
done
for k in $keys; do
  case " $required $optional " in
    *" $k "*) : ;;
    *) mos_die "event '$event': unknown key '$k' (allowed: $required${optional:+ $optional})" ;;
  esac
done

# val <key> — value of a given key from kv (empty when absent).
val() {
  printf '%s\n' "$kv" | awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); print; exit }'
}

# --- value constraints -------------------------------------------------------
statuses=$(mos_statuses)
legal_status() {
  case " $statuses " in *" $1 "*) return 0 ;; esac
  return 1
}
one_of() { # one_of <key> <allowed...>
  local k="$1" v; shift
  v=$(val "$k")
  case " $* " in *" $v "*) return 0 ;; esac
  mos_die "event '$event': $k must be one of: $* (got '$v')"
}
for k in from to was; do
  case " $keys " in *" $k "*)
    v=$(val "$k")
    legal_status "$v" || mos_die "event '$event': $k '$v' is not a legal status ($statuses)"
    ;;
  esac
done
case "$event" in
  gate-review) one_of gate 1 2; one_of barred yes no; one_of inherent yes no ;;
  gate-approved) one_of gate 1 2; one_of by human auto ;;
  changes-requested) one_of gate 1 2; one_of by human auto ;;
  step) one_of result pass fail ;;
  diff-review) one_of verdict PASS FAIL ;;
  verification) one_of verdict PASS FAIL ;;
  delivered) one_of mode human auto ;;
  feedback) one_of reason mr human ;;
esac

# --- locate the item -----------------------------------------------------------
dir=$(mos_work_item_dir "$target")
doc=$(mos_work_item_doc "$dir")
log="$dir/events.log"
root=$(mos_root)

# --- from=/was= must match the item's actual current status --------------------
current=$(mos_frontmatter_field "$doc" status || true)
case "$event" in
  status)
    from=$(val from)
    [ "$from" = "$current" ] ||
      mos_die "event 'status': from='$from' does not match the item's current status '$current' — record what actually happened"
    ;;
  blocked)
    was=$(val was)
    [ "$was" = "$current" ] ||
      mos_die "event 'blocked': was='$was' does not match the item's current status '$current' — record what actually happened"
    ;;
esac

# --- status effect -------------------------------------------------------------
new_status=""
case "$effect" in
  -) : ;;
  =to) new_status=$(val to) ;;
  unblocked)
    new_status=$(val to)
    if [ -z "$new_status" ]; then
      [ -f "$log" ] || mos_die "unblocked: no events.log to read the last blocked event from — pass to=<status>"
      new_status=$(awk -F'\t' '$2 == "blocked" { for (i = 3; i <= NF; i++) if ($i ~ /^was=/) { sub(/^was=/, "", $i); w = $i } } END { print w }' "$log")
      [ -n "$new_status" ] || mos_die "unblocked: no earlier blocked event with was= in $log — pass to=<status>"
      legal_status "$new_status" || mos_die "unblocked: recorded was '$new_status' is not a legal status"
    fi
    ;;
  *) new_status="$effect" ;;
esac

# --- prose ---------------------------------------------------------------------
if [ "$have_prose" = no ]; then
  case "$event" in
    created) prose="created" ;;
    status) prose="status → $(val to)" ;;
    gate-review)
      caps="no caps"
      [ "$(val barred)" = yes ] && caps="hard cap fired"
      [ "$(val inherent)" = yes ] && caps="inherent hard cap"
      prose="gate $(val gate) review round $(val round): confidence $(val confidence) ($caps)"
      ;;
    gate-approved) prose="gate $(val gate) approved by $(val by) (confidence $(val confidence))" ;;
    changes-requested) prose="gate $(val gate): changes requested by $(val by)" ;;
    blocked) prose="blocked (was: $(val was); unblock: $(val unblock))" ;;
    unblocked) prose="unblocked, resuming $new_status" ;;
    step) prose="step $(val step) $(val result) after $(val attempts) attempt(s)" ;;
    diff-review) prose="diff review $(val repo): $(val verdict), $(val findings) finding(s)" ;;
    verification) prose="verification $(val verdict): gates $(val gates)" ;;
    delivered) prose="delivery approved ($(val mode)), MR created: $(val mr); awaiting merge" ;;
    merged) prose="MR merged, closed: $(val mr)" ;;
    closed-unmerged) prose="MR closed without merging: $(val mr)" ;;
    feedback) prose="reopened: $(val reason) feedback (round $(val round))" ;;
    reverted) prose="reverted after merge by $(val mr)" ;;
    correction) prose="human correction: $(val what)" ;;
    harvest) prose="KB harvest: $(val new) new, $(val updated) updated" ;;
    cancelled) prose="cancelled: $(val reason)" ;;
  esac
fi

# --- write (temp copies, then mv) ----------------------------------------------
ts=$(mos_now_iso)
today=$(mos_today)
line="$ts	$event"
if [ -n "$kv" ]; then
  line="$line	$(printf '%s\n' "$kv" | paste -sd '	' -)"
fi
activity="- $today — $prose"

tmp_doc="$doc.tmp.$$"
tmp_log="$log.tmp.$$"
trap 'rm -f "$tmp_doc" "$tmp_log"' EXIT

# Activity: append the line at the end of the ## Activity section (before
# any trailing blank lines / the next ## heading); create the section at the
# end of the doc when it is missing. newline is passed via the environment
# (not -v) so backslash sequences in the prose (\n, \t, ...) are not
# escape-processed by awk's -v assignment.
newline="$activity" awk '
function flush(at_eof,    i, last) {
  last = n
  while (last > 0 && buf[last] ~ /^[ \t\r]*$/) last--
  if (last == 0) print ""            # empty section: one blank between heading and first entry
  for (i = 1; i <= last; i++) print buf[i]
  print newline
  if (!at_eof) for (i = last + 1; i <= n; i++) print buf[i]
  n = 0
  done = 1
}
BEGIN { newline = ENVIRON["newline"] }
/^## / {
  if (inact && !done) flush(0)
  inact = ($0 ~ /^## Activity[ \t\r]*$/)
  if (inact) { seen = 1; print; next }   # heading printed, never buffered
}
{ if (inact) buf[++n] = $0; else print }
END {
  if (inact && !done) flush(1)
  if (!seen) { print ""; print "## Activity"; print ""; print newline }
}
' "$doc" >"$tmp_doc"
mv "$tmp_doc" "$doc"

[ -z "$new_status" ] || mos_frontmatter_set "$doc" status "$new_status"
mos_frontmatter_set "$doc" updated "$today"

if [ -f "$log" ]; then cat "$log" >"$tmp_log"; else : >"$tmp_log"; fi
printf '%s\n' "$line" >>"$tmp_log"
mv "$tmp_log" "$log"
trap - EXIT

printf '%s: %s%s\n' "${dir#"$root"/}" "$event" "${new_status:+ (status → $new_status)}"
