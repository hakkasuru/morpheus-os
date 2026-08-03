#!/usr/bin/env bash
# sync-bundles.sh — clone or update every knowledge bundle in config/bundles.yaml.
# Bundles are vendored, read-only reference material under knowledge/bundles/
# (gitignored). Writes nothing outside knowledge/bundles/.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: sync-bundles.sh [--bundle <name>]

Clone every knowledge bundle listed in config/bundles.yaml into
knowledge/bundles/<name>, or fast-forward it when it is already there.
Idempotent; nothing outside knowledge/bundles/ is touched.

Options:
  --bundle <name>   sync only this bundle
  -h, --help        show this help
EOF
}

usage_error() {
  printf 'error: %s\n' "$*" >&2
  usage >&2
  exit 2
}

bundle_filter=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --bundle)
      [ $# -ge 2 ] || usage_error "--bundle requires a name"
      bundle_filter="$2"
      shift 2
      ;;
    --bundle=*)
      bundle_filter="${1#--bundle=}"
      [ -n "$bundle_filter" ] || usage_error "--bundle requires a name"
      shift
      ;;
    *) usage_error "unexpected argument: $1" ;;
  esac
done

root=$(mos_root)
registry=$(mos_bundles_path)

sync_one() {
  local name="$1" dest remote ref
  dest="$root/knowledge/bundles/$name"

  if [ -d "$dest/.git" ]; then
    # Vendored and read-only by convention: only a fast-forward is safe. A
    # refused pull means someone edited the vendored copy — surface it.
    git -C "$dest" pull --ff-only ||
      mos_die "update failed for bundle '$name' — knowledge/bundles/$name has local changes or diverged; vendored bundles are read-only, restore it (or remove it and re-run sync-bundles.sh)"
    printf 'sync: bundle %s updated\n' "$name"
  else
    if [ -e "$dest" ]; then
      mos_die "knowledge/bundles/$name exists but is not a git repository — remove it, then re-run sync-bundles.sh"
    fi
    remote=$(mos_yaml_bundle_field "$name" remote || true)
    [ -n "$remote" ] || mos_die "bundle '$name' has no 'remote:' in $registry"
    ref=$(mos_yaml_bundle_field "$name" ref || true)
    mkdir -p "$root/knowledge/bundles"
    if [ -n "$ref" ]; then
      git clone --branch "$ref" "$remote" "$dest" ||
        mos_die "clone failed for bundle '$name' from $remote (ref $ref) — check the URL, ref and your credentials"
    else
      git clone "$remote" "$dest" ||
        mos_die "clone failed for bundle '$name' from $remote — check the URL and your credentials"
    fi
    printf 'sync: bundle %s cloned\n' "$name"
  fi
}

names=$(mos_yaml_bundle_names || true)
if [ -z "$names" ]; then
  [ -z "$bundle_filter" ] ||
    mos_die "bundle '$bundle_filter' is not in $registry — no bundles are registered"
  printf 'sync: no bundles registered in %s\n' "$registry"
  exit 0
fi

if [ -n "$bundle_filter" ]; then
  case "
$names
" in
    *"
$bundle_filter
"*) : ;;
    *) mos_die "bundle '$bundle_filter' is not in $registry — known names: $(printf '%s' "$names" | tr '\n' ' ')" ;;
  esac
  names="$bundle_filter"
fi

count=0
# fd 3 keeps stdin free for git (credential prompts).
while IFS= read -r name <&3; do
  [ -n "$name" ] || continue
  sync_one "$name"
  count=$((count + 1))
done 3<<EOF
$names
EOF

printf 'sync: %s bundle(s) up to date\n' "$count"
