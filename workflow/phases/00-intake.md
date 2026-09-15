# Phase: intake

## Entry

A new piece of work exists (the human described a task, story, or epic —
or asked to scaffold one). Status is `intake`, folder under `work/backlog/`.

## Steps

1. Scaffold, if not already done: `scripts/new-work.sh task|story|epic
   "<title>"` (add `--parent <epic-folder>` for an epic child). This
   creates the folder and its seeded `task.md`/`epic.md`.
2. Frame `task.md` (or `epic.md`):
   - `## Request` — the ask, VERBATIM. Paste what the human said; do not
     paraphrase or improve it.
   - `## Acceptance Criteria` — draft criteria from the request. These are
     drafts: phase 02 replaces them with final, testable versions. If the
     request is too vague to draft even one criterion, ask now — do not
     scaffold doubt forward.
   - `repos:` — the registered repo ids this work touches, e.g.
     `repos: [my-api, my-frontend]`. For each id: it must exist in
     `config/repos.yaml`, and `repos/<id>` must be cloned (else run
     `scripts/sync-repos.sh --repo <id>`). A repo the human named that is
     NOT registered → offer the `add-repo` runbook first.
   - Epic children: set `epic:` to the parent epic's id.
3. Advance — one atomic edit, per `workflow/WORKFLOW.md` § States: move
   the folder `work/backlog/` → `work/active/` (epic children: the folder
   stays inside the epic) AND record the status change:
   `scripts/event.sh <work-id> status from=intake to=context -- "framed: <one line>"`,
   then continue with `phases/01-context.md`.
   Work that should wait in the backlog instead: leave it — folder in
   `work/backlog/`, `status: intake` is a complete, legal resting state.

## Exit

`task.md`/`epic.md` framed: `## Request` pasted verbatim, draft acceptance
criteria present, `repos:` filled with registered-and-cloned ids (epics may
leave `repos:` empty when the split lives with their children). Then either
resting in the backlog, or advanced to `context` as step 3 describes.

## Hard rules

- `## Request` is verbatim — the human's words are the audit trail every
  later phase traces back to.
- Never enter `context` with an unfilled `repos:` on a task/story — phase
  01 reads `knowledge/repos/<id>/` for every listed repo; an empty list
  silently skips that entirely.
- Never register or clone a repo as a side effect — unregistered repo
  mentions go through the `add-repo` runbook, with the human's confirmation.
- Folder move and status change are one atomic edit, never one without
  the other.
