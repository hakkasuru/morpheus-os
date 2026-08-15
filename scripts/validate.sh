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
EOF
}

case "${1:-}" in
  '') : ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) mos_usage_error "unexpected argument: $1" ;;
esac
[ $# -le 1 ] || mos_usage_error "validate.sh takes no arguments"

# The twelve legal work-item statuses — see workflow/WORKFLOW.md.
STATUSES="intake context planning plan-review impl-planning impl-review executing verifying delivering done blocked cancelled"
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
  printf '%s' "${1#"$root"/}"
}

validate_work_doc() {
  local file="$1" folder base doc where wtype status id f
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
          v_warn "$where: status '$status' under work/active/ — expected a phase between context and delivering"
        fi
        ;;
    esac
  fi

  [ "$doc" = "task.md" ] || return 0

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
  if [ -f "$folder/04-verification.md" ] && ! in_set "$status" "executing verifying delivering done"; then
    v_error "$where: 04-verification.md exists while status is '$status' — it may only exist while executing, verifying, delivering or done"
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
