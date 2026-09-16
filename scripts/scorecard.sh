#!/usr/bin/env bash
# scorecard.sh — read-only: one TAB-separated row per work item from its run
# record (events.log, frontmatter, gate/review/verification docs, trace/),
# or a per-harness-version summary. Items without an events.log are parsed
# best-effort from their Activity prose and review docs and marked
# source=legacy. Never writes anything.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: scorecard.sh [<work-id | folder> ...] [--no-traces] [--summary]

Print the run record as data. Default: every work item under work/ (all
states, epic children included), TAB-separated with a header row, one row
per item. Empty cells are "-".

Columns:
  id type harness workspace_rev repos status created merged lead_h
  g1_rounds g1_conf_first g1_conf_final g1_by g1_caps g1_inherent
  g2_rounds g2_conf_first g2_conf_final g2_by g2_caps g2_inherent
  changes_requested blocked corrections feedback_rounds
  steps step_fails diff_verdict diff_findings verification
  delivered_mode mr reverted docs_missing
  briefs reports subagent_transcripts tool_calls tokens_in tokens_out source

  lead_h        hours from created to the merged event (1 decimal)
  docs_missing  comma list of: plan-review impl-review verification
                diff-review harness events — the gate docs / stamp / log the
                item's status requires but lacks (validate.sh's rules)
  items_with_gaps (--summary)  items whose status requires a gate doc (plan
                review, impl review, verification, diff review) they lack —
                the stamp and events log are listed per row but not counted
                here
  tool_calls, tokens_*  summed over trace/raw/*.jsonl and the session
                transcripts sessions.tsv points at that still exist; "-" when
                no file carries the data (Copilot has no token usage)
  source        events (from events.log) or legacy (Activity prose + review
                docs, best effort — first-round confidences are unknown)

Options:
  <work-id | folder> ...  only these items
  --no-traces             skip transcript scanning (cost columns become "-")
  --summary               one row per harness version instead: items,
                          auto_approve_rate, mean_g1_rounds, mean_g2_rounds,
                          changes_requested, blocked, corrections, reverted,
                          items_with_gaps, mean_lead_h
  -h, --help              show this help
EOF
}

traces=yes
summary=no
only=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-traces) traces=no ;;
    --summary) summary=yes ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*) mos_usage_error "unknown option: $1" ;;
    *) only="$only $1" ;;
  esac
  shift
done

root=$(mos_root)
HEADER='id	type	harness	workspace_rev	repos	status	created	merged	lead_h	g1_rounds	g1_conf_first	g1_conf_final	g1_by	g1_caps	g1_inherent	g2_rounds	g2_conf_first	g2_conf_final	g2_by	g2_caps	g2_inherent	changes_requested	blocked	corrections	feedback_rounds	steps	step_fails	diff_verdict	diff_findings	verification	delivered_mode	mr	reverted	docs_missing	briefs	reports	subagent_transcripts	tool_calls	tokens_in	tokens_out	source'

fm() { mos_frontmatter_field "$1" "$2" 2>/dev/null || true; }
dash() { [ -n "$1" ] && printf '%s' "$1" || printf -- '-'; }

# lead_hours <created> <merged> — hours between, 1 decimal; "-" when unknown.
lead_hours() {
  local a b
  a=$(mos_iso_to_epoch "$1" 2>/dev/null || true)
  b=$(mos_iso_to_epoch "$2" 2>/dev/null || true)
  if [ -n "$a" ] && [ -n "$b" ]; then
    awk -v a="$a" -v b="$b" 'BEGIN { printf "%.1f\n", (b - a) / 3600 }'
  else
    printf -- '-\n'
  fi
}

# count_files <dir> <glob> — number of matching files (0 when none).
count_files() {
  local n=0 f
  for f in "$1"/$2; do
    [ -f "$f" ] && n=$((n + 1))
  done
  printf '%s\n' "$n"
}

# trace_costs <folder> — "tool_calls\ttokens_in\ttokens_out" over raw/*.jsonl
# and the transcripts sessions.tsv points at. Copilot logs (copilot-* or a
# session-state/ path) use the "tool key marker; Claude JSONL "type":"tool_use".
trace_costs() {
  local dir="$1" f calls=0 tin=0 tout=0 any=no files="" marker c
  for f in "$dir"/trace/raw/*.jsonl; do [ -f "$f" ] && files="$files
$f"; done
  if [ -f "$dir/trace/sessions.tsv" ]; then
    while IFS='	' read -r _sid path _first _last; do
      [ -f "$path" ] && files="$files
$path"
    done < <(tail -n +2 "$dir/trace/sessions.tsv")
  fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    any=yes
    case "$f" in
      */copilot-*.jsonl | */session-state/*) marker='"tool' ;;
      *) marker='"type": ?"tool_use"' ;;
    esac
    c=$(grep -Ec -- "$marker" "$f" 2>/dev/null || true)
    calls=$((calls + ${c:-0}))
    # `|| true`: a transcript without usage data makes grep exit 1, and under
    # `set -o pipefail` that becomes the assignment's status — fatal under
    # `set -e` on shells that apply errexit inside command substitutions.
    c=$(grep -oE '"input_tokens": ?[0-9]+' "$f" 2>/dev/null | awk -F'[: ]+' '{ s += $NF } END { print s + 0 }' || true)
    tin=$((tin + ${c:-0}))
    c=$(grep -oE '"output_tokens": ?[0-9]+' "$f" 2>/dev/null | awk -F'[: ]+' '{ s += $NF } END { print s + 0 }' || true)
    tout=$((tout + ${c:-0}))
  done <<EOF
$files
EOF
  if [ "$any" = yes ]; then
    printf '%s\t%s\t%s\n' "$calls" "$([ "$tin" -gt 0 ] && printf '%s' "$tin" || printf -- '-')" "$([ "$tout" -gt 0 ] && printf '%s' "$tout" || printf -- '-')"
  else
    printf -- '-\t-\t-\n'
  fi
}

# events_metrics <events.log> — one "name=value" per line for the event-derived columns.
events_metrics() {
  awk -F'\t' '
function get(k,   i, p) { for (i = 3; i <= NF; i++) { p = index($i, "="); if (substr($i, 1, p - 1) == k) return substr($i, p + 1) } return "" }
$2 == "gate-review" { g = get("gate"); R[g]++; if (F[g] == "") F[g] = get("confidence"); L[g] = get("confidence"); if (get("barred") == "yes") C[g]++; if (get("inherent") == "yes") I[g] = "yes" }
$2 == "gate-approved" { B[get("gate")] = get("by") }
$2 == "changes-requested" { cr++ }
$2 == "blocked" { bl++ }
$2 == "correction" { co++ }
$2 == "feedback" { fb++ }
$2 == "step" { st++; if (get("result") == "fail") sf++ }
$2 == "diff-review" { dv = get("verdict"); df = get("findings") }
$2 == "verification" { vf = get("verdict") }
$2 == "delivered" { dm = get("mode"); mr = get("mr") }
$2 == "merged" { merged = $1; if (mr == "") mr = get("mr") }
$2 == "reverted" { rv = "yes" }
END {
  printf "g1_rounds=%s\ng1_conf_first=%s\ng1_conf_final=%s\ng1_by=%s\ng1_caps=%s\ng1_inherent=%s\n", R[1] + 0, F[1], L[1], B[1], C[1] + 0, I[1]
  printf "g2_rounds=%s\ng2_conf_first=%s\ng2_conf_final=%s\ng2_by=%s\ng2_caps=%s\ng2_inherent=%s\n", R[2] + 0, F[2], L[2], B[2], C[2] + 0, I[2]
  printf "changes_requested=%s\nblocked=%s\ncorrections=%s\nfeedback_rounds=%s\nsteps=%s\nstep_fails=%s\n", cr + 0, bl + 0, co + 0, fb + 0, st + 0, sf + 0
  printf "diff_verdict=%s\ndiff_findings=%s\nverification=%s\ndelivered_mode=%s\nmr=%s\nmerged=%s\nreverted=%s\n", dv, df, vf, dm, mr, merged, rv
}' "$1"
}

# legacy_caps <review-doc> — 1 when auto_approval_barred: yes, 0 when the doc
# exists without it, empty when the doc is missing.
legacy_caps() {
  if [ "$(fm "$1" auto_approval_barred)" = yes ]; then printf 1
  elif [ -f "$1" ]; then printf 0
  fi
}

# legacy_metrics <folder> <doc> — same names, best effort from review docs + Activity prose.
legacy_metrics() {
  local dir="$1" doc="$2" rd by
  rd="$dir/02-plan-review.md"
  printf 'g1_rounds=%s\ng1_conf_first=%s\ng1_conf_final=%s\n' "$(fm "$rd" review_round)" "$([ "$(fm "$rd" review_round)" = 1 ] && fm "$rd" confidence)" "$(fm "$rd" confidence)"
  by=$(fm "$dir/02-plan.md" approved_by)
  case "$by" in *human*) by=human ;; *plan-reviewer*) by=auto ;; *) by="" ;; esac
  printf 'g1_by=%s\ng1_caps=%s\ng1_inherent=%s\n' "$by" "$(legacy_caps "$rd")" "$(fm "$rd" inherent_cap)"
  rd="$dir/03-implementation-plan-review.md"
  printf 'g2_rounds=%s\ng2_conf_first=%s\ng2_conf_final=%s\n' "$(fm "$rd" review_round)" "$([ "$(fm "$rd" review_round)" = 1 ] && fm "$rd" confidence)" "$(fm "$rd" confidence)"
  by=$(fm "$dir/03-implementation-plan.md" approved_by)
  case "$by" in *human*) by=human ;; *plan-reviewer*) by=auto ;; *) by="" ;; esac
  printf 'g2_by=%s\ng2_caps=%s\ng2_inherent=%s\n' "$by" "$(legacy_caps "$rd")" "$(fm "$rd" inherent_cap)"
  printf 'changes_requested=%s\n' "$(grep -ciE 'changes.requested' "$doc" || true)"
  printf 'blocked=%s\n' "$(grep -cE -- '— blocked' "$doc" || true)"
  printf 'corrections=\nsteps=\nstep_fails=\ndiff_findings=\n'
  printf 'feedback_rounds=%s\n' "$(grep -ciE -- '— reopened' "$doc" || true)"
  printf 'diff_verdict=%s\n' "$(fm "$dir/04-diff-review.md" verdict)"
  printf 'verification=%s\n' "$(fm "$dir/04-verification.md" status | grep -x complete || true)"
  if grep -qiE 'delivery auto-approved' "$doc"; then printf 'delivered_mode=auto\n'
  elif grep -qiE 'delivery approved' "$doc"; then printf 'delivered_mode=human\n'
  else printf 'delivered_mode=\n'; fi
  printf 'mr=%s\n' "$(fm "$doc" mr | awk '{ print $1 }' | grep -v '^null$' || true)"
  printf 'merged=%s\n' "$(grep -E -- '^- [0-9]{4}-[0-9]{2}-[0-9]{2} — .*merged' "$doc" | head -1 | sed -E 's/^- ([0-9-]+) .*/\1/' || true)"
  printf 'reverted=%s\n' "$(grep -qiE 'revert' "$doc" && printf yes || true)"
}

# docs_missing <folder> <status> <harness> <instrumented> — comma list or "-".
docs_missing() {
  local dir="$1" status="$2" harness="$3" instrumented="$4" rank miss=""
  rank=$(mos_status_rank "$status")
  [ "$status" = cancelled ] && rank=0
  if [ "$rank" -ge 5 ] && { [ "$(fm "$dir/02-plan.md" status)" != approved ] || [ ! -f "$dir/02-plan-review.md" ]; }; then miss="$miss,plan-review"; fi
  # feedback: phases/07-feedback.md step 5 puts the implementation plan back
  # at status: in-review for the gate-2 revisit — both documents must exist,
  # but the plan is legitimately unapproved until the human re-approves it.
  if [ "$rank" -ge 7 ] && [ -f "$dir/task.md" ]; then
    if [ "$status" = feedback ]; then
      { [ -f "$dir/03-implementation-plan.md" ] && [ -f "$dir/03-implementation-plan-review.md" ]; } || miss="$miss,impl-review"
    elif [ "$(fm "$dir/03-implementation-plan.md" status)" != approved ] || [ ! -f "$dir/03-implementation-plan-review.md" ]; then
      miss="$miss,impl-review"
    fi
  fi
  if [ "$rank" -ge 9 ] && [ -f "$dir/task.md" ] && [ "$(fm "$dir/04-verification.md" status)" != complete ]; then miss="$miss,verification"; fi
  if [ "$rank" -ge 9 ] && [ -f "$dir/task.md" ] && [ "$(fm "$dir/04-diff-review.md" verdict)" != PASS ]; then miss="$miss,diff-review"; fi
  [ -n "$harness" ] || miss="$miss,harness"
  [ "$instrumented" = yes ] || miss="$miss,events"
  miss=${miss#,}
  dash "$miss"
}

row_for() {
  local dir="$1" doc id type harness wsrev repos status created instrumented metrics m
  local g1_rounds g1_conf_first g1_conf_final g1_by g1_caps g1_inherent g2_rounds g2_conf_first g2_conf_final g2_by g2_caps g2_inherent
  local changes_requested blocked corrections feedback_rounds steps step_fails diff_verdict diff_findings verification delivered_mode mr merged reverted
  local briefs reports subs costs source lead
  doc=$(mos_work_item_doc "$dir")
  id=$(fm "$doc" id); type=$(fm "$doc" type); harness=$(fm "$doc" harness); wsrev=$(fm "$doc" workspace_rev)
  repos=$(fm "$doc" repos | tr -d '[] ' ); status=$(fm "$doc" status); created=$(fm "$doc" created)
  instrumented=no
  # -f, not -s: an empty events.log is still an instrumented item (validate.sh
  # decides the same way).
  [ -f "$dir/events.log" ] && instrumented=yes
  if [ "$instrumented" = yes ]; then metrics=$(events_metrics "$dir/events.log"); source=events
  else metrics=$(legacy_metrics "$dir" "$doc"); source=legacy; fi
  # load name=value lines into like-named shell variables (names are fixed above)
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    case "${m%%=*}" in
      g1_rounds | g1_conf_first | g1_conf_final | g1_by | g1_caps | g1_inherent | g2_rounds | g2_conf_first | g2_conf_final | g2_by | g2_caps | g2_inherent | changes_requested | blocked | corrections | feedback_rounds | steps | step_fails | diff_verdict | diff_findings | verification | delivered_mode | mr | merged | reverted)
        eval "${m%%=*}=\"\${m#*=}\""
        ;;
    esac
  done <<EOF
$metrics
EOF
  [ -n "${mr:-}" ] || mr=$(fm "$doc" mr | awk '{ print $1 }' | grep -v '^null$' || true)
  lead=$(lead_hours "$created" "${merged:-}")
  briefs=$(count_files "$dir/trace/briefs" '*.md')
  reports=$(count_files "$dir/trace/reports" '*.md')
  subs=$(count_files "$dir/trace/raw" '*.jsonl')
  if [ "$traces" = yes ]; then costs=$(trace_costs "$dir"); else costs='-	-	-'; fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t' "$(dash "$id")" "$(dash "$type")" "$(dash "$harness")" "$(dash "$wsrev")" "$(dash "$repos")" "$(dash "$status")" "$(dash "$created")" "$(dash "${merged:-}")" "$lead"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t' "$(dash "${g1_rounds:-}")" "$(dash "${g1_conf_first:-}")" "$(dash "${g1_conf_final:-}")" "$(dash "${g1_by:-}")" "$(dash "${g1_caps:-}")" "$(dash "${g1_inherent:-}")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t' "$(dash "${g2_rounds:-}")" "$(dash "${g2_conf_first:-}")" "$(dash "${g2_conf_final:-}")" "$(dash "${g2_by:-}")" "$(dash "${g2_caps:-}")" "$(dash "${g2_inherent:-}")"
  printf '%s\t%s\t%s\t%s\t' "$(dash "${changes_requested:-}")" "$(dash "${blocked:-}")" "$(dash "${corrections:-}")" "$(dash "${feedback_rounds:-}")"
  printf '%s\t%s\t%s\t%s\t%s\t' "$(dash "${steps:-}")" "$(dash "${step_fails:-}")" "$(dash "${diff_verdict:-}")" "$(dash "${diff_findings:-}")" "$(dash "${verification:-}")"
  printf '%s\t%s\t%s\t%s\t' "$(dash "${delivered_mode:-}")" "$(dash "${mr:-}")" "$(dash "${reverted:-}")" "$(docs_missing "$dir" "$status" "$harness" "$instrumented")"
  printf '%s\t%s\t%s\t%s\t%s\n' "$briefs" "$reports" "$subs" "$costs" "$source"
}

rows() {
  local dir
  if [ -n "$only" ]; then
    for t in $only; do
      dir=$(mos_work_item_dir "$t")
      row_for "$dir"
    done
  else
    [ -d "$root/work" ] || return 0
    while IFS= read -r doc; do
      [ -n "$doc" ] || continue
      row_for "$(dirname "$doc")"
    done < <(find "$root/work" -type f \( -name task.md -o -name epic.md \) ! -path "$root/work/.trace-unassigned/*" | LC_ALL=C sort)
  fi
}

if [ "$summary" = no ]; then
  printf '%s\n' "$HEADER"
  rows
  exit 0
fi
# --summary: aggregate the rows by harness version.
printf 'harness\titems\tauto_approve_rate\tmean_g1_rounds\tmean_g2_rounds\tchanges_requested\tblocked\tcorrections\treverted\titems_with_gaps\tmean_lead_h\n'
# Column indices below follow HEADER (1-based): 3 harness, 9 lead_h, 10 g1_rounds,
# 13 g1_by, 16 g2_rounds, 19 g2_by, 22 changes_requested, 23 blocked, 24 corrections,
# 33 reverted, 34 docs_missing — keep in sync when HEADER changes.
rows | awk -F'\t' '
function num(v) { return (v ~ /^-?[0-9.]+$/) ? v + 0 : 0 }
function isnum(v) { return v ~ /^-?[0-9.]+$/ }
{
  h = $3; n[h]++
  if ($13 != "-") { appr[h]++; if ($13 == "auto") auto[h]++ }
  if ($19 != "-") { appr[h]++; if ($19 == "auto") auto[h]++ }
  if (isnum($10)) { g1[h] += $10; g1n[h]++ }
  if (isnum($16)) { g2[h] += $16; g2n[h]++ }
  cr[h] += num($22); bl[h] += num($23); co[h] += num($24)
  if ($33 == "yes") rv[h]++
  if ($34 ~ /(plan-review|impl-review|verification|diff-review)/) gaps[h]++
  if (isnum($9)) { lead[h] += $9; leadn[h]++ }
}
END {
  for (h in n) {
    printf "%s\t%d\t%s\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%s\n", h, n[h],
      (appr[h] ? sprintf("%.2f", auto[h] / appr[h]) : "-"),
      (g1n[h] ? sprintf("%.1f", g1[h] / g1n[h]) : "-"),
      (g2n[h] ? sprintf("%.1f", g2[h] / g2n[h]) : "-"),
      cr[h], bl[h], co[h], rv[h] + 0, gaps[h] + 0,
      (leadn[h] ? sprintf("%.1f", lead[h] / leadn[h]) : "-")
  }
}' |
  # Order by harness version, not by string: build a zero-padded sort key from
  # the semver part (like scripts/session-brief.sh does), sort, strip it again.
  # Rows whose harness is not a semver ("-", legacy items) sort last.
  awk -F'	' '{ v = $1; sub(/\+.*/, "", v); if (v ~ /^[0-9]+\.[0-9]+\.[0-9]+$/) { split(v, p, "."); printf "%05d%05d%05d	%s\n", p[1], p[2], p[3], $0 } else printf "99999999999999	%s\n", $0 }' |
  LC_ALL=C sort | cut -f2-
