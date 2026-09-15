#!/usr/bin/env bash
# trace-capture.sh — the per-item trace folder (work/<...>/<id>/trace/):
#   path   next free filename for a subagent brief or report (creates dirs)
#   --hook Claude Code / Copilot CLI hook entry point: attribute a session
#          or subagent transcript to the work item(s) it worked on, record
#          pointer rows (sessions.tsv) or copy subagent transcripts (raw/).
# Hooks never fail the agent: once a payload is read, every --hook path exits 0 and prints nothing (a malformed --hook argument list is a usage error, exit 2, like any CLI — the shipped hook configs wrap the call in "|| true").
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: trace-capture.sh path <work-id | folder> brief|report <phase> <agent> [--step <k>]
       trace-capture.sh --hook stop|subagent-stop [--agent claude|copilot]

path    Print the next free path under the item's trace/ folder and create
        the folders:  trace/briefs/<phase>-<agent>[-step<k>]-<n>.md  or
        trace/reports/<phase>-<agent>[-step<k>]-<n>.md.  <phase> is the
        two-digit phase number (01..08); <agent> is explorer, implementer,
        plan-reviewer, diff-reviewer or another agent name ([a-z0-9-]+);
        <n> counts up from 1 per pattern. The orchestrator writes each
        brief there BEFORE dispatching; the implementer writes its report
        to the path the orchestrator put in its brief.

--hook  Read the hook payload (JSON) from stdin.
        stop           end of an agent turn: attribute the session
                       transcript to the work items it touched and upsert
                       a pointer row in each one's trace/sessions.tsv
                       (session_id, transcript_path, first_seen, last_seen).
        subagent-stop  a subagent finished: copy its transcript into each
                       matching item's trace/raw/ (gitignored).
        --agent claude  (default) payload fields session_id,
                        transcript_path, agent_id, agent_transcript_path
        --agent copilot payload field sessionId; the transcript is
                        ${COPILOT_HOME:-~/.copilot}/session-state/<sessionId>/events.jsonl
        A transcript is attributed to an item only when a TOOL-CALL line in
        it names work/<state>/<id>/ or worktrees/<repo>--<id> — a mere
        mention (the session brief listing open items) never counts.
        Unattributed transcripts go to work/.trace-unassigned/. Problems while
        processing a payload are appended to work/.trace-unassigned/hook.log
        and the exit status is 0, so a capture failure can never block the
        agent. Only a malformed argument list (unknown event or --agent) is
        a usage error (exit 2).

Options:
  -h, --help   show this help
EOF
}

[ $# -ge 1 ] || mos_usage_error "missing subcommand (path | --hook)"
case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
esac

root=$(mos_root)

# --- path ---------------------------------------------------------------------
cmd_path() {
  local target="" kind="" phase="" agent="" step="" dir sub base n candidate
  while [ $# -gt 0 ]; do
    case "$1" in
      --step)
        [ $# -ge 2 ] || mos_usage_error "--step requires a number"
        step="$2"
        shift
        ;;
      --step=*) step="${1#--step=}" ;;
      -*) mos_usage_error "unknown option: $1" ;;
      *)
        if [ -z "$target" ]; then target="$1"
        elif [ -z "$kind" ]; then kind="$1"
        elif [ -z "$phase" ]; then phase="$1"
        elif [ -z "$agent" ]; then agent="$1"
        else mos_usage_error "unexpected argument: $1"
        fi
        ;;
    esac
    shift
  done
  [ -n "$agent" ] || mos_usage_error "path needs <work-id | folder> brief|report <phase> <agent>"
  case "$kind" in
    brief) sub=briefs ;;
    report) sub=reports ;;
    *) mos_usage_error "kind must be brief or report, got '$kind'" ;;
  esac
  case "$phase" in
    [0-9][0-9]) : ;;
    *) mos_usage_error "phase must be the two-digit phase number (01..08), got '$phase'" ;;
  esac
  case "$agent" in
    '' | *[!a-z0-9-]*) mos_usage_error "agent must match [a-z0-9-]+, got '$agent'" ;;
  esac
  case "$step" in
    '' | *[!0-9]*) [ -z "$step" ] || mos_usage_error "--step must be a number, got '$step'" ;;
  esac
  dir=$(mos_work_item_dir "$target")
  mkdir -p "$dir/trace/$sub"
  base="$phase-$agent${step:+-step$step}"
  n=1
  while :; do
    candidate="$dir/trace/$sub/$base-$n.md"
    [ -e "$candidate" ] || break
    n=$((n + 1))
  done
  printf '%s\n' "$candidate"
}

# --- hooks ----------------------------------------------------------------------
UNASSIGNED="$root/work/.trace-unassigned"
# A tool-call line, per agent transcript format. Claude Code JSONL carries
# "type":"tool_use" blocks. Copilot events.jsonl: the exact event type is
# confirmed at the Copilot live check (plan Task 14); until then the key
# fragment "tool matches toolName/toolArgs/tool_call style keys.
TOOL_MARKER_CLAUDE='"type": ?"tool_use"'
TOOL_MARKER_COPILOT='"tool'

# safe_path_id <value> — reject an id that would escape the directory it is
# pasted into ("/" or ".." anywhere). Session and subagent ids come from the
# hook payload, and they end up in cp targets and transcript paths.
safe_path_id() {
  case "$1" in
    '' | */* | *..*) return 1 ;;
  esac
  return 0
}

hook_log() {
  mkdir -p "$UNASSIGNED" 2>/dev/null || return 0
  printf '%s\t%s\n' "$(mos_now_iso)" "$*" >>"$UNASSIGNED/hook.log" 2>/dev/null || true
}

# json_field <name> — first string value of "<name>": "…" in $PAYLOAD.
json_field() {
  printf '%s' "$PAYLOAD" | tr -d '\n\r' | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

# item_dir_for_id <id> — folder of a work item (all states, epic children).
item_dir_for_id() {
  find "$root/work" -mindepth 2 -maxdepth 3 -type d -name "$1" 2>/dev/null | head -1
}

# attribute <transcript> <marker-ere> — ids of the work items this transcript
# did tool calls on, one per line. One fixed-string pass over the transcript
# (grep -F -f <all ids>), then the tool-call marker, then the path pattern
# per id in awk.
attribute() {
  local transcript="$1" marker="$2" idfile ids
  idfile=$(mktemp "${TMPDIR:-/tmp}/mos-ids.XXXXXX") || return 0
  find "$root/work" -mindepth 2 -maxdepth 3 -type d \( -name 'T-*' -o -name 'S-*' -o -name 'E-*' \) 2>/dev/null |
    sed 's|.*/||' | LC_ALL=C sort -u >"$idfile"
  if [ ! -s "$idfile" ]; then
    rm -f "$idfile"
    return 0
  fi
  ids=$(paste -sd ' ' "$idfile")
  grep -F -f "$idfile" "$transcript" 2>/dev/null | grep -E -- "$marker" | awk -v ids="$ids" '
BEGIN { n = split(ids, a, " ") }
{
  for (i = 1; i <= n; i++) {
    id = a[i]
    if (hit[id]) continue
    if ($0 ~ ("work/(backlog|active|done)/([^/]+/)?" id "/") || $0 ~ ("worktrees/[^/\"]+--" id)) {
      hit[id] = 1
      print id
    }
  }
}' || true
  rm -f "$idfile"
}

# upsert_session <sessions.tsv> <session_id> <transcript_path>
upsert_session() {
  local file="$1" sid="$2" path="$3" now tmp
  now=$(mos_now_iso)
  mkdir -p "$(dirname "$file")"
  tmp="$file.tmp.$$"
  {
    printf 'session_id\ttranscript_path\tfirst_seen\tlast_seen\n'
    if [ -f "$file" ]; then
      awk -F'\t' -v sid="$sid" -v path="$path" -v now="$now" '
NR == 1 && $1 == "session_id" { next }
$1 == sid { printf "%s\t%s\t%s\t%s\n", sid, path, $3, now; seen = 1; next }
{ print }
END { if (!seen) printf "%s\t%s\t%s\t%s\n", sid, path, now, now }' "$file"
    else
      printf '%s\t%s\t%s\t%s\n' "$sid" "$path" "$now" "$now"
    fi
  } >"$tmp"
  mv "$tmp" "$file"
}

# resolve_session — sets SID, TRANSCRIPT, MARKER from $PAYLOAD for $AGENT.
resolve_session() {
  case "$AGENT" in
    claude)
      SID=$(json_field session_id)
      TRANSCRIPT=$(json_field transcript_path)
      MARKER="$TOOL_MARKER_CLAUDE"
      ;;
    copilot)
      SID=$(json_field sessionId)
      TRANSCRIPT="${COPILOT_HOME:-$HOME/.copilot}/session-state/$SID/events.jsonl"
      MARKER="$TOOL_MARKER_COPILOT"
      ;;
  esac
}

hook_stop() {
  resolve_session
  if [ -z "$SID" ]; then
    hook_log "stop($AGENT): no session id in payload"
    return 0
  fi
  if ! safe_path_id "$SID"; then
    hook_log "stop($AGENT): refusing session id with path characters: $SID"
    return 0
  fi
  if [ ! -f "$TRANSCRIPT" ]; then
    hook_log "stop($AGENT): transcript not found: $TRANSCRIPT (session $SID)"
    return 0
  fi
  ids=$(attribute "$TRANSCRIPT" "$MARKER")
  if [ -z "$ids" ]; then
    upsert_session "$UNASSIGNED/sessions.tsv" "$SID" "$TRANSCRIPT"
    return 0
  fi
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    dir=$(item_dir_for_id "$id")
    [ -n "$dir" ] || continue
    upsert_session "$dir/trace/sessions.tsv" "$SID" "$TRANSCRIPT"
  done <<EOF
$ids
EOF
}

# cmd_hook — AGENT PAYLOAD SID TRANSCRIPT MARKER are declared local here and
# assigned by the helper functions above via bash dynamic scoping; shellcheck
# may flag SC2034/SC2154 on that, which is expected and acceptable.
cmd_hook() {
  local event="" AGENT=claude PAYLOAD SID TRANSCRIPT MARKER ids id dir
  [ $# -ge 1 ] || mos_usage_error "--hook needs stop or subagent-stop"
  event="$1"
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --agent)
        [ $# -ge 2 ] || mos_usage_error "--agent requires claude or copilot"
        AGENT="$2"
        shift
        ;;
      --agent=*) AGENT="${1#--agent=}" ;;
      *) mos_usage_error "unknown option: $1" ;;
    esac
    shift
  done
  case "$AGENT" in claude | copilot) : ;; *) mos_usage_error "--agent must be claude or copilot" ;; esac
  case "$event" in stop | subagent-stop) : ;; *) mos_usage_error "--hook expects stop or subagent-stop, got '$event'" ;; esac
  PAYLOAD=$(cat 2>/dev/null || true)
  # From here on nothing may fail the caller: argv is validated above (usage
  # errors are for humans); payload processing never exits non-zero.
  set +e
  case "$event" in
    stop) hook_stop ;;
    subagent-stop) hook_subagent_stop ;;
  esac 2>/dev/null
  exit 0
}

hook_subagent_stop() {
  local agent_id sub ids id dir dest
  resolve_session
  if [ -z "$SID" ]; then
    hook_log "subagent-stop($AGENT): no session id in payload"
    return 0
  fi
  if ! safe_path_id "$SID"; then
    hook_log "subagent-stop($AGENT): refusing session id with path characters: $SID"
    return 0
  fi
  case "$AGENT" in
    claude)
      agent_id=$(json_field agent_id)
      sub=$(json_field agent_transcript_path)
      [ -n "$sub" ] || sub="$TRANSCRIPT"
      [ -n "$agent_id" ] || agent_id="subagent-$(date -u +%Y%m%dT%H%M%SZ)-$$"
      ;;
    copilot)
      # Payload field names for Copilot subagents are confirmed at the live
      # check; until then look for a nested session id and its directory.
      agent_id=$(json_field subagentSessionId)
      [ -n "$agent_id" ] || agent_id=$(json_field agentId)
      if [ -z "$agent_id" ]; then
        hook_log "subagent-stop(copilot): payload has no subagent id — nothing to copy (session $SID)"
        return 0
      fi
      sub="${COPILOT_HOME:-$HOME/.copilot}/session-state/$agent_id/events.jsonl"
      agent_id="copilot-$agent_id"
      ;;
  esac
  if ! safe_path_id "$agent_id"; then
    hook_log "subagent-stop($AGENT): refusing subagent id with path characters: $agent_id"
    return 0
  fi
  if [ ! -f "$sub" ]; then
    hook_log "subagent-stop($AGENT): transcript not found: $sub (session $SID)"
    return 0
  fi
  ids=$(attribute "$sub" "$MARKER")
  if [ -z "$ids" ]; then
    mkdir -p "$UNASSIGNED/raw"
    cp "$sub" "$UNASSIGNED/raw/$SID-$agent_id.jsonl"
    return 0
  fi
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    dir=$(item_dir_for_id "$id")
    [ -n "$dir" ] || continue
    mkdir -p "$dir/trace/raw"
    dest="$dir/trace/raw/$agent_id.jsonl"
    cp "$sub" "$dest"
  done <<EOF
$ids
EOF
}

case "$1" in
  path)
    shift
    cmd_path "$@"
    ;;
  --hook)
    shift
    cmd_hook "$@"
    ;;
  *) mos_usage_error "unknown subcommand '$1' (expected path | --hook)" ;;
esac
