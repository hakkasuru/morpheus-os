#!/usr/bin/env bash
# status.sh — read-only workspace dashboard. Costs zero model tokens:
# run it instead of asking an agent "where are we?".
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: status.sh

Print a read-only snapshot of the workspace: work items by state (flagging
gates waiting on you and blocked items), active worktrees (flagging
orphans), repo clone state, and validate.sh warnings.

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

root=$(mos_root)

# --- Work items -------------------------------------------------------------
printf '== Work items ==\n'
found_work=0
for state in backlog active "done"; do
  dir="$root/work/$state"
  [ -d "$dir" ] || continue
  while IFS= read -r doc; do
    [ -n "$doc" ] || continue
    found_work=1
    folder=$(dirname "$doc")
    id=$(basename "$folder")
    status=$(mos_frontmatter_field "$doc" status || true)
    updated=$(mos_frontmatter_field "$doc" updated || true)
    flag=""
    case "$status" in
      plan-review | impl-review)
        # the gate doc's own status says whether it's on the human's desk
        gate_doc="$folder/02-plan.md"
        [ "$status" = "impl-review" ] && gate_doc="$folder/03-implementation-plan.md"
        gate_state=""
        [ -f "$gate_doc" ] && gate_state=$(mos_frontmatter_field "$gate_doc" status || true)
        [ "$gate_state" = "in-review" ] && flag="  <-- WAITING ON YOU (approve/revise)"
        ;;
      delivering) flag="  <-- WAITING ON YOU (confirm delivery)" ;;
      blocked)
        unblock=$(grep -E -- '- [0-9]{4}-[0-9]{2}-[0-9]{2} — blocked ' "$doc" 2>/dev/null | tail -1 || true)
        flag="  <-- BLOCKED${unblock:+: ${unblock#*— }}"
        ;;
    esac
    printf '  %-8s %-45s %-13s %s%s\n' "$state" "$id" "${status:-?}" "${updated:-}" "$flag"
  done < <(find "$dir" -type f \( -name task.md -o -name epic.md \) 2>/dev/null | LC_ALL=C sort)
done
[ "$found_work" -eq 1 ] || printf '  (none)\n'

# --- Worktrees --------------------------------------------------------------
printf '\n== Worktrees ==\n'
found_wt=0
for wt in "$root"/worktrees/*--*; do
  [ -d "$wt" ] || continue
  found_wt=1
  name=$(basename "$wt")
  work_id="${name#*--}"
  orphan="  <-- ORPHAN? no active work item"
  # a worktree is accounted for when its work-id folder exists under work/active/
  if find "$root/work/active" -maxdepth 3 -type d -name "$work_id" 2>/dev/null | grep -q .; then
    orphan=""
  fi
  printf '  %s%s\n' "$name" "$orphan"
done
[ "$found_wt" -eq 1 ] || printf '  (none)\n'

# --- Repos ------------------------------------------------------------------
printf '\n== Repos ==\n'
while IFS= read -r id; do
  [ -n "$id" ] || continue
  if [ -d "$root/repos/$id/.git" ]; then
    printf '  %-30s cloned\n' "$id"
  else
    printf '  %-30s MISSING — scripts/sync-repos.sh --repo %s\n' "$id" "$id"
  fi
done < <(mos_yaml_repo_ids 2>/dev/null || true)

# --- Validation -------------------------------------------------------------
printf '\n== Validation ==\n'
warn_file="${TMPDIR:-/tmp}/mos-status-warnings.$$"
if "$SCRIPT_DIR/validate.sh" 2>"$warn_file" >/dev/null; then
  wcount=$(grep -c '^warning:' "$warn_file" 2>/dev/null || true)
  if [ "${wcount:-0}" -gt 0 ]; then
    printf '  OK with %s warning(s):\n' "$wcount"
    sed -n 's/^warning: /    - /p' "$warn_file"
  else
    printf '  OK, no warnings\n'
  fi
else
  printf '  FAILING — run scripts/validate.sh for details:\n'
  sed -n 's/^error: /    - /p' "$warn_file" | head -10
fi
rm -f "$warn_file"
