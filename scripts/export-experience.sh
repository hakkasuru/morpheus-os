#!/usr/bin/env bash
# export-experience.sh — copy finished work items (docs, events.log, trace/
# incl. raw transcripts, and the session transcripts they point at) plus
# scorecard and preferences snapshots into an EXPERIENCE STORE outside this
# workspace, for a separate proposer repo to read. Read-only on the
# workspace: it never creates, changes or removes anything under it.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: export-experience.sh --dest <store> [--workspace-name <name>] [--include-active]
                            [--dry-run] [--ignore-sweep] [<work-id> ...]

Copy this workspace's run record into <store>/<name>/ (store layout v1):
  manifest.tsv               one row per exported item
  scorecard-<ts>.tsv         scripts/scorecard.sh rows at export time
  summary-<ts>.tsv           scripts/scorecard.sh --summary at export time
  config/preferences.md      snapshot of config/preferences.md
  items/<id>/                verbatim copy of the work item folder (an epic's
                             copy excludes its children — they are items)
  sessions/<sid>.jsonl       each session transcript once; copied items'
                             trace/sessions.tsv point at these copies

Default scope: every item under work/done/ (epic children included).
A secrets sweep (cloud keys, private keys, host/API tokens) runs over
everything before the first write; any hit aborts with file:line.

Options:
  --dest <store>           destination directory (must exist, outside this workspace)
  --workspace-name <name>  store subfolder; default: this workspace folder's name
  --include-active         also export items under work/active/
  --dry-run                list what would be exported; write nothing
  --ignore-sweep           export despite sweep hits (warns loudly)
  <work-id> ...            only these items
  -h, --help               show this help
EOF
}

STORE_VERSION=1
dest="" wsname="" include_active=no dry=no ignore_sweep=no only=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dest)
      [ $# -ge 2 ] || mos_usage_error "--dest requires a path"
      dest="$2"; shift ;;
    --dest=*) dest="${1#--dest=}" ;;
    --workspace-name)
      [ $# -ge 2 ] || mos_usage_error "--workspace-name requires a name"
      wsname="$2"; shift ;;
    --workspace-name=*) wsname="${1#--workspace-name=}" ;;
    --include-active) include_active=yes ;;
    --dry-run) dry=yes ;;
    --ignore-sweep) ignore_sweep=yes ;;
    -h | --help) usage; exit 0 ;;
    -*) mos_usage_error "unknown option: $1" ;;
    *) only="$only $1" ;;
  esac
  shift
done
[ -n "$dest" ] || mos_usage_error "--dest <store> is required"

root=$(mos_root)
[ -d "$dest" ] || mos_die "destination '$dest' does not exist — create the store directory first"
dest=$(cd "$dest" && pwd -P)
case "$dest/" in
  "$root/"*) mos_die "destination '$dest' is inside this workspace — the store must live outside it" ;;
esac
[ -n "$wsname" ] || wsname=$(basename "$root")
case "$wsname" in
  '.' | '..' | '' | *[!A-Za-z0-9._-]*) mos_die "workspace name '$wsname' must match [A-Za-z0-9._-]+ and cannot be '.' or '..'" ;;
esac
# The guard above reads best for the common case, but the real write target is
# <dest>/<name>: check that too, both ways round — it may BE this workspace
# (--dest <parent of workspace>), or contain it.
target="$dest/$wsname"
case "$target/" in
  "$root/"*) mos_die "destination '$target' is inside this workspace — the store must live outside it" ;;
esac
case "$root/" in
  "$target/"*) mos_die "destination '$target' contains this workspace — pick a store outside it" ;;
esac
now=$(mos_now_iso)
stamp=$(date -u +%Y%m%dT%H%M%SZ)

# --- selection ----------------------------------------------------------------
# select_items — absolute item folders, one per line (top-level + epic children).
select_items() {
  local s id d state states="done"
  [ "$include_active" = yes ] && states="done active"
  if [ -n "$only" ]; then
    # An explicit id is still bound by the selected states: exporting a
    # backlog or cancelled item by name would put an unfinished record in
    # the store without ever saying so.
    for id in $only; do
      d=$(mos_work_item_dir "$id")
      state=$(printf '%s\n' "${d#"$root"/}" | cut -d/ -f2)
      case " $states " in
        *" $state "*) printf '%s\n' "$d" ;;
        *) mos_die "$id is under work/$state/ — only done items are exported (add --include-active for active ones)" ;;
      esac
    done
    return 0
  fi
  for s in $states; do
    [ -d "$root/work/$s" ] || continue
    find "$root/work/$s" -mindepth 1 -maxdepth 2 -type d \( -name 'T-*' -o -name 'S-*' -o -name 'E-*' \) |
      while IFS= read -r d; do
        [ -f "$d/task.md" ] || [ -f "$d/epic.md" ] || continue
        printf '%s\n' "$d"
      done | LC_ALL=C sort
  done
}

# item_sessions <dir> — "sid<TAB>path" rows from the item's trace/sessions.tsv.
item_sessions() {
  [ -f "$1/trace/sessions.tsv" ] || return 0
  awk -F'\t' 'NR > 1 && NF >= 2 && $1 != "" { print $1 "\t" $2 }' "$1/trace/sessions.tsv"
}

# item_parent <dir> — the enclosing epic id or "-".
item_parent() {
  local p
  p=$(basename "$(dirname "$1")")
  case "$p" in E-*) printf '%s\n' "$p" ;; *) printf -- '-\n' ;; esac
}

items=$(select_items)
if [ -z "$items" ]; then
  if [ "$include_active" = yes ]; then mos_die "nothing to export: no work items under work/done or work/active"; fi
  mos_die "nothing to export: no work items under work/done (add --include-active for active items)"
fi

# --- secrets sweep (before any write) -------------------------------------------
sweep_files() {
  local d sid path
  printf '%s\n' "$items"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    while IFS='	' read -r sid path; do
      [ -n "$sid" ] && [ -f "$path" ] && printf '%s\n' "$path"
    done <<EOF
$(item_sessions "$d")
EOF
  done <<EOF
$items
EOF
  [ -f "$root/config/preferences.md" ] && printf '%s\n' "$root/config/preferences.md"
  return 0
}

# show_hits — print the sweep's file:line list to stderr, workspace-relative.
show_hits() {
  printf '%s\n' "$hits" | sed "s|^$root/|  |" >&2
}

# Only file:line is reported, never the matching text: the report itself
# travels (terminal, logs, a paste to the human) and must not become a second
# copy of the secret.
hits=$(sweep_files | LC_ALL=C sort -u | tr '\n' '\0' | xargs -0 grep -rIEn \
  -e 'AKIA[0-9A-Z]{16}' \
  -e '-----BEGIN [A-Z ]*PRIVATE KEY' \
  -e 'gh[pousr]_[A-Za-z0-9]{36}' \
  -e 'glpat-[A-Za-z0-9_-]{20,}' \
  -e 'xox[baprs]-[A-Za-z0-9-]{10,}' \
  -e 'sk-[A-Za-z0-9_-]{20,}' \
  -e 'Bearer [A-Za-z0-9._~+/=-]{20,}' \
  -e 'AIza[0-9A-Za-z_-]{35}' \
  -- 2>/dev/null | sed 's/:\([0-9][0-9]*\):.*/:\1/' | LC_ALL=C sort -u || true)
if [ -n "$hits" ]; then
  if [ "$ignore_sweep" = yes ]; then
    mos_warn "secrets sweep found token-shaped text — exporting anyway (--ignore-sweep):"
    show_hits
  else
    printf 'error: secrets sweep found token-shaped text — nothing was written. Redact at the source or re-run with --ignore-sweep:\n' >&2
    show_hits
    exit 1
  fi
fi

# --- dry run ------------------------------------------------------------------------
if [ "$dry" = yes ]; then
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    printf 'would export %s (%s session row(s))\n' "$(basename "$d")" "$(item_sessions "$d" | grep -c . || true)"
  done <<EOF
$items
EOF
  printf 'dry run: nothing written (destination %s)\n' "$target"
  exit 0
fi

# --- copy sessions (dedup per workspace) -----------------------------------------
copy_sessions() {
  local d sid path
  mkdir -p "$target/sessions"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    while IFS='	' read -r sid path; do
      [ -n "$sid" ] || continue
      case "$sid" in */* | *..*) mos_warn "skipping session id '$sid' (unsafe path component)"; continue ;; esac
      [ -f "$path" ] || continue
      if [ ! -f "$target/sessions/$sid.jsonl" ] || [ "$path" -nt "$target/sessions/$sid.jsonl" ]; then
        cp "$path" "$target/sessions/$sid.jsonl"
      fi
    done <<EOF
$(item_sessions "$d")
EOF
  done <<EOF
$items
EOF
}

# copy_item <dir> — replace <target>/items/<id> with a copy; drop nested child
# items from an epic's copy; rewrite copied session pointers to the store.
copy_item() {
  local src="$1" id dst tmp
  id=$(basename "$src")
  dst="$target/items/$id"
  mkdir -p "$target/items"
  rm -rf "$dst"
  cp -R "$src" "$dst"
  find "$dst" -mindepth 1 -maxdepth 1 -type d \( -name 'T-*' -o -name 'S-*' \) -exec rm -rf {} +
  if [ -f "$dst/trace/sessions.tsv" ]; then
    tmp="$dst/trace/sessions.tsv.tmp.$$"
    awk -F'\t' -v OFS='\t' -v store="$target/sessions" '
NR == 1 { print; next }
NF >= 2 && $1 !~ /\// && $1 !~ /\.\./ {
  f = store "/" $1 ".jsonl"
  if ((getline line < f) >= 0) { close(f); $2 = f }
}
{ print }' "$dst/trace/sessions.tsv" >"$tmp"
    mv "$tmp" "$dst/trace/sessions.tsv"
  fi
}

# session_counts <dir> — "copied<TAB>missing" for the item's session rows.
session_counts() {
  local sid _path c=0 m=0
  while IFS='	' read -r sid _path; do
    [ -n "$sid" ] || continue
    if [ -f "$target/sessions/$sid.jsonl" ]; then c=$((c + 1)); else m=$((m + 1)); fi
  done <<EOF
$(item_sessions "$1")
EOF
  printf '%s\t%s\n' "$c" "$m"
}

# write_manifest — merge this export's rows into manifest.tsv (replace by id).
write_manifest() {
  local d id doc type status harness parent counts tmp
  tmp="$target/manifest.tsv.tmp.$$"
  {
    printf 'id\ttype\tstatus\tharness\tparent\tsource_path\texported_at\tsessions_copied\tsessions_missing\tstore_version\n'
    if [ -f "$target/manifest.tsv" ]; then
      awk -F'\t' -v ids=" $(printf '%s\n' "$items" | while IFS= read -r d; do basename "$d"; done | paste -sd ' ' -) " '
NR > 1 && index(ids, " " $1 " ") == 0 { print }' "$target/manifest.tsv"
    fi
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      id=$(basename "$d")
      doc=$(mos_work_item_doc "$d")
      type=$(mos_frontmatter_field "$doc" type || printf -- '-')
      status=$(mos_frontmatter_field "$doc" status || printf -- '-')
      harness=$(mos_frontmatter_field "$doc" harness || printf -- '-')
      parent=$(item_parent "$d")
      counts=$(session_counts "$d")
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "${type:--}" "${status:--}" "${harness:--}" "$parent" "${d#"$root"/}" "$now" "$counts" "$STORE_VERSION"
    done <<EOF
$items
EOF
  } >"$tmp"
  mv "$tmp" "$target/manifest.tsv"
}

n_items=$(printf '%s\n' "$items" | grep -c .)
mkdir -p "$target"
copy_sessions
copied=0; missing=0
while IFS= read -r d; do
  [ -n "$d" ] || continue
  copy_item "$d"
  counts=$(session_counts "$d")
  copied=$((copied + ${counts%%	*})); missing=$((missing + ${counts#*	}))
done <<EOF
$items
EOF
write_manifest
# stamp has one-second resolution: two exports within the same second would
# otherwise collide on the same snapshot names and the second silently
# overwrites the first. Widen to a numbered suffix until both names are free;
# `_2` (not `-2`) so a plain sort still puts the newest snapshot last.
snap="$stamp"; n=2
while [ -e "$target/scorecard-$snap.tsv" ] || [ -e "$target/summary-$snap.tsv" ]; do snap="${stamp}_$n"; n=$((n + 1)); done
"$SCRIPT_DIR/scorecard.sh" >"$target/scorecard-$snap.tsv"
"$SCRIPT_DIR/scorecard.sh" --summary >"$target/summary-$snap.tsv"
if [ -f "$root/config/preferences.md" ]; then
  mkdir -p "$target/config" && cp "$root/config/preferences.md" "$target/config/preferences.md"
fi
printf 'exported %s item(s) to %s; session rows resolved %s, missing %s; snapshots scorecard-%s.tsv summary-%s.tsv\n' \
  "$n_items" "$target" "$copied" "$missing" "$snap" "$snap"
