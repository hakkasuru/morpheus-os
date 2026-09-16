#!/usr/bin/env bash
# validate.sh — structural checks over work/ and knowledge/.
# Errors exit 1; warnings go to stderr and do not change the exit code.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: validate.sh

Check the workspace for structural mistakes:
  work/**/{task,epic}.md   frontmatter present and complete, id matches its
                           folder, status is legal, folder and status agree,
                           phase docs exist only when the status allows them
  knowledge/**/*.md        frontmatter present with a legal type: and
                           status:, no unsubstituted {{DATE}} placeholders,
                           verified: is a date when set

Errors print to stderr and exit 1. Warnings print to stderr and exit 0.
Missing or empty work/ and knowledge/ trees are fine.

Options:
  -h, --help   show this help
  --harness    template self-check instead of the workspace: VERSION is
               semver and matches the newest CHANGELOG heading, every
               script parses (bash -n), shellcheck when installed, and an
               end-to-end smoke of new-work/stamp/event/trace-capture/
               scorecard/export-experience in a throwaway copy.
EOF
}

mode=workspace
case "${1:-}" in
  '') : ;;
  --harness) mode=harness ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) mos_usage_error "unexpected argument: $1" ;;
esac
[ $# -le 1 ] || mos_usage_error "validate.sh takes at most one option"

# The fourteen legal work-item statuses — see workflow/WORKFLOW.md.
STATUSES=$(mos_statuses)
WORK_TYPES="task story epic"
KB_TYPES="Note Decision Runbook Reference"
# The three legal knowledge-doc statuses — see knowledge/decisions/adopt-okf-lite-kb.md.
KB_STATUSES="draft stable deprecated"
WORK_FIELDS="id type title status created updated"

errors=0
checks=0
kb_dirs_seen=""

v_error() {
  printf 'error: %s\n' "$*" >&2
  errors=$((errors + 1))
}

v_warn() {
  printf 'warning: %s\n' "$*" >&2
}

# check — count one assertion.
check() {
  checks=$((checks + 1))
}

# in_set <needle> "<space separated set>"
in_set() {
  case " $2 " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

# is_epic_child_folder <folder-relative-to-root> — true when the folder sits
# nested inside an epic folder (a segment starting with "E-" between
# work/<state>/ and the item), e.g. work/active/E-.../T-.../. Per
# workflow/WORKFLOW.md § States, epic children live inside their epic's
# folder for their whole lifecycle — the folder<->status agreement rules
# apply only to top-level items (standalone work items, and epics
# themselves), so callers skip that check for these.
is_epic_child_folder() {
  case "$1" in
    work/backlog/E-*/* | work/active/E-*/* | work/done/E-*/*) return 0 ;;
  esac
  return 1
}

# is_iso_date <value> — true for YYYY-MM-DD (rejects "", "null", quotes).
is_iso_date() {
  case "${1:-}" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) return 0 ;;
  esac
  return 1
}

# conf_report <instrumented yes|no> <msg> — gate-consistency severity rule:
# an item with an events.log ran under the run-record rules → error; an
# older item → warning (its gaps are data, not debt — never backfill docs).
conf_report() {
  if [ "$1" = yes ]; then v_error "$2"; else v_warn "$2"; fi
}

# gate_approved <doc> — true when status approved with approver and date.
gate_approved() {
  [ -f "$1" ] || return 1
  [ "$(field "$1" status)" = approved ] || return 1
  local by at
  by=$(field "$1" approved_by)
  at=$(field "$1" approved_at)
  [ -n "$by" ] && [ "$by" != null ] && is_iso_date "$at"
}

# The event vocabulary (scripts/lib.sh mos_event_vocab) — checks events.log lines.
EVENTS=$(mos_event_names)

# has_frontmatter <file> — first line "---" and a closing "---".
has_frontmatter() {
  awk '
    { line = $0; sub(/\r$/, "", line); sub(/[ \t]+$/, "", line) }
    NR == 1 { if (line != "---") exit 1; next }
    line == "---" { ok = 1; exit 0 }
    END { exit (ok ? 0 : 1) }
  ' "$1"
}

# field <file> <name> — frontmatter scalar or empty.
field() {
  mos_frontmatter_field "$1" "$2" || true
}

# rel <path> — path relative to the workspace root, for readable messages.
rel() {
  printf '%s' "${1#"${root:-$(mos_root)}"/}"
}

validate_work_doc() {
  local file="$1" folder base doc where wtype status id f repos_val
  folder=$(dirname "$file")
  base=$(basename "$folder")
  doc=$(basename "$file")
  where=$(rel "$file")

  check
  if ! has_frontmatter "$file"; then
    v_error "$where: no YAML frontmatter — needs '---' as the first line and a closing '---'"
    return 0
  fi

  for f in $WORK_FIELDS; do
    check
    if [ -z "$(field "$file" "$f")" ]; then
      v_error "$where: required frontmatter field '$f' is missing or empty"
    fi
  done

  id=$(field "$file" id)
  wtype=$(field "$file" type)
  status=$(field "$file" status)

  check
  if [ -n "$id" ] && [ "$id" != "$base" ]; then
    v_error "$where: id '$id' does not match its folder name '$base' — rename one of them"
  fi

  check
  if [ -n "$wtype" ] && ! in_set "$wtype" "$WORK_TYPES"; then
    v_error "$where: type '$wtype' is not one of: $WORK_TYPES"
  fi

  check
  if [ -n "$status" ] && ! in_set "$status" "$STATUSES"; then
    v_error "$where: status '$status' is not one of: $STATUSES"
  fi

  # Folder (coarse state) must agree with status (phase). Top-level items
  # only — an epic child keeps whatever status it likes in place, see
  # is_epic_child_folder above.
  # Skipped when status is empty — that is already reported above.
  check
  if [ -n "$status" ] && ! is_epic_child_folder "$(rel "$folder")"; then
    case "$(rel "$folder")" in
      work/done/*)
        if ! in_set "$status" "done cancelled"; then
          v_error "$where: status '$status' under work/done/ — move it back to work/active/ or set status done|cancelled"
        fi
        ;;
      work/backlog/*)
        if [ "$status" != "intake" ]; then
          v_error "$where: status '$status' under work/backlog/ — move it to work/active/ or set status intake"
        fi
        ;;
      work/active/*)
        if in_set "$status" "done cancelled intake"; then
          v_warn "$where: status '$status' under work/active/ — expected a phase between context and awaiting-merge (or feedback/blocked)"
        fi
        ;;
    esac
  fi

  # --- run record: stamp, events.log, gate consistency ----------------------
  local instrumented=no harness rank last_status_event ev_errors
  [ -f "$folder/events.log" ] && instrumented=yes

  check
  harness=$(field "$file" harness)
  if [ -z "$harness" ]; then
    conf_report "$instrumented" "$where: no harness: stamp — run scripts/stamp.sh $(basename "$folder") (or --backfill for every unstamped item)"
  elif ! printf '%s' "$harness" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\+([0-9a-f]{7,40}|unknown)$'; then
    v_error "$where: harness '$harness' is not <MAJOR.MINOR.PATCH>+<commit|unknown>"
  fi
  check
  if [ -z "$(field "$file" workspace_rev)" ]; then
    conf_report "$instrumented" "$where: no workspace_rev: field — run scripts/stamp.sh $(basename "$folder")"
  fi

  if [ "$instrumented" = yes ]; then
    check
    ev_errors=$(awk -F'\t' -v events=" $EVENTS " '
NF < 2 { printf "line %d: fewer than 2 TAB-separated fields\n", NR; next }
$1 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/ { printf "line %d: bad timestamp \047%s\047\n", NR, $1 }
index(events, " " $2 " ") == 0 { printf "line %d: unknown event \047%s\047\n", NR, $2 }
{ for (i = 3; i <= NF; i++) if ($i !~ /^[a-z][a-z0-9_-]*=/) printf "line %d: field \047%s\047 is not key=value\n", NR, $i }
' "$folder/events.log")
    if [ -n "$ev_errors" ]; then
      while IFS= read -r e; do
        [ -n "$e" ] || continue
        v_error "$where: events.log $e (scripts/event.sh writes well-formed lines — never edit the log by hand)"
      done <<EOF
$ev_errors
EOF
    fi
    # The last status-affecting event must agree with status:.
    check
    last_status_event=$(awk -F'\t' '
$2 == "blocked" { s = "blocked"; for (i = 3; i <= NF; i++) if ($i ~ /^was=/) { w = $i; sub(/^was=/, "", w) } }
$2 == "status" { for (i = 3; i <= NF; i++) if ($i ~ /^to=/) { s = $i; sub(/^to=/, "", s) } }
$2 == "unblocked" { t = ""; for (i = 3; i <= NF; i++) if ($i ~ /^to=/) { t = $i; sub(/^to=/, "", t) }; s = (t != "" ? t : w) }
$2 == "delivered" { s = "awaiting-merge" }
$2 == "merged" { s = "done" }
$2 == "feedback" { s = "feedback" }
$2 == "cancelled" { s = "cancelled" }
END { print s }' "$folder/events.log")
    if [ -n "$last_status_event" ] && [ -n "$status" ] && [ "$last_status_event" != "$status" ]; then
      v_error "$where: status is '$status' but the last status event in events.log says '$last_status_event' — change status only through scripts/event.sh"
    fi
  fi

  if [ -n "$status" ] && [ "$status" != cancelled ]; then
    rank=$(mos_status_rank "$status")
    # Gate 1: from impl-planning on (feedback/awaiting-merge/done included).
    if [ "$rank" -ge 5 ]; then
      check
      gate_approved "$folder/02-plan.md" ||
        conf_report "$instrumented" "$where: status '$status' is past gate 1 but 02-plan.md is not approved (status: approved + approved_by + approved_at)"
      check
      [ -f "$folder/02-plan-review.md" ] ||
        conf_report "$instrumented" "$where: status '$status' is past gate 1 but 02-plan-review.md is missing — the gate dispatches a plan-review subagent (WORKFLOW.md § Review gates)"
    fi
  fi

  if [ "$doc" = "epic.md" ]; then
    # Roll-up: the epic's status reflects its furthest-behind child.
    check
    local child_doc child_status child_rank min_rank=99 min_status=""
    while IFS= read -r child_doc; do
      [ -n "$child_doc" ] || continue
      child_status=$(field "$child_doc" status)
      in_set "$child_status" "done cancelled" && continue
      child_rank=$(mos_status_rank "$child_status")
      [ "$child_rank" -gt 0 ] || continue
      if [ "$child_rank" -lt "$min_rank" ]; then min_rank=$child_rank; min_status=$child_status; fi
    done < <(find "$folder" -mindepth 2 -maxdepth 2 -type f -name task.md 2>/dev/null | LC_ALL=C sort)
    if [ -n "$min_status" ] && [ -n "$status" ] && [ "$(mos_status_rank "$status")" -gt "$min_rank" ]; then
      v_warn "$where: epic status '$status' is ahead of its furthest-behind child ('$min_status') — WORKFLOW.md § Epic flow: the epic reflects the furthest-behind child"
    fi
    return 0
  fi

  # Phase-doc honesty: a phase document may not exist before its phase.
  #
  # Exempt: blocked and cancelled are orthogonal to phase progression, not points
  # along it — a task that reached verifying and then became blocked legitimately
  # keeps its 04-verification.md. An empty status is already an error above, so
  # judging its phase docs would only add noise.
  if [ -z "$status" ] || in_set "$status" "blocked cancelled"; then
    return 0
  fi

  check
  if [ -f "$folder/01-context.md" ] && [ "$status" = "intake" ]; then
    v_error "$where: 01-context.md exists while status is intake — advance status to context or delete the file"
  fi

  check
  if [ -f "$folder/02-plan.md" ] && in_set "$status" "intake context"; then
    v_error "$where: 02-plan.md exists while status is '$status' — it may only exist from planning onward"
  fi

  check
  if [ -f "$folder/03-implementation-plan.md" ] && in_set "$status" "intake context planning plan-review"; then
    v_error "$where: 03-implementation-plan.md exists while status is '$status' — it may only exist from impl-planning onward"
  fi

  check
  if [ -f "$folder/04-verification.md" ] && ! in_set "$status" "executing verifying delivering awaiting-merge feedback done"; then
    v_error "$where: 04-verification.md exists while status is '$status' — it may only exist while executing, verifying, delivering, awaiting-merge, feedback or done"
  fi

  # An empty repos: past intake means phase 01 silently skips the KB read
  # for every affected repo. Warn, don't error: the template ships
  # "repos: []", block-style lists read as empty scalars here (so only the
  # literal inline empty list fires), and knowledge-only work is legal.
  check
  repos_val=$(field "$file" repos)
  if [ "$repos_val" = "[]" ] && ! in_set "$status" "intake blocked cancelled done"; then
    v_warn "$where: repos is [] while status is '$status' — fill repos: with the registered repo ids this work touches (workflow/phases/00-intake.md)"
  fi

  # Gate 2 and delivery conformance (tasks/stories only).
  rank=$(mos_status_rank "$status")
  if [ "$rank" -ge 7 ]; then
    check
    if [ "$status" = feedback ]; then
      # phases/07-feedback.md step 5 sets the implementation plan back to
      # status: in-review for the gate-2 revisit and waits for the human, so
      # an item in feedback legitimately has an unapproved plan. Both gate-2
      # documents must still be there.
      [ -f "$folder/03-implementation-plan.md" ] ||
        conf_report "$instrumented" "$where: status 'feedback' but 03-implementation-plan.md is missing — the feedback round revisits gate 2 (phases/07-feedback.md)"
    else
      gate_approved "$folder/03-implementation-plan.md" ||
        conf_report "$instrumented" "$where: status '$status' is past gate 2 but 03-implementation-plan.md is not approved (status: approved + approved_by + approved_at)"
    fi
    check
    [ -f "$folder/03-implementation-plan-review.md" ] ||
      conf_report "$instrumented" "$where: status '$status' is past gate 2 but 03-implementation-plan-review.md is missing"
  fi
  if [ "$rank" -ge 9 ]; then
    check
    if [ ! -f "$folder/04-verification.md" ] || [ "$(field "$folder/04-verification.md" status)" != complete ]; then
      conf_report "$instrumented" "$where: status '$status' but 04-verification.md is missing or not status: complete (phases/05-verify.md)"
    fi
    check
    if [ ! -f "$folder/04-diff-review.md" ] || [ "$(field "$folder/04-diff-review.md" verdict)" != PASS ]; then
      conf_report "$instrumented" "$where: status '$status' but 04-diff-review.md is missing or its verdict is not PASS (phases/05-verify.md step 3)"
    fi
  fi
}

validate_kb_doc() {
  local file="$1" dir base where ktype status created stale verified
  dir=$(dirname "$file")
  base=$(basename "$file")
  where=$(rel "$file")

  # An unsubstituted {{DATE}} means a template was copied without filling it
  # in. Worth its own check because it otherwise fails silently: "created:
  # {{DATE}}" is not an ISO date, so the draft-age check below skips rather
  # than firing. Only new-work.sh substitutes placeholders, and only for
  # templates/work/ — knowledge docs are copied by hand.
  check
  if grep -qF '{{DATE}}' "$file"; then
    v_error "$where: unsubstituted {{DATE}} placeholder — replace it with the real date (date -u +%Y-%m-%d)"
  fi

  check
  if has_frontmatter "$file"; then
    ktype=$(field "$file" type)
    check
    if [ -z "$ktype" ]; then
      v_error "$where: frontmatter field 'type' is missing or empty — expected one of: $KB_TYPES"
    elif ! in_set "$ktype" "$KB_TYPES"; then
      v_error "$where: type '$ktype' is not one of: $KB_TYPES"
    fi

    stale=$(field "$file" stale_after)
    check
    if is_iso_date "$stale" && [[ "$stale" < "$today" ]]; then
      v_warn "$where: stale_after $stale has passed — re-check the content and bump stale_after"
    fi

    status=$(field "$file" status)
    created=$(field "$file" created)
    # Validate the status vocabulary. Without this, a typo ("stabel", "Draft")
    # passes silently AND disables the draft-age warning below, which tests
    # status = "draft" exactly — so the one mechanism that stops drafts
    # accumulating fails closed on a misspelling.
    check
    if [ -z "$status" ]; then
      v_error "$where: frontmatter field 'status' is missing or empty — expected one of: $KB_STATUSES"
    elif ! in_set "$status" "$KB_STATUSES"; then
      v_error "$where: status '$status' is not one of: $KB_STATUSES"
    fi
    check
    if [ "$status" = "draft" ] && [ -n "$cutoff30" ] &&
      is_iso_date "$created" && [[ "$created" < "$cutoff30" ]]; then
      v_warn "$where: still status draft, created $created (more than 30 days ago) — finish it or mark it stable"
    fi

    # verified: optional human-review stamp. When set, it must be a date —
    # a malformed value would silently defeat the reviewed-vs-raw signal
    # that shared bundles rely on.
    verified=$(field "$file" verified)
    check
    if [ -n "$verified" ] && [ "$verified" != "null" ] && ! is_iso_date "$verified"; then
      v_warn "$where: verified '$verified' is not a YYYY-MM-DD date — use the date the human reviewed it, or null"
    fi
  else
    v_error "$where: no YAML frontmatter — knowledge docs need '---', a 'type:' field and a closing '---'"
  fi

  check
  if [ -f "$dir/index.md" ]; then
    if ! grep -qF -- "$base" "$dir/index.md"; then
      v_warn "$where: not listed in $(rel "$dir")/index.md"
    fi
  else
    case " $kb_dirs_seen " in
      *" $dir "*) : ;;
      *)
        kb_dirs_seen="$kb_dirs_seen $dir"
        v_warn "$(rel "$dir"): no index.md — every knowledge directory needs one"
        ;;
    esac
  fi
}

# --- --harness: template self-check -----------------------------------------
smoke_failed=0
SMOKE_ITEM=""
smoke_fail() {
  printf 'smoke: FAIL — %s\n' "$*" >&2
  smoke_failed=1
}
smoke_assert_file() { check; [ -f "$1" ] || smoke_fail "expected file: $1"; }
smoke_assert_grep() { check; grep -Eq -- "$2" "$1" 2>/dev/null || smoke_fail "expected /$2/ in $1"; }
smoke_assert_eq() { check; [ "$1" = "$2" ] || smoke_fail "$3: expected '$2', got '$1'"; }

# smoke_workspace — copy the template machinery into a throwaway git repo
# and export SMOKE=<its path>. The EXIT trap set below removes it, however
# the run ends (success, failure or interrupt).
smoke_workspace() {
  local src="$1"
  SMOKE=$(mktemp -d "${TMPDIR:-/tmp}/mos-smoke.XXXXXX") || mos_die "mktemp failed"
  SMOKE=$(cd "$SMOKE" && pwd -P)
  # shellcheck disable=SC2064
  trap "rm -rf '$SMOKE'" EXIT
  trap 'if [ "${BASH_SUBSHELL:-0}" -eq 0 ]; then printf "smoke: aborted at validate.sh line %s (a smoke command exited non-zero — see the last command output)\n" "$LINENO" >&2; fi' ERR
  mkdir -p "$SMOKE/work" "$SMOKE/knowledge" "$SMOKE/repos" "$SMOKE/worktrees"
  cp -R "$src/scripts" "$src/templates" "$src/workflow" "$src/config" "$SMOKE/"
  cp "$src/VERSION" "$src/CHANGELOG.md" "$SMOKE/"
  cp "$src/.gitignore" "$SMOKE/"
  git -C "$SMOKE" init -q
  git -C "$SMOKE" -c user.email=smoke@example.invalid -c user.name=smoke add -A
  git -C "$SMOKE" -c user.email=smoke@example.invalid -c user.name=smoke commit -q -m 'smoke: template copy'
}

run_harness_checks() {
  set -E
  local src version heading_version f
  src=$(mos_root)

  check
  if [ ! -f "$src/VERSION" ]; then
    v_error "VERSION is missing at the template root — create it with a MAJOR.MINOR.PATCH line"
  else
    version=$(head -1 "$src/VERSION" | tr -d ' \t\r')
    check
    if ! printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      v_error "VERSION '$version' is not MAJOR.MINOR.PATCH"
    fi
    check
    heading_version=$(grep -m1 -E '^## ' "$src/CHANGELOG.md" | sed -E 's/^## ([^ ]+).*/\1/')
    if [ "$heading_version" != "$version" ]; then
      v_error "newest CHANGELOG.md heading is '## $heading_version …' but VERSION is '$version' — bump one to match (heading format: '## <version> — <date>')"
    fi
  fi

  for f in "$src"/scripts/*.sh; do
    check
    bash -n "$f" 2>/dev/null || v_error "$(rel "$f"): bash -n failed"
  done

  # Warning severity and above only: info-level heuristics (e.g. SC2015 on
  # "cmd || true") differ between shellcheck versions, and whatever version
  # happens to be on PATH (a CI runner image, a distro package) must not
  # fail the self-check for that. Info-level cleanliness is gated by the
  # pinned container run (README / CI workflow), not here.
  if command -v shellcheck >/dev/null 2>&1; then
    check
    shellcheck --severity=warning "$src"/scripts/*.sh || v_error "shellcheck reported findings (warning severity or above)"
  else
    printf 'shellcheck: skipped (not installed)\n'
  fi

  smoke_workspace "$src"
  run_smoke "$SMOKE"
  [ "$smoke_failed" -eq 0 ] || v_error "smoke assertions failed (see smoke: FAIL lines above)"

  if [ "$errors" -gt 0 ]; then
    printf 'harness: FAILED — %s error(s), %s checks\n' "$errors" "$checks" >&2
    exit 1
  fi
  printf 'harness: OK (%s checks)\n' "$checks"
  exit 0
}

# run_smoke <copy> — end-to-end assertions against the throwaway copy.
# Each later change to the run record adds its assertions here.
run_smoke() {
  local w="$1" out
  # --- lib.sh helpers (Task 2) ---
  out=$(cd "$w" && . scripts/lib.sh && mos_statuses)
  smoke_assert_eq "$out" "intake context planning plan-review impl-planning impl-review executing verifying delivering awaiting-merge feedback done blocked cancelled" "mos_statuses"
  out=$(cd "$w" && . scripts/lib.sh && mos_status_rank feedback)
  smoke_assert_eq "$out" 7 "mos_status_rank feedback"
  out=$(cd "$w" && . scripts/lib.sh && mos_status_rank blocked)
  smoke_assert_eq "$out" 0 "mos_status_rank blocked"
  out=$(cd "$w" && . scripts/lib.sh && mos_event_names)
  smoke_assert_eq "$out" "created status gate-review gate-approved changes-requested blocked unblocked step diff-review verification delivered merged closed-unmerged feedback reverted correction harvest cancelled" "mos_event_names"
  out=$(cd "$w" && . scripts/lib.sh && mos_event_vocab | grep -c .)
  smoke_assert_eq "$out" 18 "mos_event_vocab has 18 events"
  out=$(cd "$w" && . scripts/lib.sh && mos_semver_ok 1.2.3 && echo yes || echo no)
  smoke_assert_eq "$out" yes "mos_semver_ok 1.2.3"
  out=$(cd "$w" && . scripts/lib.sh && mos_semver_ok 1.2 && echo yes || echo no)
  smoke_assert_eq "$out" no "mos_semver_ok 1.2"
  out=$(cd "$w" && . scripts/lib.sh && mos_harness_version)
  check; printf '%s' "$out" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\+([0-9a-f]{7,40}|unknown)$' || smoke_fail "mos_harness_version '$out' does not match the stamp regex"
  out=$(cd "$w" && . scripts/lib.sh && mos_iso_to_epoch 2026-01-01T00:00:00Z)
  smoke_assert_eq "$out" 1767225600 "mos_iso_to_epoch"
  out=$(cd "$w" && . scripts/lib.sh && mos_iso_to_epoch 2026-01-01)
  smoke_assert_eq "$out" 1767225600 "mos_iso_to_epoch date-only"
  printf -- '---\nid: x\nmr: null\n---\n\nbody\n' >"$w/fm.md"
  (cd "$w" && . scripts/lib.sh && mos_frontmatter_set fm.md mr https://example.invalid/1 && mos_frontmatter_set fm.md harness 1.0.0+abcdef1)
  smoke_assert_grep "$w/fm.md" '^mr: https://example.invalid/1$'
  smoke_assert_grep "$w/fm.md" '^harness: 1\.0\.0\+abcdef1$'
  out=$(awk 'NR==5' "$w/fm.md")
  smoke_assert_eq "$out" "---" "mos_frontmatter_set inserts before the closing ---"
  smoke_assert_grep "$w/fm.md" '^body$'
  mkdir -p "$w/work/active/T-20260101-fixture" "$w/work/active/E-20260101-epic/S-20260101-child"
  printf -- '---\nid: T-20260101-fixture\n---\n' >"$w/work/active/T-20260101-fixture/task.md"
  printf -- '---\nid: S-20260101-child\n---\n' >"$w/work/active/E-20260101-epic/S-20260101-child/task.md"
  out=$(cd "$w" && . scripts/lib.sh && mos_work_item_dir T-20260101-fixture)
  smoke_assert_eq "$out" "$w/work/active/T-20260101-fixture" "mos_work_item_dir top-level"
  out=$(cd "$w" && . scripts/lib.sh && mos_work_item_dir S-20260101-child)
  smoke_assert_eq "$out" "$w/work/active/E-20260101-epic/S-20260101-child" "mos_work_item_dir epic child"
  out=$(cd "$w" && . scripts/lib.sh && mos_work_item_dir nope-nope 2>&1) || true
  check; printf '%s' "$out" | grep -q 'no work item' || smoke_fail "mos_work_item_dir should die on unknown id, got: $out"
  out=$(cd "$w" && . scripts/lib.sh && mos_work_item_doc work/active/T-20260101-fixture)
  smoke_assert_eq "$out" "work/active/T-20260101-fixture/task.md" "mos_work_item_doc"
  rm -rf "$w/work/active/T-20260101-fixture" "$w/work/active/E-20260101-epic" "$w/fm.md"

  # --- stamp.sh + new-work stamping (Task 3) ---
  out=$(cd "$w" && scripts/stamp.sh --print)
  check; printf '%s' "$out" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\+[0-9a-f]{7,40}$' || smoke_fail "stamp.sh --print: '$out'"
  out=$(cd "$w" && scripts/new-work.sh task "smoke" | sed 's/^created: //')
  SMOKE_ITEM=$(dirname "$out")
  smoke_assert_file "$SMOKE_ITEM/task.md"
  smoke_assert_grep "$SMOKE_ITEM/task.md" '^harness: [0-9]+\.[0-9]+\.[0-9]+\+[0-9a-f]{7,40}$'
  smoke_assert_grep "$SMOKE_ITEM/task.md" '^workspace_rev: [0-9a-f]{7,40}$'
  check; grep -Eq '\{\{[A-Za-z_]+\}\}' "$SMOKE_ITEM/task.md" && smoke_fail "task.md still has {{TOKENS}}"
  # backfill: strip the stamp, then --backfill must restore a stamp (0.0.0+ or real)
  (cd "$w" && awk '!/^(harness|workspace_rev):/' "$SMOKE_ITEM/task.md" >"$SMOKE_ITEM/task.md.tmp" && mv "$SMOKE_ITEM/task.md.tmp" "$SMOKE_ITEM/task.md")
  out=$(cd "$w" && scripts/stamp.sh --backfill --dry-run)
  check; printf '%s' "$out" | grep -q "$(basename "$SMOKE_ITEM")" || smoke_fail "stamp.sh --backfill --dry-run should list the unstamped item, got: $out"
  smoke_assert_grep "$SMOKE_ITEM/task.md" '^created: '
  (cd "$w" && scripts/stamp.sh --backfill >/dev/null)
  smoke_assert_grep "$SMOKE_ITEM/task.md" '^harness: [0-9]+\.[0-9]+\.[0-9]+\+([0-9a-f]{7,40}|unknown)$'
  smoke_assert_grep "$SMOKE_ITEM/task.md" '^workspace_rev: '

  # item-mode stamp rewrites both fields with current values
  (cd "$w" && scripts/stamp.sh "$(basename "$SMOKE_ITEM")") >/dev/null
  smoke_assert_grep "$SMOKE_ITEM/task.md" '^harness: [0-9]+\.[0-9]+\.[0-9]+\+[0-9a-f]{7,40}$'
  smoke_assert_eq "$(grep -c '^harness: ' "$SMOKE_ITEM/task.md")" 1 "item-mode stamp leaves exactly one harness: line"
  # without VERSION, new-work.sh must fail loudly and create nothing
  mv "$w/VERSION" "$w/VERSION.smokebak"
  out=$(cd "$w" && scripts/new-work.sh task "nostamp" 2>&1) && smoke_fail "new-work.sh must fail when VERSION is missing"
  check; printf '%s' "$out" | grep -q 'VERSION' || smoke_fail "new-work.sh failure should name VERSION, got: $out"
  check; ls -d "$w"/work/backlog/*-nostamp >/dev/null 2>&1 && smoke_fail "new-work.sh created a folder despite the missing VERSION"
  out=$(cd "$w" && scripts/stamp.sh "$(basename "$SMOKE_ITEM")" 2>&1) && smoke_fail "stamp.sh must fail when VERSION is missing"
  smoke_assert_grep "$SMOKE_ITEM/task.md" '^harness: [0-9]+\.[0-9]+\.[0-9]+\+[0-9a-f]{7,40}$'
  mv "$w/VERSION.smokebak" "$w/VERSION"

  # --- event.sh (Task 4) ---
  smoke_assert_file "$SMOKE_ITEM/events.log"
  smoke_assert_grep "$SMOKE_ITEM/events.log" "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z	created$"
  (cd "$w" && scripts/event.sh "$(basename "$SMOKE_ITEM")" status from=intake to=context -- "context started") >/dev/null
  mkdir -p "$w/work/active" && mv "$SMOKE_ITEM" "$w/work/active/" && SMOKE_ITEM="$w/work/active/$(basename "$SMOKE_ITEM")"
  smoke_assert_grep "$SMOKE_ITEM/events.log" "	status	from=intake	to=context$"
  smoke_assert_grep "$SMOKE_ITEM/task.md" '^status: context$'
  smoke_assert_grep "$SMOKE_ITEM/task.md" "^- [0-9]{4}-[0-9]{2}-[0-9]{2} — context started$"
  smoke_assert_grep "$SMOKE_ITEM/task.md" "^updated: $(mos_today)$"
  (cd "$w" && scripts/event.sh "$SMOKE_ITEM" gate-review gate=1 round=1 confidence=90 barred=no inherent=no review=02-plan-review.md) >/dev/null
  smoke_assert_grep "$SMOKE_ITEM/task.md" '^- .* — gate 1 review round 1: confidence 90 \(no caps\)$'
  (cd "$w" && scripts/event.sh "$SMOKE_ITEM" blocked was=context "unblock=human answers Q1") >/dev/null
  smoke_assert_grep "$SMOKE_ITEM/task.md" '^status: blocked$'
  smoke_assert_grep "$SMOKE_ITEM/task.md" '^- .* — blocked \(was: context; unblock: human answers Q1\)$'
  (cd "$w" && scripts/event.sh "$SMOKE_ITEM" unblocked) >/dev/null
  smoke_assert_grep "$SMOKE_ITEM/task.md" '^status: context$'
  out=$(cd "$w" && scripts/event.sh "$SMOKE_ITEM" bogus 2>&1 || true)
  check; printf '%s' "$out" | grep -q "unknown event" || smoke_fail "event.sh should reject unknown events, got: $out"
  out=$(cd "$w" && scripts/event.sh "$SMOKE_ITEM" status from=context 2>&1 || true)
  check; printf '%s' "$out" | grep -q "missing required key" || smoke_fail "event.sh should reject a missing key, got: $out"
  out=$(cd "$w" && scripts/event.sh "$SMOKE_ITEM" status from=context to=nowhere 2>&1 || true)
  check; printf '%s' "$out" | grep -q "not a legal status" || smoke_fail "event.sh should reject an illegal status, got: $out"

  # (fix round 1) prose survives backslashes; newline in prose rejected; from= must match; first event keeps the blank after ## Activity
  (cd "$w" && scripts/event.sh "$SMOKE_ITEM" correction 'what=path C:\notes\typo fix' -- 'kept literal \n and \t here') >/dev/null
  smoke_assert_grep "$SMOKE_ITEM/task.md" '^- .* — kept literal \\n and \\t here$'
  out=$(cd "$w" && scripts/event.sh "$SMOKE_ITEM" correction what=x -- "line one
line two" 2>&1) && smoke_fail "event.sh must reject a newline in prose"
  check; printf '%s' "$out" | grep -q 'newline' || smoke_fail "newline rejection message missing, got: $out"
  out=$(cd "$w" && scripts/event.sh "$SMOKE_ITEM" status from=planning to=executing 2>&1) && smoke_fail "event.sh must reject from= that does not match the current status"
  check; printf '%s' "$out" | grep -q 'does not match' || smoke_fail "from= mismatch message missing, got: $out"
  smoke_assert_grep "$SMOKE_ITEM/task.md" '^status: context$'
  out=$(awk '/^## Activity/{getline; print; exit}' "$SMOKE_ITEM/task.md")
  smoke_assert_eq "$out" "" "blank line preserved between ## Activity and the first entry"
  out=$(awk '/^## Activity/{getline; getline; print; exit}' "$SMOKE_ITEM/task.md")
  check; printf '%s' "$out" | grep -Eq '^- [0-9]{4}-[0-9]{2}-[0-9]{2} — created$' || smoke_fail "first Activity entry should be the created line, got: $out"

  smoke_assert_eq "$(grep -c . "$SMOKE_ITEM/events.log")" 6 "events.log has exactly the 6 accepted events"
  smoke_assert_eq "$(grep -c '^status: ' "$SMOKE_ITEM/task.md")" 1 "task.md has exactly one status: line"

  # --- trace-capture.sh path (Task 5) ---
  out=$(cd "$w" && scripts/trace-capture.sh path "$SMOKE_ITEM" brief 01 explorer)
  smoke_assert_eq "$out" "$SMOKE_ITEM/trace/briefs/01-explorer-1.md" "first explorer brief path"
  : >"$out"
  out=$(cd "$w" && scripts/trace-capture.sh path "$SMOKE_ITEM" brief 01 explorer)
  smoke_assert_eq "$out" "$SMOKE_ITEM/trace/briefs/01-explorer-2.md" "second explorer brief path increments"
  out=$(cd "$w" && scripts/trace-capture.sh path "$SMOKE_ITEM" report 04 implementer --step 3)
  smoke_assert_eq "$out" "$SMOKE_ITEM/trace/reports/04-implementer-step3-1.md" "implementer report path"
  check; [ -d "$SMOKE_ITEM/trace/reports" ] || smoke_fail "path should create trace/reports/"
  out=$(cd "$w" && scripts/trace-capture.sh path "$SMOKE_ITEM" brief 9 explorer 2>&1 || true)
  check; printf '%s' "$out" | grep -q "two-digit" || smoke_fail "path should reject a non two-digit phase, got: $out"
  smoke_assert_grep "$w/.gitignore" '^work/\*\*/trace/raw/$'
  smoke_assert_grep "$w/.gitignore" '^work/\.trace-unassigned/$'
  out=$(cd "$w" && scripts/trace-capture.sh path "$SMOKE_ITEM" brief 04 implementer --step x3 2>&1 || true)
  check; printf '%s' "$out" | grep -q 'must be a number' || smoke_fail "path should reject a non-numeric --step, got: $out"
  out=$(cd "$w" && scripts/trace-capture.sh path "$SMOKE_ITEM" brief 04 implementer --step 12)
  smoke_assert_eq "$out" "$SMOKE_ITEM/trace/briefs/04-implementer-step12-1.md" "numeric --step accepted"

  # --- trace-capture.sh --hook stop (Task 6) ---
  id=$(basename "$SMOKE_ITEM")
  sed "s|__ID__|$id|g" "$w/scripts/fixtures/transcript.jsonl" >"$w/transcript.jsonl"
  sed "s|__TRANSCRIPT__|$w/transcript.jsonl|" "$w/scripts/fixtures/hook-stop.json" >"$w/hook-stop.json"
  out=$(cd "$w" && scripts/trace-capture.sh --hook stop <hook-stop.json; echo "rc=$?")
  smoke_assert_eq "$out" "rc=0" "stop hook exits 0 and prints nothing"
  smoke_assert_file "$SMOKE_ITEM/trace/sessions.tsv"
  smoke_assert_grep "$SMOKE_ITEM/trace/sessions.tsv" "^session_id	transcript_path	first_seen	last_seen$"
  smoke_assert_grep "$SMOKE_ITEM/trace/sessions.tsv" "^smoke-session-0001	$w/transcript.jsonl	[0-9T:Z-]+	[0-9T:Z-]+$"
  (cd "$w" && scripts/trace-capture.sh --hook stop <hook-stop.json)
  smoke_assert_eq "$(grep -c '^smoke-session-0001' "$SMOKE_ITEM/trace/sessions.tsv")" 1 "second stop upserts, no duplicate row"
  # a transcript that only MENTIONS the id must not attribute
  sed -n 1p "$w/transcript.jsonl" >"$w/mention.jsonl"
  sed "s|__TRANSCRIPT__|$w/mention.jsonl|;s|smoke-session-0001|smoke-session-0002|" "$w/scripts/fixtures/hook-stop.json" >"$w/hook-mention.json"
  (cd "$w" && scripts/trace-capture.sh --hook stop <hook-mention.json)
  check; grep -q 'smoke-session-0002' "$SMOKE_ITEM/trace/sessions.tsv" && smoke_fail "mention-only transcript was attributed"
  smoke_assert_grep "$w/work/.trace-unassigned/sessions.tsv" '^smoke-session-0002	'
  # garbage payload: exit 0, logged
  out=$(cd "$w" && printf 'not json' | scripts/trace-capture.sh --hook stop; echo "rc=$?")
  smoke_assert_eq "$out" "rc=0" "garbage payload still exits 0"
  smoke_assert_grep "$w/work/.trace-unassigned/hook.log" 'no session id'
  # copilot: transcript path derived from sessionId under COPILOT_HOME
  mkdir -p "$w/copilot-home/session-state/cp-0001"
  cp "$w/transcript.jsonl" "$w/copilot-home/session-state/cp-0001/events.jsonl"
  (cd "$w" && printf '{"sessionId":"cp-0001","timestamp":1,"cwd":"."}' | COPILOT_HOME="$w/copilot-home" scripts/trace-capture.sh --hook stop --agent copilot)
  smoke_assert_grep "$SMOKE_ITEM/trace/sessions.tsv" "^cp-0001	$w/copilot-home/session-state/cp-0001/events.jsonl	"

  # --- trace-capture.sh --hook subagent-stop + hook config (Task 7) ---
  sed "s|__TRANSCRIPT__|$w/transcript.jsonl|;s|__PARENT__|$w/mention.jsonl|" "$w/scripts/fixtures/hook-subagent-stop.json" >"$w/hook-sub.json"
  (cd "$w" && scripts/trace-capture.sh --hook subagent-stop <hook-sub.json)
  smoke_assert_file "$SMOKE_ITEM/trace/raw/agent-smoke-01.jsonl"
  smoke_assert_eq "$(wc -l <"$SMOKE_ITEM/trace/raw/agent-smoke-01.jsonl" | tr -d ' ')" 3 "subagent transcript copied whole"
  # older Claude Code payloads: no agent_transcript_path → fall back to transcript_path
  sed "s|__TRANSCRIPT__|$w/transcript.jsonl|;s|__PARENT__|$w/transcript.jsonl|;/agent_transcript_path/d;s|agent-smoke-01|agent-smoke-02|" "$w/scripts/fixtures/hook-subagent-stop.json" >"$w/hook-sub2.json"
  (cd "$w" && scripts/trace-capture.sh --hook subagent-stop <hook-sub2.json)
  smoke_assert_file "$SMOKE_ITEM/trace/raw/agent-smoke-02.jsonl"
  # unattributed subagent transcript → unassigned raw/
  sed "s|__TRANSCRIPT__|$w/mention.jsonl|;s|__PARENT__|$w/mention.jsonl|;s|agent-smoke-01|agent-smoke-03|" "$w/scripts/fixtures/hook-subagent-stop.json" >"$w/hook-sub3.json"
  (cd "$w" && scripts/trace-capture.sh --hook subagent-stop <hook-sub3.json)
  smoke_assert_file "$w/work/.trace-unassigned/raw/smoke-session-0001-agent-smoke-03.jsonl"
  # hook config files
  smoke_assert_grep "$(mos_root)/.claude/settings.json" '"SubagentStop"'
  smoke_assert_grep "$(mos_root)/.claude/settings.json" '"Stop"'
  smoke_assert_grep "$(mos_root)/.claude/settings.json" 'trace-capture.sh\\" --hook subagent-stop'
  smoke_assert_grep "$(mos_root)/.claude/settings.json" 'trace-capture.sh\\" --hook stop'
  smoke_assert_grep "$(mos_root)/.github/hooks/trace-capture.json" '"agentStop"'
  smoke_assert_grep "$(mos_root)/.github/hooks/trace-capture.json" '"subagentStop"'
  smoke_assert_grep "$(mos_root)/.github/hooks/trace-capture.json" '\-\-hook stop --agent copilot'
  smoke_assert_grep "$(mos_root)/.github/hooks/trace-capture.json" '\-\-hook subagent-stop --agent copilot'
  rm -f "$w/transcript.jsonl" "$w/mention.jsonl" "$w"/hook-*.json; rm -rf "$w/copilot-home"

  # --- conformance checks (Task 8) ---
  # SMOKE_ITEM is at status context with events.log → violations are ERRORS.
  (cd "$w" && scripts/event.sh "$SMOKE_ITEM" status from=context to=executing) >/dev/null
  out=$(cd "$w" && scripts/validate.sh 2>&1 || true)
  check; printf '%s' "$out" | grep -q "error: .*02-plan.md.*approved" || smoke_fail "executing without an approved 02-plan.md must be an error, got: $out"
  check; printf '%s' "$out" | grep -q "error: .*03-implementation-plan.md.*approved" || smoke_fail "executing without an approved impl plan must be an error"
  check; printf '%s' "$out" | grep -q "error: .*02-plan-review.md" || smoke_fail "missing gate-1 review doc must be an error"
  # satisfy gate 1 and 2, then delivering without verification/diff review
  today=$(mos_today)
  printf -- '---\ntask: %s\nphase: plan\nstatus: approved\napproved_at: %s\napproved_by: human\nupdated: %s\n---\n# Plan\n' "$id" "$today" "$today" >"$SMOKE_ITEM/02-plan.md"
  printf -- '---\ntask: %s\nphase: plan-review-report\nconfidence: 90\nreview_round: 1\nauto_approval_barred: no\n---\n' "$id" >"$SMOKE_ITEM/02-plan-review.md"
  printf -- '---\ntask: %s\nphase: implementation-plan\nstatus: approved\napproved_at: %s\napproved_by: plan-reviewer (confidence 90)\nupdated: %s\n---\n# Impl\n' "$id" "$today" "$today" >"$SMOKE_ITEM/03-implementation-plan.md"
  printf -- '---\ntask: %s\nphase: plan-review-report\nconfidence: 90\nreview_round: 1\nauto_approval_barred: no\n---\n' "$id" >"$SMOKE_ITEM/03-implementation-plan-review.md"
  (cd "$w" && scripts/event.sh "$SMOKE_ITEM" status from=executing to=delivering) >/dev/null
  out=$(cd "$w" && scripts/validate.sh 2>&1 || true)
  check; printf '%s' "$out" | grep -q "error: .*04-verification.md" || smoke_fail "delivering without 04-verification.md must be an error"
  check; printf '%s' "$out" | grep -q "error: .*04-diff-review.md" || smoke_fail "delivering without a PASS diff review must be an error"
  printf -- '---\ntask: %s\nphase: verification\nstatus: complete\nupdated: %s\n---\n' "$id" "$today" >"$SMOKE_ITEM/04-verification.md"
  printf -- '---\ntask: %s\nphase: diff-review-report\nrepos: []\nverdict: PASS\ncreated: %s\n---\n' "$id" "$today" >"$SMOKE_ITEM/04-diff-review.md"
  out=$(cd "$w" && scripts/validate.sh 2>&1; echo "rc=$?")
  check; printf '%s' "$out" | grep -q "rc=0" || smoke_fail "conformant item should validate, got: $out"
  # malformed events.log line → error; status disagreement → error
  printf 'not-a-timestamp\tstatus\tto=done\n' >>"$SMOKE_ITEM/events.log"
  out=$(cd "$w" && scripts/validate.sh 2>&1 || true)
  check; printf '%s' "$out" | grep -q "error: .*events.log.*timestamp" || smoke_fail "malformed events.log timestamp must be an error, got: $out"
  sed '$d' "$SMOKE_ITEM/events.log" >"$SMOKE_ITEM/events.log.tmp" && mv "$SMOKE_ITEM/events.log.tmp" "$SMOKE_ITEM/events.log"
  (cd "$w" && . scripts/lib.sh && mos_frontmatter_set "$SMOKE_ITEM/task.md" status verifying)
  out=$(cd "$w" && scripts/validate.sh 2>&1 || true)
  check; printf '%s' "$out" | grep -q "error: .*status.*'verifying'.*events.log.*'delivering'" || smoke_fail "status/events.log disagreement must be an error, got: $out"
  (cd "$w" && . scripts/lib.sh && mos_frontmatter_set "$SMOKE_ITEM/task.md" status delivering)
  # legacy item (no events.log, no stamp) → warnings only, exit 0
  mkdir -p "$w/work/done/T-20260101-legacy"
  printf -- '---\nid: T-20260101-legacy\ntype: task\ntitle: "legacy"\nstatus: done\nrepos: []\nepic: null\ncreated: 2026-01-01\nupdated: 2026-01-02\nmr: null\n---\n\n## Activity\n\n- 2026-01-01 — created\n' >"$w/work/done/T-20260101-legacy/task.md"
  out=$(cd "$w" && scripts/validate.sh 2>&1; echo "rc=$?")
  check; printf '%s' "$out" | grep -q "rc=0" || smoke_fail "legacy item must not fail validation, got: $out"
  check; printf '%s' "$out" | grep -q "warning: .*T-20260101-legacy.*04-verification.md" || smoke_fail "legacy item gaps must warn"
  check; printf '%s' "$out" | grep -q "warning: .*T-20260101-legacy.*harness" || smoke_fail "legacy item missing stamp must warn"
  # epic roll-up warning
  mkdir -p "$w/work/active/E-20260101-roll/S-20260101-kid"
  printf -- '---\nid: E-20260101-roll\ntype: epic\ntitle: "roll"\nstatus: executing\nrepos: []\nepic: null\ncreated: 2026-01-01\nupdated: 2026-01-01\nmr: null\nharness: 0.0.0+unknown\nworkspace_rev: unknown\n---\n\n## Activity\n' >"$w/work/active/E-20260101-roll/epic.md"
  printf -- '---\nid: S-20260101-kid\ntype: story\ntitle: "kid"\nstatus: context\nrepos: []\nepic: E-20260101-roll\ncreated: 2026-01-01\nupdated: 2026-01-01\nmr: null\nharness: 0.0.0+unknown\nworkspace_rev: unknown\n---\n\n## Activity\n' >"$w/work/active/E-20260101-roll/S-20260101-kid/task.md"
  out=$(cd "$w" && scripts/validate.sh 2>&1 || true)
  check; printf '%s' "$out" | grep -q "warning: .*E-20260101-roll.*furthest-behind child.*context" || smoke_fail "epic roll-up must warn, got: $out"
  rm -rf "$w/work/done/T-20260101-legacy" "$w/work/active/E-20260101-roll"

  # (fix round 1) a plain unblocked (no to=) must not trip the status/events agreement check
  (cd "$w" && scripts/event.sh "$SMOKE_ITEM" blocked was=delivering "unblock=smoke" && scripts/event.sh "$SMOKE_ITEM" unblocked) >/dev/null
  smoke_assert_grep "$SMOKE_ITEM/task.md" '^status: delivering$'
  out=$(cd "$w" && scripts/validate.sh 2>&1; echo "rc=$?")
  check; printf '%s' "$out" | grep -q "rc=0" || smoke_fail "blocked→unblocked (no to=) must validate clean, got: $out"
  check; printf '%s' "$out" | grep -q "events.log says 'blocked'" && smoke_fail "false status/events disagreement after unblocked"

  # --- scorecard.sh rows (Task 9) ---
  # enrich the smoke item's log so the columns have values to check
  (cd "$w" && scripts/event.sh "$SMOKE_ITEM" gate-approved gate=1 by=auto confidence=90 &&
    scripts/event.sh "$SMOKE_ITEM" gate-review gate=2 round=1 confidence=70 barred=no inherent=no review=03-implementation-plan-review.md &&
    scripts/event.sh "$SMOKE_ITEM" gate-review gate=2 round=2 confidence=88 barred=no inherent=no review=03-implementation-plan-review.md &&
    scripts/event.sh "$SMOKE_ITEM" gate-approved gate=2 by=human confidence=88 &&
    scripts/event.sh "$SMOKE_ITEM" step step=1 result=fail attempts=1 &&
    scripts/event.sh "$SMOKE_ITEM" step step=1 result=pass attempts=2 &&
    scripts/event.sh "$SMOKE_ITEM" diff-review repo=demo verdict=PASS findings=0 &&
    scripts/event.sh "$SMOKE_ITEM" verification gates=3/3 verdict=PASS &&
    scripts/event.sh "$SMOKE_ITEM" correction "what=used fix: instead of bugfix:" &&
    scripts/event.sh "$SMOKE_ITEM" delivered mode=auto mr=https://example.invalid/mr/1 &&
    scripts/event.sh "$SMOKE_ITEM" merged mr=https://example.invalid/mr/1) >/dev/null
  # shellcheck disable=SC2031 # false positive: id is set once above (line
  # ~636), never inside a subshell; shellcheck misreads the long &&-chained
  # subshell just above as reassigning it (confirmed by bisection).
  mkdir -p "$w/work/done" && mv "$SMOKE_ITEM" "$w/work/done/" && SMOKE_ITEM="$w/work/done/$id"
  # A raw transcript with tool calls but NO usage data: the token sums grep for
  # "input_tokens"/"output_tokens" and find nothing. Under `set -o pipefail`
  # that pipeline exits 1 and, inside a command substitution feeding an
  # assignment, would kill scorecard.sh outright — so this file must not.
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_9","name":"Read","input":{"file_path":"x"}}]}}' >"$SMOKE_ITEM/trace/raw/agent-smoke-nousage.jsonl"
  out=$(cd "$w" && scripts/scorecard.sh)
  smoke_assert_eq "$(printf '%s\n' "$out" | head -1 | cut -f1-3)" "id	type	harness" "scorecard header starts with id type harness"
  smoke_assert_eq "$(printf '%s\n' "$out" | grep -c .)" 2 "scorecard prints header + 1 row"
  row=$(printf '%s\n' "$out" | sed -n 2p)
  col() { printf '%s\n' "$out" | head -1 | tr '\t' '\n' | grep -nx -- "$1" | cut -d: -f1; }
  cell() { printf '%s\n' "$row" | cut -f"$(col "$1")"; }
  # shellcheck disable=SC2031 # false positive: same id, see note above.
  smoke_assert_eq "$(cell id)" "$id" "row id"
  smoke_assert_eq "$(cell status)" "done" "row status"
  smoke_assert_eq "$(cell g1_rounds)" 1 "g1_rounds"
  smoke_assert_eq "$(cell g1_conf_final)" 90 "g1_conf_final"
  smoke_assert_eq "$(cell g1_by)" auto "g1_by"
  smoke_assert_eq "$(cell g2_rounds)" 2 "g2_rounds"
  smoke_assert_eq "$(cell g2_conf_first)" 70 "g2_conf_first"
  smoke_assert_eq "$(cell g2_conf_final)" 88 "g2_conf_final"
  smoke_assert_eq "$(cell g2_by)" human "g2_by"
  smoke_assert_eq "$(cell blocked)" 2 "blocked count"
  smoke_assert_eq "$(cell corrections)" 2 "corrections"
  smoke_assert_eq "$(cell steps)" 2 "steps"
  smoke_assert_eq "$(cell step_fails)" 1 "step_fails"
  smoke_assert_eq "$(cell diff_verdict)" PASS "diff_verdict"
  smoke_assert_eq "$(cell verification)" PASS "verification"
  smoke_assert_eq "$(cell delivered_mode)" auto "delivered_mode"
  smoke_assert_eq "$(cell mr)" https://example.invalid/mr/1 "mr"
  smoke_assert_eq "$(cell docs_missing)" - "no docs missing"
  smoke_assert_eq "$(cell briefs)" 1 "briefs counted (one file was written at the path)"
  smoke_assert_eq "$(cell subagent_transcripts)" 3 "raw subagent transcripts counted (2 copied + the usage-less one)"
  smoke_assert_eq "$(cell tool_calls)" 5 "tool calls summed over raw transcripts (2 files x 2 + 1 in the usage-less one)"
  smoke_assert_eq "$(cell tokens_in)" 400 "tokens_in summed (2 x (120+80); the usage-less transcript adds no tokens)"
  smoke_assert_eq "$(cell source)" events "source=events"
  check; printf '%s' "$(cell lead_h)" | grep -Eq '^[0-9]+(\.[0-9])?$' || smoke_fail "lead_h numeric, got '$(cell lead_h)'"
  out=$(cd "$w" && scripts/scorecard.sh --no-traces)
  row=$(printf '%s\n' "$out" | sed -n 2p)
  smoke_assert_eq "$(cell tool_calls)" - "--no-traces leaves tool_calls empty"
  # legacy row
  mkdir -p "$w/work/done/T-20260101-legacy"
  printf -- '---\nid: T-20260101-legacy\ntype: task\ntitle: "legacy"\nstatus: done\nrepos: [demo]\nepic: null\ncreated: 2026-01-01\nupdated: 2026-01-03\nmr: https://example.invalid/mr/9\n---\n\n## Activity\n\n- 2026-01-01 — created\n- 2026-01-02 — gate 2: changes requested by human\n- 2026-01-03 — delivery auto-approved (Auto-deliver: on), MR created: https://example.invalid/mr/9\n- 2026-01-03 — MR !9 merged into main\n' >"$w/work/done/T-20260101-legacy/task.md"
  printf -- '---\ntask: T-20260101-legacy\nphase: plan-review-report\nconfidence: 49\nauto_approval_barred: yes\ninherent_cap: yes\nreview_round: 3\nprevious_confidence: 49\n---\n' >"$w/work/done/T-20260101-legacy/02-plan-review.md"
  printf -- '---\ntask: T-20260101-legacy\nphase: plan\nstatus: approved\napproved_at: 2026-01-02\napproved_by: human\n---\n' >"$w/work/done/T-20260101-legacy/02-plan.md"
  out=$(cd "$w" && scripts/scorecard.sh T-20260101-legacy)
  row=$(printf '%s\n' "$out" | sed -n 2p)
  smoke_assert_eq "$(cell source)" legacy "legacy source"
  smoke_assert_eq "$(cell g1_rounds)" 3 "legacy g1_rounds from review_round"
  smoke_assert_eq "$(cell g1_caps)" 1 "legacy g1_caps from auto_approval_barred"
  smoke_assert_eq "$(cell g1_inherent)" yes "legacy g1_inherent"
  smoke_assert_eq "$(cell g1_by)" human "legacy g1_by from approved_by"
  smoke_assert_eq "$(cell changes_requested)" 1 "legacy changes_requested from Activity"
  smoke_assert_eq "$(cell delivered_mode)" auto "legacy delivered_mode from Activity"
  smoke_assert_eq "$(cell merged)" 2026-01-03 "legacy merged date from Activity"
  smoke_assert_eq "$(cell lead_h)" 48.0 "legacy lead_h (created → merged, whole days)"
  smoke_assert_eq "$(cell harness)" - "legacy harness empty"
  check; printf '%s' "$(cell docs_missing)" | grep -q 'impl-review' || smoke_fail "legacy docs_missing lists impl-review, got '$(cell docs_missing)'"
  check; printf '%s' "$(cell docs_missing)" | grep -q 'events' || smoke_fail "legacy docs_missing lists events"
  rm -rf "$w/work/done/T-20260101-legacy"

  # --- scorecard --summary + status line (Task 10) ---
  out=$(cd "$w" && scripts/scorecard.sh --summary)
  smoke_assert_eq "$(printf '%s\n' "$out" | head -1)" "harness	items	auto_approve_rate	mean_g1_rounds	mean_g2_rounds	changes_requested	blocked	corrections	reverted	items_with_gaps	mean_lead_h" "summary header"
  row=$(printf '%s\n' "$out" | sed -n 2p)
  smoke_assert_eq "$(printf '%s\n' "$row" | cut -f2)" 1 "summary items"
  smoke_assert_eq "$(printf '%s\n' "$row" | cut -f3)" 0.50 "summary auto_approve_rate (1 auto of 2 approvals)"
  smoke_assert_eq "$(printf '%s\n' "$row" | cut -f5)" 2.0 "summary mean_g2_rounds"
  smoke_assert_eq "$(printf '%s\n' "$row" | cut -f8)" 2 "summary corrections"
  smoke_assert_eq "$(printf '%s\n' "$row" | cut -f10)" 0 "summary items_with_gaps"
  out=$(cd "$w" && scripts/status.sh)
  check; printf '%s' "$out" | grep -q '^== Scorecard ==' || smoke_fail "status.sh lacks the Scorecard section"
  check; printf '%s' "$out" | grep -Eq '1 item\(s\), 1 on [0-9]+\.[0-9]+\.[0-9]+\+[0-9a-f]{7,40}, 0 with gaps' || smoke_fail "status.sh scorecard line, got: $(printf '%s' "$out" | grep -A1 Scorecard)"
  smoke_assert_file "$(mos_root)/.claude/commands/scorecard.md"
  smoke_assert_file "$(mos_root)/.github/prompts/scorecard.prompt.md"

  # --- session-brief harness line (Task 11) ---
  out=$(cd "$w" && scripts/session-brief.sh --no-mr-check)
  check; printf '%s\n' "$out" | sed -n 2p | grep -Eq '^Harness: [0-9]+\.[0-9]+\.[0-9]+\+[0-9a-f]+$' || smoke_fail "brief line 2 should be the harness stamp, got: $(printf '%s\n' "$out" | sed -n 2p)"
  # simulate a newer upstream: a second repo with VERSION 9.9.9 as upstream/main
  git -C "$w" -c user.email=smoke@example.invalid -c user.name=smoke add -A >/dev/null 2>&1 || true
  git -C "$w" -c user.email=smoke@example.invalid -c user.name=smoke commit -q -m 'smoke: work' >/dev/null 2>&1 || true
  git -C "$w" branch -q -f upstream-sim HEAD
  git -C "$w" remote add upstream "$w" 2>/dev/null || true
  git -C "$w" fetch -q upstream upstream-sim:refs/remotes/upstream/main
  out=$(cd "$w" && scripts/session-brief.sh --no-mr-check)
  check; printf '%s' "$out" | grep -q 'Harness update available' && smoke_fail "no drift expected when upstream VERSION equals local"
  printf '9.9.9\n' >"$w/VERSION"
  git -C "$w" -c user.email=smoke@example.invalid -c user.name=smoke commit -q -am 'smoke: bump' && git -C "$w" branch -q -f upstream-sim HEAD && git -C "$w" fetch -q upstream upstream-sim:refs/remotes/upstream/main
  git -C "$w" checkout -q HEAD~1 -- VERSION
  out=$(cd "$w" && scripts/session-brief.sh --no-mr-check)
  check; printf '%s' "$out" | grep -q 'Harness update available: upstream/main is 9.9.9' || smoke_fail "drift line missing, got: $(printf '%s\n' "$out" | head -4)"
  git -C "$w" checkout -q HEAD -- VERSION

  # --- docs (Task 13) ---
  smoke_assert_grep "$(mos_root)/AGENTS.md" 'scripts/event.sh'
  smoke_assert_grep "$(mos_root)/AGENTS.md" 'trace-capture.sh path'
  smoke_assert_grep "$(mos_root)/AGENTS.md" 'correction'
  smoke_assert_grep "$(mos_root)/workflow/WORKFLOW.md" '^## Run record'
  smoke_assert_grep "$(mos_root)/workflow/WORKFLOW.md" 'gate-review'
  for p in 00-intake 01-context 02-plan 03-implementation-plan 04-execute 05-verify 06-deliver 07-feedback 08-close; do
    smoke_assert_grep "$(mos_root)/workflow/phases/$p.md" 'event.sh'
  done
  smoke_assert_grep "$(mos_root)/workflow/phases/04-execute.md" 'trace-capture.sh path'
  for f in workflow/implementer.md .claude/agents/implementer.md .github/agents/implementer.agent.md; do
    smoke_assert_grep "$(mos_root)/$f" 'report path'
  done
  smoke_assert_grep "$(mos_root)/CHANGELOG.md" 'stamp.sh --backfill'
  smoke_assert_grep "$(mos_root)/README.md" 'scorecard'
  smoke_assert_grep "$(mos_root)/knowledge/runbooks/update-harness.md" 'VERSION'

  # --- items_with_gaps counts gate-doc gaps only, not stamp/events (Task 12) ---
  # A "legacy-clean" item: no stamp, no events.log, but every gate doc present
  # and approved/complete/PASS — its docs_missing lists harness+events per row,
  # but it must NOT count toward --summary's items_with_gaps.
  id2=T-20260101-legacyclean
  mkdir -p "$w/work/done/$id2"
  printf -- '---\nid: %s\ntype: task\ntitle: "legacy clean"\nstatus: done\nrepos: []\nepic: null\ncreated: %s\nupdated: %s\nmr: null\n---\n\n## Activity\n\n- %s — created\n' "$id2" "$today" "$today" "$today" >"$w/work/done/$id2/task.md"
  printf -- '---\ntask: %s\nphase: plan\nstatus: approved\napproved_at: %s\napproved_by: human\nupdated: %s\n---\n# Plan\n' "$id2" "$today" "$today" >"$w/work/done/$id2/02-plan.md"
  printf -- '---\ntask: %s\nphase: plan-review-report\nconfidence: 90\nreview_round: 1\nauto_approval_barred: no\n---\n' "$id2" >"$w/work/done/$id2/02-plan-review.md"
  printf -- '---\ntask: %s\nphase: implementation-plan\nstatus: approved\napproved_at: %s\napproved_by: human\nupdated: %s\n---\n# Impl\n' "$id2" "$today" "$today" >"$w/work/done/$id2/03-implementation-plan.md"
  printf -- '---\ntask: %s\nphase: plan-review-report\nconfidence: 90\nreview_round: 1\nauto_approval_barred: no\n---\n' "$id2" >"$w/work/done/$id2/03-implementation-plan-review.md"
  printf -- '---\ntask: %s\nphase: verification\nstatus: complete\nupdated: %s\n---\n' "$id2" "$today" >"$w/work/done/$id2/04-verification.md"
  printf -- '---\ntask: %s\nphase: diff-review-report\nrepos: []\nverdict: PASS\ncreated: %s\n---\n' "$id2" "$today" >"$w/work/done/$id2/04-diff-review.md"
  out=$(cd "$w" && scripts/scorecard.sh --summary)
  row=$(printf '%s\n' "$out" | awk -F'\t' '$1 == "-"')
  smoke_assert_eq "$(printf '%s\n' "$row" | cut -f10)" 0 "legacy-clean item (missing only harness+events) must not count toward items_with_gaps"
  out=$(cd "$w" && scripts/scorecard.sh "$id2")
  row=$(printf '%s\n' "$out" | sed -n 2p)
  smoke_assert_eq "$(cell docs_missing)" harness,events "per-row docs_missing still lists harness and events even though they aren't counted as gaps"
  rm -rf "${w:?}/work/done/$id2"

  # --- final-review fix wave -------------------------------------------------
  # (C1) feedback legitimately carries an unapproved implementation plan:
  # phases/07-feedback.md step 5 sets it back to status: in-review for the
  # gate-2 revisit and waits for the human. Requiring approval there is a
  # false error; only the two gate-2 documents must exist.
  fb=T-20260101-feedback
  mkdir -p "$w/work/active/$fb"
  printf -- '---\nid: %s\ntype: task\ntitle: "feedback"\nstatus: delivering\nrepos: []\nepic: null\ncreated: %s\nupdated: %s\nmr: null\nharness: 1.0.0+abcdef1\nworkspace_rev: abcdef1\n---\n\n## Activity\n\n- %s — created\n' "$fb" "$today" "$today" "$today" >"$w/work/active/$fb/task.md"
  printf -- '---\ntask: %s\nphase: plan\nstatus: approved\napproved_at: %s\napproved_by: human\nupdated: %s\n---\n# Plan\n' "$fb" "$today" "$today" >"$w/work/active/$fb/02-plan.md"
  printf -- '---\ntask: %s\nphase: plan-review-report\nconfidence: 90\nreview_round: 1\nauto_approval_barred: no\n---\n' "$fb" >"$w/work/active/$fb/02-plan-review.md"
  printf -- '---\ntask: %s\nphase: implementation-plan\nstatus: approved\napproved_at: %s\napproved_by: human\nupdated: %s\n---\n# Impl\n' "$fb" "$today" "$today" >"$w/work/active/$fb/03-implementation-plan.md"
  printf -- '---\ntask: %s\nphase: plan-review-report\nconfidence: 90\nreview_round: 1\nauto_approval_barred: no\n---\n' "$fb" >"$w/work/active/$fb/03-implementation-plan-review.md"
  printf -- '---\ntask: %s\nphase: verification\nstatus: complete\nupdated: %s\n---\n' "$fb" "$today" >"$w/work/active/$fb/04-verification.md"
  printf -- '---\ntask: %s\nphase: diff-review-report\nrepos: []\nverdict: PASS\ncreated: %s\n---\n' "$fb" "$today" >"$w/work/active/$fb/04-diff-review.md"
  (cd "$w" && scripts/event.sh "$fb" delivered mode=human mr=https://example.invalid/mr/7 &&
    scripts/event.sh "$fb" feedback round=1 reason=mr) >/dev/null
  (cd "$w" && . scripts/lib.sh && mos_frontmatter_set "work/active/$fb/03-implementation-plan.md" status in-review)
  smoke_assert_grep "$w/work/active/$fb/task.md" '^status: feedback$'
  out=$(cd "$w" && scripts/validate.sh 2>&1; echo "rc=$?")
  check; printf '%s' "$out" | grep -q "rc=0" || smoke_fail "feedback item must validate clean, got: $out"
  check; printf '%s' "$out" | grep -q "error: .*$fb" && smoke_fail "feedback with an in-review impl plan must not error, got: $(printf '%s\n' "$out" | grep -- "$fb" || true)"
  out=$(cd "$w" && scripts/scorecard.sh "$fb")
  row=$(printf '%s\n' "$out" | sed -n 2p)
  smoke_assert_eq "$(cell docs_missing)" - "feedback: an impl plan back at in-review is not a missing gate doc"
  rm -rf "${w:?}/work/active/$fb"

  # (I9a) --summary: one row per harness version, ordered by SEMVER not by
  # string. 0.10.0 vs 0.9.0 is the discriminating pair — a lexical sort puts
  # "0.10.0" before "0.9.0"; a semver-aware one does not.
  v09=T-20260101-v09
  v010=T-20260101-v010
  for f in "$v09	0.9.0+abcdef2" "$v010	0.10.0+abcdef1"; do
    fid=${f%%	*}
    fstamp=${f#*	}
    mkdir -p "$w/work/done/$fid"
    printf -- '---\nid: %s\ntype: task\ntitle: "older harness"\nstatus: done\nrepos: []\nepic: null\ncreated: %s\nupdated: %s\nmr: null\n---\n\n## Activity\n\n- %s — created\n' "$fid" "$today" "$today" "$today" >"$w/work/done/$fid/task.md"
    (cd "$w" && . scripts/lib.sh && mos_frontmatter_set "work/done/$fid/task.md" harness "$fstamp")
    : >"$w/work/done/$fid/events.log"
  done
  out=$(cd "$w" && scripts/scorecard.sh --summary)
  smoke_assert_eq "$(printf '%s\n' "$out" | grep -c .)" 4 "--summary: header + one row per harness version"
  smoke_assert_eq "$(printf '%s\n' "$out" | sed -n 2p | cut -f1)" 0.9.0+abcdef2 "--summary row 1: lowest semver"
  smoke_assert_eq "$(printf '%s\n' "$out" | sed -n 3p | cut -f1)" 0.10.0+abcdef1 "--summary row 2: 0.10.0 sorts AFTER 0.9.0 (semver, not string)"
  check; printf '%s\n' "$out" | sed -n 4p | cut -f1 | grep -Eq '^1\.[0-9]+\.[0-9]+\+[0-9a-f]{7,40}$' || smoke_fail "--summary row 3 should be the smoke item's 1.x stamp, got: $(printf '%s\n' "$out" | sed -n 4p | cut -f1)"
  # (I7) an empty events.log is still an instrumented item (validate.sh uses -f)
  out=$(cd "$w" && scripts/scorecard.sh "$v09")
  row=$(printf '%s\n' "$out" | sed -n 2p)
  smoke_assert_eq "$(cell source)" events "an empty events.log still counts as instrumented"
  rm -rf "${w:?}/work/done/$v09" "${w:?}/work/done/$v010"

  # (I9b) --backfill reaches an epic and its child.
  mkdir -p "$w/work/done/E-20260101-bf/S-20260101-kid"
  printf -- '---\nid: E-20260101-bf\ntype: epic\ntitle: "backfill"\nstatus: done\nrepos: []\nepic: null\ncreated: %s\nupdated: %s\nmr: null\n---\n\n## Activity\n' "$today" "$today" >"$w/work/done/E-20260101-bf/epic.md"
  printf -- '---\nid: S-20260101-kid\ntype: story\ntitle: "backfill child"\nstatus: done\nrepos: []\nepic: E-20260101-bf\ncreated: %s\nupdated: %s\nmr: null\n---\n\n## Activity\n' "$today" "$today" >"$w/work/done/E-20260101-bf/S-20260101-kid/task.md"
  (cd "$w" && scripts/stamp.sh --backfill) >/dev/null
  smoke_assert_grep "$w/work/done/E-20260101-bf/epic.md" '^harness: [0-9]+\.[0-9]+\.[0-9]+\+([0-9a-f]{7,40}|unknown)$'
  smoke_assert_grep "$w/work/done/E-20260101-bf/S-20260101-kid/task.md" '^harness: [0-9]+\.[0-9]+\.[0-9]+\+([0-9a-f]{7,40}|unknown)$'
  rm -rf "${w:?}/work/done/E-20260101-bf"

  # (I9c) Copilot subagent-stop: transcript under COPILOT_HOME/session-state/<subagent id>/.
  mkdir -p "$w/copilot-home/session-state/cp-sub-1"
  # shellcheck disable=SC2031 # false positive: same id as the Task 9 note above.
  sed "s|__ID__|$id|g" "$w/scripts/fixtures/transcript.jsonl" >"$w/copilot-home/session-state/cp-sub-1/events.jsonl"
  (cd "$w" && printf '{"sessionId":"cp-0002","subagentSessionId":"cp-sub-1"}' | COPILOT_HOME="$w/copilot-home" scripts/trace-capture.sh --hook subagent-stop --agent copilot)
  smoke_assert_file "$SMOKE_ITEM/trace/raw/copilot-cp-sub-1.jsonl"
  # (m9) a session id carrying path characters must be refused, not pasted into
  # the unassigned copy path (this transcript only MENTIONS the item, so the
  # copy would land in work/.trace-unassigned/raw/<sid>-<agent>.jsonl).
  mkdir -p "$w/copilot-home/session-state/cp-sub-2"
  sed -n 1p "$w/copilot-home/session-state/cp-sub-1/events.jsonl" >"$w/copilot-home/session-state/cp-sub-2/events.jsonl"
  (cd "$w" && printf '{"sessionId":"../../escape","subagentSessionId":"cp-sub-2"}' | COPILOT_HOME="$w/copilot-home" scripts/trace-capture.sh --hook subagent-stop --agent copilot)
  check; [ -e "$w/work/escape-copilot-cp-sub-2.jsonl" ] && smoke_fail "a session id with ../ must not be used as a path component"
  rm -f "$w/work/escape-copilot-cp-sub-2.jsonl"
  rm -rf "$w/copilot-home"

  # --- export-experience.sh core (proposer-loop plan, Task 1) ---
  store=$(mktemp -d "${TMPDIR:-/tmp}/mos-store.XXXXXX"); store=$(cd "$store" && pwd -P)
  ws=$(basename "$w")
  # two done fixture items sharing one real session transcript; A also has a raw subagent copy
  sess="$w/sess-shared.jsonl"
  # shellcheck disable=SC2031 # false positive: id is set once above, never inside a subshell (see the earlier SC2031 notes)
  sed "s|__ID__|$id|g" "$w/scripts/fixtures/transcript.jsonl" >"$sess"
  for fx in T-20260101-expa T-20260101-expb; do
    mkdir -p "$w/work/done/$fx/trace/raw"
    printf -- '---\nid: %s\ntype: task\ntitle: "%s"\nstatus: done\nrepos: [demo]\nepic: null\ncreated: 2026-01-01\nupdated: 2026-01-02\nmr: https://example.invalid/mr/5\nharness: 0.9.0+abcdef1\nworkspace_rev: abcdef1\n---\n\n## Activity\n\n- 2026-01-01 — created\n' "$fx" "$fx" >"$w/work/done/$fx/task.md"
    printf 'session_id\ttranscript_path\tfirst_seen\tlast_seen\nshared-1\t%s\t2026-01-01T00:00:00Z\t2026-01-01T00:10:00Z\n' "$sess" >"$w/work/done/$fx/trace/sessions.tsv"
  done
  cp "$sess" "$w/work/done/T-20260101-expa/trace/raw/agent-fx.jsonl"
  # The listing covers the workspace ROOT too, so a stray items/ or
  # manifest.tsv written next to work/ would fail this as loudly as a
  # changed file would.
  before=$(cd "$w" && { find work scripts config -type f | LC_ALL=C sort | xargs ls -l | awk '{print $5, $6, $7, $8, $9}'; find . -maxdepth 1 -mindepth 1 | LC_ALL=C sort; })
  out=$(cd "$w" && scripts/export-experience.sh --dest "$store" 2>&1; echo "rc=$?")
  check; printf '%s' "$out" | grep -q '^rc=0$' || smoke_fail "export exits 0, got: $out"
  after=$(cd "$w" && { find work scripts config -type f | LC_ALL=C sort | xargs ls -l | awk '{print $5, $6, $7, $8, $9}'; find . -maxdepth 1 -mindepth 1 | LC_ALL=C sort; })
  smoke_assert_eq "$after" "$before" "export is read-only on the workspace"
  smoke_assert_file "$store/$ws/manifest.tsv"
  smoke_assert_grep "$store/$ws/manifest.tsv" '^id	type	status	harness	parent	source_path	exported_at	sessions_copied	sessions_missing	store_version$'
  smoke_assert_eq "$(grep -c . "$store/$ws/manifest.tsv")" 4 "manifest: header + 3 items (smoke item + 2 fixtures)"
  smoke_assert_grep "$store/$ws/manifest.tsv" "^T-20260101-expa	task	done	0\.9\.0\+abcdef1	-	.*	[0-9T:Z-]+	1	0	1$"
  # shellcheck disable=SC2031 # false positive: id is set once above, never inside a subshell (see the earlier SC2031 notes)
  smoke_assert_grep "$store/$ws/manifest.tsv" "^$id	task	done	[0-9.]+\+[0-9a-f]+	-	.*	[0-9T:Z-]+	0	2	1$"
  smoke_assert_file "$store/$ws/items/T-20260101-expa/task.md"
  smoke_assert_file "$store/$ws/items/T-20260101-expa/trace/raw/agent-fx.jsonl"
  # shellcheck disable=SC2031 # false positive: id is set once above, never inside a subshell (see the earlier SC2031 notes)
  smoke_assert_file "$store/$ws/items/$id/events.log"
  smoke_assert_eq "$(find "$store/$ws/sessions" -maxdepth 1 -type f | grep -c .)" 1 "one shared session copied once"
  smoke_assert_file "$store/$ws/sessions/shared-1.jsonl"
  smoke_assert_grep "$store/$ws/items/T-20260101-expb/trace/sessions.tsv" "^shared-1	$store/$ws/sessions/shared-1\.jsonl	"
  # shellcheck disable=SC2031 # false positive: id is set once above, never inside a subshell (see the earlier SC2031 notes)
  smoke_assert_grep "$store/$ws/items/$id/trace/sessions.tsv" "^smoke-session-0001	$w/transcript\.jsonl	"   # missing at source: pointer unchanged
  # re-export is idempotent for items (manifest row count unchanged)
  (cd "$w" && scripts/export-experience.sh --dest "$store" >/dev/null)
  smoke_assert_eq "$(grep -c . "$store/$ws/manifest.tsv")" 4 "re-export keeps one manifest row per item"
  # explicit id restricts; --workspace-name renames the store folder
  (cd "$w" && scripts/export-experience.sh --dest "$store" --workspace-name alt T-20260101-expb >/dev/null)
  smoke_assert_eq "$(grep -c . "$store/alt/manifest.tsv")" 2 "explicit id: header + 1 row"
  check; [ -d "$store/alt/items/T-20260101-expa" ] && smoke_fail "explicit id must not export other items"
  out=$(cd "$w" && scripts/export-experience.sh 2>&1 || true)
  check; printf '%s' "$out" | grep -q -- '--dest' || smoke_fail "missing --dest must be a usage error, got: $out"
  out=$(cd "$w" && scripts/export-experience.sh --dest "$store/does-not-exist" 2>&1 || true)
  check; printf '%s' "$out" | grep -q 'does not exist' || smoke_fail "missing destination must die, got: $out"

  # --- export-experience.sh sweep, dry-run, snapshots (Task 2) ---
  smoke_assert_eq "$(find "$store/$ws" -maxdepth 1 -name 'scorecard-*.tsv' | grep -c .)" 2 "two exports → two scorecard snapshots"
  smoke_assert_eq "$(find "$store/$ws" -maxdepth 1 -name 'summary-*.tsv' | grep -c .)" 2 "two summary snapshots"
  smoke_assert_file "$store/$ws/config/preferences.md"
  latest=$(find "$store/$ws" -maxdepth 1 -name 'scorecard-*.tsv' | LC_ALL=C sort | tail -1)
  smoke_assert_eq "$(head -1 "$latest" | cut -f1-3)" "id	type	harness" "scorecard snapshot is scorecard.sh output"
  smoke_assert_eq "$(grep -c . "$latest")" 4 "scorecard snapshot: header + 3 items"
  # dry run writes nothing
  store2=$(mktemp -d "${TMPDIR:-/tmp}/mos-store.XXXXXX"); store2=$(cd "$store2" && pwd -P)
  out=$(cd "$w" && scripts/export-experience.sh --dest "$store2" --dry-run)
  check; printf '%s' "$out" | grep -q "would export T-20260101-expa" || smoke_fail "dry-run lists items, got: $out"
  smoke_assert_eq "$(find "$store2" -mindepth 1 | grep -c .)" 0 "dry-run writes nothing"
  # planted token aborts before any write; --ignore-sweep exports with a warning
  mkdir -p "$w/work/done/T-20260101-leak"
  printf -- '---\nid: T-20260101-leak\ntype: task\ntitle: "leak"\nstatus: done\nrepos: []\nepic: null\ncreated: 2026-01-01\nupdated: 2026-01-01\nmr: null\n---\n\n## Activity\n\n- 2026-01-01 — created\n' >"$w/work/done/T-20260101-leak/task.md"
  printf 'aws_key = AKIAABCDEFGHIJKLMNOP\n' >"$w/work/done/T-20260101-leak/01-context.md"
  out=$(cd "$w" && scripts/export-experience.sh --dest "$store2" 2>&1; echo "rc=$?")
  check; printf '%s' "$out" | grep -q '^rc=1$' || smoke_fail "sweep hit exits 1, got: $out"
  check; printf '%s' "$out" | grep -q 'T-20260101-leak/01-context.md:1' || smoke_fail "sweep names file:line, got: $out"
  # the report is file:line only — it must never echo the secret back
  check; printf '%s' "$out" | grep -q 'AKIAABCDEFGHIJKLMNOP' && smoke_fail "sweep output must not repeat the matched secret, got: $out"
  smoke_assert_eq "$(find "$store2" -mindepth 1 | grep -c .)" 0 "sweep hit writes nothing"
  out=$(cd "$w" && scripts/export-experience.sh --dest "$store2" --ignore-sweep 2>&1; echo "rc=$?")
  check; printf '%s' "$out" | grep -q '^rc=0$' || smoke_fail "--ignore-sweep exports, got: $out"
  check; printf '%s' "$out" | grep -qi 'warning' || smoke_fail "--ignore-sweep must warn"
  smoke_assert_file "$store2/$ws/items/T-20260101-leak/01-context.md"
  # destination inside the workspace is refused
  out=$(cd "$w" && scripts/export-experience.sh --dest "$w/work" 2>&1 || true)
  check; printf '%s' "$out" | grep -q 'inside this workspace' || smoke_fail "dest inside workspace must be refused, got: $out"
  # summary line
  out=$(cd "$w" && scripts/export-experience.sh --dest "$store2" --ignore-sweep T-20260101-expa 2>&1)
  check; printf '%s' "$out" | grep -Eq 'exported 1 item\(s\).*session rows resolved 1, missing 0.*scorecard-[0-9T]+Z(_[0-9]+)?\.tsv' || smoke_fail "summary line shape, got: $out"

  # --- export-experience.sh containment, scope and explicit ids (final review) ---
  rm -rf "$w/work/done/T-20260101-leak"   # from here on the sweep is clean again
  store3=$(mktemp -d "${TMPDIR:-/tmp}/mos-store.XXXXXX"); store3=$(cd "$store3" && pwd -P)
  # (C1) the guard runs on the real write target: a --dest whose <name> subfolder
  # IS this workspace must be refused, and nothing may be written into it.
  out=$(cd "$w" && scripts/export-experience.sh --dest "$(dirname "$w")" 2>&1; echo "rc=$?")
  check; printf '%s' "$out" | grep -q '^rc=1$' || smoke_fail "a dest resolving onto the workspace must exit 1, got: $out"
  check; printf '%s' "$out" | grep -q 'inside this workspace' || smoke_fail "a dest resolving onto the workspace must be refused, got: $out"
  check; [ -e "$w/manifest.tsv" ] && smoke_fail "a refused export must not write manifest.tsv into the workspace root"
  check; [ -e "$w/items" ] && smoke_fail "a refused export must not write items/ into the workspace root"
  out=$(cd "$w" && scripts/export-experience.sh --dest "$store3" --workspace-name .. 2>&1; echo "rc=$?")
  check; printf '%s' "$out" | grep -q '^rc=1$' || smoke_fail "--workspace-name .. must exit 1, got: $out"
  check; printf '%s' "$out" | grep -q 'must match' || smoke_fail "--workspace-name .. must be refused, got: $out"
  # (I4a) an epic and its child export as two flat items; the child names its parent
  mkdir -p "$w/work/done/E-20260101-ep/S-20260101-kid"
  printf -- '---\nid: E-20260101-ep\ntype: epic\ntitle: "ep"\nstatus: done\nrepos: [demo]\nepic: null\ncreated: 2026-01-01\nupdated: 2026-01-02\nmr: null\nharness: 0.9.0+abcdef1\n---\n\n## Activity\n\n- 2026-01-01 — created\n' >"$w/work/done/E-20260101-ep/epic.md"
  printf -- '---\nid: S-20260101-kid\ntype: story\ntitle: "kid"\nstatus: done\nrepos: [demo]\nepic: E-20260101-ep\ncreated: 2026-01-01\nupdated: 2026-01-02\nmr: null\nharness: 0.9.0+abcdef1\n---\n\n## Activity\n\n- 2026-01-01 — created\n' >"$w/work/done/E-20260101-ep/S-20260101-kid/task.md"
  (cd "$w" && scripts/export-experience.sh --dest "$store3" >/dev/null)
  smoke_assert_file "$store3/$ws/items/S-20260101-kid/task.md"
  check; [ -e "$store3/$ws/items/E-20260101-ep/S-20260101-kid" ] && smoke_fail "an epic's copy must not carry its child item"
  smoke_assert_grep "$store3/$ws/manifest.tsv" '^S-20260101-kid	story	done	0\.9\.0\+abcdef1	E-20260101-ep	'
  smoke_assert_grep "$store3/$ws/manifest.tsv" '^E-20260101-ep	epic	done	'
  # (I4b) active items stay out until --include-active asks for them
  mkdir -p "$w/work/active/T-20260101-act"
  printf -- '---\nid: T-20260101-act\ntype: task\ntitle: "act"\nstatus: executing\nrepos: [demo]\nepic: null\ncreated: 2026-01-01\nupdated: 2026-01-02\nmr: null\nharness: 0.9.0+abcdef1\n---\n\n## Activity\n\n- 2026-01-01 — created\n' >"$w/work/active/T-20260101-act/task.md"
  printf '2026-01-01T00:00:00Z\tcreated\ttype=task\n' >"$w/work/active/T-20260101-act/events.log"
  (cd "$w" && scripts/export-experience.sh --dest "$store3" >/dev/null)
  check; [ -e "$store3/$ws/items/T-20260101-act" ] && smoke_fail "an active item must not export without --include-active"
  (cd "$w" && scripts/export-experience.sh --dest "$store3" --include-active >/dev/null)
  smoke_assert_file "$store3/$ws/items/T-20260101-act/task.md"
  smoke_assert_file "$store3/$ws/items/T-20260101-act/events.log"
  # (I4c) an unknown explicit id is a runtime error, not an empty export
  out=$(cd "$w" && scripts/export-experience.sh --dest "$store3" T-does-not-exist 2>&1; echo "rc=$?")
  check; printf '%s' "$out" | grep -q '^rc=1$' || smoke_fail "an unknown id must exit 1, got: $out"
  check; printf '%s' "$out" | grep -q 'no work item' || smoke_fail "an unknown id must say so, got: $out"
  # (M1) an explicit id outside the selected states is refused, not exported
  mkdir -p "$w/work/backlog/T-20260101-bk"
  printf -- '---\nid: T-20260101-bk\ntype: task\ntitle: "bk"\nstatus: intake\nrepos: [demo]\nepic: null\ncreated: 2026-01-01\nupdated: 2026-01-01\nmr: null\nharness: 0.9.0+abcdef1\n---\n\n## Activity\n\n- 2026-01-01 — created\n' >"$w/work/backlog/T-20260101-bk/task.md"
  out=$(cd "$w" && scripts/export-experience.sh --dest "$store3" T-20260101-bk 2>&1; echo "rc=$?")
  check; printf '%s' "$out" | grep -q '^rc=1$' || smoke_fail "a backlog id must exit 1, got: $out"
  check; printf '%s' "$out" | grep -q 'only done items' || smoke_fail "a backlog id must be refused, got: $out"
  check; [ -e "$store3/$ws/items/T-20260101-bk" ] && smoke_fail "a refused explicit id must not be exported"
  rm -rf "$store" "$store2" "$store3" "$w/work/done/T-20260101-expa" "$w/work/done/T-20260101-expb" "$w/work/done/T-20260101-leak" "$w/work/done/E-20260101-ep" "$w/work/active/T-20260101-act" "$w/work/backlog/T-20260101-bk" "$sess"

  # --- proposer-loop docs (Task 3) ---
  smoke_assert_grep "$(mos_root)/knowledge/runbooks/export-experience.md" '^type: Runbook$'
  smoke_assert_grep "$(mos_root)/knowledge/runbooks/index.md" 'export-experience.md'
  smoke_assert_file "$(mos_root)/.claude/commands/export-experience.md"
  smoke_assert_file "$(mos_root)/.github/prompts/export-experience.prompt.md"
  smoke_assert_grep "$(mos_root)/knowledge/decisions/proposer-loop-separate-repo.md" '^type: Decision$'
  smoke_assert_grep "$(mos_root)/knowledge/decisions/index.md" 'proposer-loop-separate-repo.md'
  smoke_assert_grep "$(mos_root)/workflow/WORKFLOW.md" 'export-experience.sh'
  smoke_assert_grep "$(mos_root)/README.md" 'export-experience'
  smoke_assert_eq "$(head -1 "$(mos_root)/VERSION")" "1.1.0" "VERSION is 1.1.0"
  smoke_assert_grep "$(mos_root)/CHANGELOG.md" '^## 1\.1\.0 — [0-9]{4}-[0-9]{2}-[0-9]{2}$'

  : # Keep this bare `:` as the LAST statement of run_smoke. Several
    # assertions here are "should NOT match" greps whose expected miss exits
    # 1; whichever one ends up last would otherwise become run_smoke's return
    # status and trip the caller's `set -e`/ERR trap even though nothing is
    # wrong. Append new smoke blocks ABOVE this line.
}

# shellcheck disable=SC2031 # false positive: mode is set once above (lines
# 36/39) in a top-level case, never inside a subshell; shellcheck misreads a
# long &&-chained subshell inside run_smoke() as reassigning it (confirmed
# by bisection — removing that subshell block silences this finding).
if [ "$mode" = harness ]; then
  run_harness_checks
fi

root=$(mos_root)
today=$(mos_today)
cutoff30=$(mos_days_ago_iso 30 || true)

if [ -d "$root/work" ]; then
  while IFS= read -r work_doc; do
    [ -n "$work_doc" ] || continue
    validate_work_doc "$work_doc"
  done < <(find "$root/work" -type f \( -name task.md -o -name epic.md \) | LC_ALL=C sort)
fi

if [ -d "$root/knowledge" ]; then
  # The knowledge format this harness's templates and checks support. Bumped
  # by the kb-migrate runbook together with the checks themselves, so a
  # mismatch against the knowledge base's own stamp means "the harness moved
  # ahead of your docs" — typically right after pulling template updates from
  # upstream.
  SUPPORTED_OKF_VERSION="0.2"
  check
  if [ -f "$root/knowledge/index.md" ]; then
    kb_version=$(mos_frontmatter_field "$root/knowledge/index.md" okf_version || true)
    if [ -z "$kb_version" ]; then
      v_warn "knowledge/index.md: no okf_version stamp — add 'okf_version: \"$SUPPORTED_OKF_VERSION\"' frontmatter so format drift is detectable"
    elif [ "$kb_version" != "$SUPPORTED_OKF_VERSION" ]; then
      v_warn "knowledge/index.md: knowledge base is stamped okf_version \"$kb_version\" but this harness supports \"$SUPPORTED_OKF_VERSION\" — run the kb-migrate runbook (knowledge/runbooks/kb-migrate.md)"
    fi
  fi

  # knowledge/bundles/ holds vendored external bundles — read-only reference
  # material that may not follow this workspace's type vocabulary. Skip it.
  # index.md and log.md are OKF reserved filenames — listings and history,
  # not concept docs; neither carries concept frontmatter.
  while IFS= read -r kb_doc; do
    [ -n "$kb_doc" ] || continue
    validate_kb_doc "$kb_doc"
  done < <(find "$root/knowledge" -type d -path "$root/knowledge/bundles" -prune -o -type f -name '*.md' ! -name 'index.md' ! -name 'log.md' -print | LC_ALL=C sort)
fi

if [ "$errors" -gt 0 ]; then
  printf 'validate: FAILED — %s error(s), %s checks\n' "$errors" "$checks" >&2
  exit 1
fi

printf 'validate: OK (%s checks)\n' "$checks"
