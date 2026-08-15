#!/usr/bin/env bash
# lib.sh — shared helpers for the Morpheus OS scripts.
# Sourced by sync-repos.sh, new-work.sh, worktree.sh, validate.sh.
# bash 3.2 compatible; no GNU-only flags. No side effects on source.
set -euo pipefail

# --- guard: this file is a library ------------------------------------------
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    -h | --help)
      cat <<'EOF'
Usage: . scripts/lib.sh

Shared helper library for the Morpheus OS scripts. Not executable on its own;
source it from another script:

  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
  . "$SCRIPT_DIR/lib.sh"
EOF
      exit 0
      ;;
  esac
  printf 'error: %s is meant to be sourced, not executed\n' "${BASH_SOURCE[0]}" >&2
  exit 2
fi

# --- basics -----------------------------------------------------------------

# mos_root — absolute path of the workspace root (the parent of scripts/).
# Computed on every call, never cached in a variable: a cache the environment can
# pre-seed would let an inherited value silently relocate the whole workspace.
mos_root() {
  local root
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P) ||
    mos_die "cannot resolve the workspace root from ${BASH_SOURCE[0]}"
  printf '%s\n' "$root"
}

# mos_die "<msg>" — print an error to stderr and exit 1.
mos_die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

# mos_warn "<msg>" — print a warning to stderr; never fatal.
mos_warn() {
  printf 'warning: %s\n' "$*" >&2
  return 0
}

# mos_today — UTC date as YYYY-MM-DD.
mos_today() {
  date -u +%Y-%m-%d
}

# mos_today_compact — UTC date as YYYYMMDD.
mos_today_compact() {
  date -u +%Y%m%d
}

# mos_days_ago_iso <n> — UTC date n days ago as YYYY-MM-DD.
# Uses perl because `date -d` (GNU) and `date -v` (BSD) are both non-portable.
# Returns 1 without output when perl is unavailable, so callers can skip.
mos_days_ago_iso() {
  local days="${1:-0}"
  case "$days" in
    '' | *[!0-9]*) return 1 ;;
  esac
  command -v perl >/dev/null 2>&1 || return 1
  perl -e 'my @t = gmtime(time - $ARGV[0] * 86400); printf "%04d-%02d-%02d\n", $t[5]+1900, $t[4]+1, $t[3];' "$days"
}

# mos_slugify "<string>" — lowercase, non-alphanumerics to "-", squeezed/trimmed.
# LC_ALL=C keeps `tr`/`sed` byte-oriented (macOS tr rejects multibyte input
# otherwise). The result goes through a variable so the trailing newline is
# ours: fed input without a final newline, BSD sed emits none and GNU sed does.
mos_slugify() {
  local text slug translit
  text="${1:-}"
  # Transliterate accents to ASCII when iconv can. Adopt the result only on
  # success — a failing iconv may emit PARTIAL output before dying, and
  # partial + fallback would concatenate garbage.
  if command -v iconv >/dev/null 2>&1; then
    if translit=$(printf '%s' "$text" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null); then
      text="$translit"
    fi
  fi
  slug=$(printf '%s' "$text" |
    LC_ALL=C tr '\n' '-' |
    LC_ALL=C tr '[:upper:]' '[:lower:]' |
    LC_ALL=C sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-*$//')
  printf '%s\n' "$slug"
}

# --- YAML (registry) parsing ------------------------------------------------
# One awk program serves all registry queries so there is exactly one parser.
# It is indentation-aware: an entry starts at "  - id: <value>", the entry's own
# scalar fields sit at the indent of that "id" key, and anything deeper (the
# commands: sub-block) can never leak into a field lookup.

# mos__awk_scalar — awk prelude: value trimming / unquoting helpers.
mos__awk_scalar() {
  cat <<'AWK'
function mos_trim(v) {
  # \r: tolerate CRLF-authored files — both parsers route values through here
  sub(/^[ \t]+/, "", v)
  sub(/[ \t\r]+$/, "", v)
  return v
}
function mos_scalar(v, strip_comment,   q, first, last) {
  if (strip_comment) sub(/[ \t]+#.*$/, "", v)
  v = mos_trim(v)
  q = sprintf("%c", 39)
  if (length(v) >= 2) {
    first = substr(v, 1, 1)
    last = substr(v, length(v), 1)
    if ((first == "\"" && last == "\"") || (first == q && last == q))
      v = substr(v, 2, length(v) - 2)
  }
  return v
}
AWK
}

# mos_registry_path — absolute path of config/repos.yaml.
mos_registry_path() {
  printf '%s/config/repos.yaml\n' "$(mos_root)"
}

# mos_usage_error "<msg>" — usage-error contract shared by every CLI:
# error to stderr, the caller's usage() to stderr, exit 2. Each script
# defines its own usage() before first use.
mos_usage_error() {
  printf 'error: %s\n' "$*" >&2
  usage >&2
  exit 2
}

# mos_bundles_path — absolute path of config/bundles.yaml.
mos_bundles_path() {
  printf '%s/config/bundles.yaml\n' "$(mos_root)"
}

# mos__yaml_query <ids|field|commands> [id] [field] [warn] [file] [entry-key]
# warn=1 reports list items this parser has to skip; only the registry-wide
# reads ask for it, so a single command prints such a warning once rather than
# per query. file/entry-key default to the repo registry keyed by "id" — the
# bundle helpers pass config/bundles.yaml keyed by "name".
mos__yaml_query() {
  local mode="$1" want_id="${2:-}" want_field="${3:-}" warn="${4:-0}" registry ekey
  registry="${5:-$(mos_registry_path)}"
  ekey="${6:-id}"
  [ -f "$registry" ] || mos_die "registry not found: $registry"
  awk -v mode="$mode" -v want_id="$want_id" -v want_field="$want_field" -v warn="$warn" -v ekey="$ekey" \
    "$(mos__awk_scalar)"'
{
  line = $0
  if (line ~ /^[ \t]*$/) next
  if (line ~ /^[ \t]*#/) next
  indent = match(line, /[^ ]/) - 1

  if (line ~ /^[ ]*-([ ]|$)/) {          # a sequence item
    # entry start: "  - <entry-key>: <value>"
    if (line ~ ("^[ ]*-[ ]+" ekey ":")) {
      p = index(line, ekey ":")
      field_indent = p - 1
      entry_indent = indent
      cmd_indent = -1
      in_commands = 0
      cur = mos_scalar(substr(line, p + length(ekey) + 1), 1)
      in_entry = (cur == want_id)
      if (mode == "ids" && cur != "") {
        if (warn == 1 && (cur in mos_seen)) {
          printf "warning: %s:%d: duplicate entry \"%s\" — lookups use the first occurrence\n", FILENAME, FNR, cur > "/dev/stderr"
        }
        mos_seen[cur] = 1
        print cur
      }
      next
    }
    # A registry entry is recognised by the entry key being its first key.
    # Anything else is skipped — say so instead of dropping the entry silently.
    if (entry_indent == "" || indent == entry_indent) {
      in_entry = 0
      in_commands = 0
      if (warn == 1) {
        printf "warning: %s:%d: sequence item has no \"%s:\" as its first key — this entry is ignored; write it as \"- %s: <value>\"\n", FILENAME, FNR, ekey, ekey > "/dev/stderr"
      }
      next
    }
  }
  if (field_indent == 0) next            # nothing seen yet: outside all entries
  if (indent <= entry_indent) {          # dedented out of the entry list
    in_entry = 0
    in_commands = 0
    next
  }

  if (indent == field_indent) {          # a scalar field of the current entry
    c = index(line, ":")
    if (c == 0) next
    key = mos_trim(substr(line, 1, c - 1))
    if (key == "commands") {
      in_commands = 1
      cmd_indent = -1
      next
    }
    in_commands = 0
    if (mode == "field" && in_entry && key == want_field) {
      print mos_scalar(substr(line, c + 1), 1)
      found = 1
      exit 0
    }
    next
  }

  # deeper than the entry fields: only the commands: sub-block is of interest
  if (mode == "commands" && in_entry && in_commands) {
    if (cmd_indent < 0) cmd_indent = indent
    if (indent != cmd_indent) next       # ignore anything nested deeper
    c = index(line, ":")
    if (c == 0) next
    key = mos_trim(substr(line, 1, c - 1))
    if (key == "") next
    printf "%s\t%s\n", key, mos_scalar(substr(line, c + 1), 1)
  }
}
END { if (mode == "field") exit (found ? 0 : 1) }
' "$registry"
}

# mos_yaml_repo_ids — every top-level entry id, one per line.
# This is the registry-wide read, so it is the one that warns about entries the
# parser had to skip.
mos_yaml_repo_ids() {
  mos__yaml_query ids "" "" 1
}

# mos_yaml_repo_field <id> <field> — scalar field of one entry.
# Empty output + return 1 when the entry or the field is absent.
mos_yaml_repo_field() {
  [ $# -eq 2 ] || mos_die "mos_yaml_repo_field: need <id> <field>"
  mos__yaml_query field "$1" "$2"
}

# mos_yaml_repo_commands <id> — the commands: sub-block as "name<TAB>command".
mos_yaml_repo_commands() {
  [ $# -eq 1 ] || mos_die "mos_yaml_repo_commands: need <id>"
  mos__yaml_query commands "$1"
}

# mos_repo_branch_prefix <id> — the branch prefix task branches use in this
# repo: the entry's optional 'branch_prefix:' (taken verbatim — include your
# separator, e.g. "feature/" or "dev-"), or "work/" when unset. Lets repos
# follow org-enforced branch naming without touching the scripts.
mos_repo_branch_prefix() {
  [ $# -eq 1 ] || mos_die "mos_repo_branch_prefix: need <id>"
  local prefix
  prefix=$(mos_yaml_repo_field "$1" branch_prefix || true)
  if [ -z "$prefix" ]; then
    printf 'work/\n'
    return 0
  fi
  case "$prefix" in
    *[\ \	]* | -*) mos_die "repo '$1': branch_prefix '$prefix' is not a valid branch prefix (no whitespace, no leading '-')" ;;
  esac
  printf '%s\n' "$prefix"
}

# mos_yaml_bundle_names — every bundle name from config/bundles.yaml, one per
# line. Registry-wide read, so it carries the skipped-entry warning.
mos_yaml_bundle_names() {
  mos__yaml_query ids "" "" 1 "$(mos_bundles_path)" name
}

# mos_yaml_bundle_field <name> <field> — scalar field of one bundle entry.
# Empty output + return 1 when the entry or the field is absent.
mos_yaml_bundle_field() {
  [ $# -eq 2 ] || mos_die "mos_yaml_bundle_field: need <name> <field>"
  mos__yaml_query field "$1" "$2" 0 "$(mos_bundles_path)" name
}

# mos_repo_registered <id> — true when the id exists in the registry.
# Queries quietly: the callers that report a miss print the id list themselves
# (via mos_yaml_repo_ids), which is where the skipped-entry warning belongs.
mos_repo_registered() {
  local want="${1:-}" id
  [ -n "$want" ] || return 1
  while IFS= read -r id; do
    if [ "$id" = "$want" ]; then
      return 0
    fi
  done <<EOF
$(mos__yaml_query ids)
EOF
  return 1
}

# --- hosts ------------------------------------------------------------------

# mos__detect_host <id> — echo the host, or return 1 without output.
# Never dies: callers that only want to probe (mos_check_host_cli) must not be
# torn down, and `$(fn || true)` cannot rescue a die because `exit` inside a
# command substitution skips the `|| true` and leaves status 1 for `set -e`.
mos__detect_host() {
  local id="${1:-}" host remote
  [ -n "$id" ] || return 1
  host=$(mos_yaml_repo_field "$id" host || true)
  if [ -n "$host" ]; then
    printf '%s\n' "$host"
    return 0
  fi
  remote=$(mos_yaml_repo_field "$id" remote || true)
  [ -n "$remote" ] || return 1
  case "$remote" in
    *github.*) printf 'github\n' ;;
    *gitlab.*) printf 'gitlab\n' ;;
    *) return 1 ;;
  esac
}

# mos_repo_host <id> — explicit host: wins, else detected from the remote URL.
mos_repo_host() {
  local id="${1:-}" host remote
  [ -n "$id" ] || mos_die "mos_repo_host: need <id>"
  if host=$(mos__detect_host "$id"); then
    printf '%s\n' "$host"
    return 0
  fi
  remote=$(mos_yaml_repo_field "$id" remote || true)
  [ -n "$remote" ] || mos_die "repo '$id' has no 'remote:' in $(mos_registry_path)"
  mos_die "cannot detect host for repo '$id' from remote '$remote' — add 'host: github' or 'host: gitlab' to that entry in $(mos_registry_path)"
}

# mos_host_cli <host> — the CLI that talks to that host.
mos_host_cli() {
  case "${1:-}" in
    github) printf 'gh\n' ;;
    gitlab) printf 'glab\n' ;;
    *) mos_die "unknown host '${1:-}' — expected 'github' or 'gitlab'" ;;
  esac
}

# mos_check_host_cli <id> — warn-only check that the host CLI is usable.
mos_check_host_cli() {
  local id="${1:-}" host cli
  [ -n "$id" ] || return 0
  if ! host=$(mos__detect_host "$id"); then
    mos_warn "repo '$id': cannot tell whether it lives on github or gitlab — skipping the CLI check; add 'host:' to its entry in $(mos_registry_path)"
    return 0
  fi
  # `cli=$(...) || ...` is safe: a die inside the substitution surfaces as a
  # non-zero status here instead of tearing the calling script down.
  if ! cli=$(mos_host_cli "$host" 2>/dev/null); then
    mos_warn "repo '$id': unknown host '$host' — expected 'github' or 'gitlab'"
    return 0
  fi
  if ! command -v "$cli" >/dev/null 2>&1; then
    mos_warn "repo '$id': '$cli' is not installed — $host operations will not work"
    return 0
  fi
  if ! "$cli" auth status >/dev/null 2>&1; then
    mos_warn "repo '$id': '$cli' is not authenticated — run '$cli auth login'"
  fi
  return 0
}

# --- markdown frontmatter ---------------------------------------------------

# mos_frontmatter_field <file> <field> — scalar from the first --- ... --- block.
# Empty output + return 1 when the file has no frontmatter or the field is absent.
mos_frontmatter_field() {
  [ $# -eq 2 ] || mos_die "mos_frontmatter_field: need <file> <field>"
  local file="$1" field="$2"
  [ -f "$file" ] || return 1
  awk -v want="$field" \
    "$(mos__awk_scalar)"'
NR == 1 {
  if (mos_trim($0) != "---") exit 1
  next
}
{
  if (mos_trim($0) == "---") exit (found ? 0 : 1)
  if (match($0, /^[A-Za-z_][A-Za-z0-9_.-]*:/)) {
    key = substr($0, 1, RLENGTH - 1)
    if (key == want) {
      # strip_comment=1: template frontmatter carries inline "# ..." hints
      # (e.g. stale_after: null # YYYY-MM-DD — ...), same as the registry.
      print mos_scalar(substr($0, RLENGTH + 1), 1)
      found = 1
      exit 0
    }
  }
}
END { exit (found ? 0 : 1) }
' "$file"
}
