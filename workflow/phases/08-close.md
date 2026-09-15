# Phase: close (on merge)

## Entry

Status is `awaiting-merge` and the human asked to close the item — either
directly ("<work-id> was merged", "close <work-id>") or after
`scripts/mr-check.sh` (session brief or `/mr-check`) reported the MR as
`merged` and the human said to go ahead. The ask is always the human's;
a `merged` verdict alone never starts this phase.

## Steps

1. Confirm the merge via the host CLI for every MR in `task.md` `mr:` —
   `scripts/mr-check.sh <work-id>` (or `glab mr view` / `gh pr view` by
   hand). Proceed only on `merged`. Otherwise:
   - `open` / `attention` — not merged yet. Tell the human; stay in
     `awaiting-merge` (or reopen via `phases/07-feedback.md` if they want
     changes).
   - `closed` (without merging) — record it first: `scripts/event.sh
     <work-id> closed-unmerged mr=<url>`. Then ask the human, and follow
     their choice: `scripts/event.sh <work-id> cancelled "reason=MR closed
     without merge"` (then folder to `work/done/`), or `scripts/event.sh
     <work-id> feedback round=<n> reason=human` to rework and reopen the
     MR.
   - `error` (CLI missing, unauthenticated, offline) — do not guess. Ask
     the human to confirm the merge explicitly; on that confirmation
     proceed and append `scripts/event.sh <work-id> merged mr=<url> --
     "merge confirmed by human (CLI unavailable)"`.
2. Clean up the local task branch in each affected repo (the worktree was
   already removed at delivery — check `scripts/worktree.sh list`; if one
   is still there, `scripts/worktree.sh remove <repo-id> <work-id>
   --delete-branch` does both). Branch name: `mr:` / the implementation
   plan's `## Delivery` section. Then, from `repos/<repo-id>`:
   `git fetch --prune` and `git branch -d <branch>` — the lowercase `-d`
   refuses an unmerged branch, which is the safety net; if it refuses
   after a confirmed merge (squash or rebase merge), use `-D` only after
   the CLI verdict in step 1 said `merged`.
3. Close out: `scripts/event.sh <work-id> merged mr=<url>` (sets
   `status: done`, bumps `updated:`, writes the Activity line). How the
   folder moves depends on the kind of item (per `workflow/WORKFLOW.md`
   § States):
   - Top-level item (standalone task/story, or an epic): move its folder to
     `work/done/`.
   - Epic CHILD (a story/task nested under `work/<state>/E-.../`): do NOT
     move its folder — it stays inside the epic for its whole lifecycle
     (the `merged` event above already updated its `status:` and
     `## Activity`). Check off its line in the epic's own `epic.md`
     `## Stories` checklist. Once every child is `done`|`cancelled`, move
     the EPIC's own folder to `work/done/` (this carries the whole
     subtree, children included).
4. KB touch-up (light — the full harvest ran at delivery): if a feedback
   round changed what was delivered, re-check the docs in
   `knowledge/repos/<affected-repo>/` that the round's diff touches and
   update their `index.md` if needed.
5. Run `scripts/validate.sh`.
6. If a merged MR is later reverted, record it on THIS item —
   `scripts/event.sh <work-id> reverted mr=<reverting-mr-url>` — and treat
   the revert itself as new work.

## Exit

`status: done`, MR merged and confirmed, no worktree and no local task
branch left for this item. Folder under `work/done/` for a top-level item
or a fully-closed epic; an epic child stays in place inside its epic's
folder.

## Hard rules

- `done` means merged. Never close on the human's word alone while the
  host CLI can answer — and never on the CLI alone without the human's ask.
- Never delete an unmerged branch here: `closed`-without-merge and `open`
  MRs keep their branch until the human decides.
- Never reopen a `done` item. If more changes are wanted after the merge,
  scaffold a new work item (`phases/00-intake.md`).
- Update the doc's `updated:` field on every edit.
