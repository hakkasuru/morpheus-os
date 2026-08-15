#!/usr/bin/env bash
# new-work.sh — scaffold a work item folder from templates/work/.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: new-work.sh <task|story|epic> "<title>" [--parent <epic-folder-path>]

Create work/backlog/<ID>/ containing a single seeded task.md (task, story) or
epic.md (epic). Phase docs are NOT pre-created — each phase creates its own.

  ID = T-|S-|E- + UTC YYYYMMDD + "-" + slugified title

Options:
  --parent <path>   nest under an existing epic folder (must contain epic.md)
  -h, --help        show this help
EOF
}

# sed_escape <string> — escape a replacement string for `s|...|...|`.
sed_escape() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

type=""
title=""
parent=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --parent)
      [ $# -ge 2 ] || mos_usage_error "--parent requires a path"
      parent="$2"
      shift 2
      ;;
    --parent=*)
      parent="${1#--parent=}"
      [ -n "$parent" ] || mos_usage_error "--parent requires a path"
      shift
      ;;
    -*) mos_usage_error "unknown option: $1" ;;
    *)
      if [ -z "$type" ]; then
        type="$1"
      elif [ -z "$title" ]; then
        title="$1"
      else
        mos_usage_error "unexpected argument: $1 (quote the title)"
      fi
      shift
      ;;
  esac
done

[ -n "$type" ] || mos_usage_error "missing type (task|story|epic)"
[ -n "$title" ] || mos_usage_error "missing title"

case "$type" in
  task) prefix="T-" ;;
  story) prefix="S-" ;;
  epic) prefix="E-" ;;
  *) mos_usage_error "invalid type '$type' — expected task, story or epic" ;;
esac

slug=$(mos_slugify "$title")
[ -n "$slug" ] || mos_die "title '$title' produces an empty slug — use at least one letter or digit"

id="${prefix}$(mos_today_compact)-${slug}"
root=$(mos_root)

if [ "$type" = "epic" ]; then
  doc="epic.md"
else
  doc="task.md"
fi
template="$root/templates/work/$doc"
[ -f "$template" ] ||
  mos_die "templates/work/$doc missing — run from a complete checkout"

if [ -n "$parent" ]; then
  [ -d "$parent" ] || mos_die "parent '$parent' is not a directory"
  parent_abs=$(cd "$parent" && pwd -P)
  # Containment: an epic folder outside work/ would escape validate.sh's scan.
  case "$parent_abs/" in
    "$root/work/"*) : ;;
    *) mos_die "parent '$parent' resolves outside this workspace's work/ tree ($parent_abs) — epics live under work/" ;;
  esac
  [ -f "$parent_abs/epic.md" ] ||
    mos_die "parent '$parent' has no epic.md — --parent must point at an epic folder"
  dest="$parent_abs/$id"
else
  dest="$root/work/backlog/$id"
fi

[ ! -e "$dest" ] || mos_die "$dest already exists — refusing to overwrite"

today=$(mos_today)
# {{TITLE}} lands inside a double-quoted YAML scalar — escape \ and " for
# YAML first, then escape the result for the sed replacement.
title_yaml=$(printf '%s' "$title" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
id_e=$(sed_escape "$id")
type_e=$(sed_escape "$type")
title_e=$(sed_escape "$title_yaml")
date_e=$(sed_escape "$today")

mkdir -p "$dest" || mos_die "cannot create $dest"
if ! sed \
  -e "s|{{ID}}|$id_e|g" \
  -e "s|{{TYPE}}|$type_e|g" \
  -e "s|{{TITLE}}|$title_e|g" \
  -e "s|{{DATE}}|$date_e|g" \
  -e "s|{{STATUS}}|intake|g" \
  "$template" >"$dest/$doc" 2>/dev/null; then
  rm -f "$dest/$doc"
  rmdir "$dest" 2>/dev/null || true
  mos_die "failed to write $dest/$doc from $template"
fi

# grep -E: a bare "{" is an undefined BRE, so the token pattern must be ERE.
if grep -qE '\{\{[A-Za-z_]+\}\}' "$dest/$doc"; then
  mos_warn "$dest/$doc still contains unsubstituted {{TOKENS}} — check $template"
fi

printf 'created: %s\n' "$dest/$doc"
