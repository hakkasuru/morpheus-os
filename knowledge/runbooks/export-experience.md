---
type: Runbook
title: "Export experience"
description: "Copy finished work items, traces and scorecard snapshots into an experience store for the proposer repo."
status: draft
created: 2026-09-16
updated: 2026-09-16
stale_after: null # YYYY-MM-DD — re-verify after this date
tags: [harness, evaluation, meta-harness, proposer, export]
repo: null
generated_by: claude-code # agent name when agent-authored
verified: null # YYYY-MM-DD — set when a human reviews an agent-authored doc
---

# Export experience

## Trigger

The human (or the proposer repo's `experience.sh sync`) asks to export this
workspace's run record.

## Preconditions

- A store directory exists outside the workspace (`--dest` must point at an
  existing path outside this workspace's root).
- There are items to export under `work/done/` (or `work/active/` when
  `--include-active` is used).

## Steps

1. Confirm with the human the store path and the workspace name to use;
   when the proposer repo runs this via `experience.sh sync`, both come
   from its `config/sources.yaml`.

2. Dry-run it and relay the list of what would be exported.

   ```
   scripts/export-experience.sh --dest <store> --dry-run
   ```

3. Run it for real, without `--dry-run`.

   ```
   scripts/export-experience.sh --dest <store>
   ```

4. **[destructive — confirm]** On a secrets-sweep hit, the export aborts
   before any write and prints the offending `file:line` list. Show that
   list to the human and STOP — they redact at the source (and re-run from
   step 2) or explicitly ask for `--ignore-sweep` (which exports anyway and
   warns loudly). Never pass `--ignore-sweep` on your own initiative.

5. Relay the summary line the script prints
   (`exported N item(s) to …; session rows resolved X, missing Y; snapshots …`).

## Rollback

The export only copies data. To undo it, delete
`<store>/<workspace-name>/`.

## Verification

- `<store>/<workspace-name>/manifest.tsv` lists the exported items.
- `<store>/<workspace-name>/items/<id>/task.md` (or `epic.md` for an epic)
  opens and matches the source item.
- `<store>/<workspace-name>/sessions/` holds the transcripts the exported
  items' `trace/sessions.tsv` point at.
