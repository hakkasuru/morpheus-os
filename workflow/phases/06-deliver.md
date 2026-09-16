# Phase: delivering

## Entry

Verification is complete and everything is green. Status is `delivering`.

## Steps

1. Pre-flight: for each affected repo, confirm the host CLI is authenticated
   (`scripts/lib.sh` host detection, then `glab auth status` for GitLab or
   `gh auth status` for GitHub).
2. GATE — per `workflow/WORKFLOW.md` § Review gates:
   - **Auto-deliver (opt-in):** if `config/preferences.md` sets
     `Auto-deliver: on` AND `04-verification.md` is all green AND the diff
     review verdict is PASS → proceed without waiting. List any carried
     MINOR diff-review findings in the MR description, and record the
     delivery with `mode=auto` in step 3. Anything less than fully
     green — a red gate, a FAIL or missing diff review, a blocked item —
     is NOT auto-deliverable: fall through to the human.
   - **Otherwise:** present the verification report summary plus a
     proposed MR title/description per repo (apply `config/preferences.md`
     MR format) to the human. Wait for explicit approval.
3. On approval (human, or auto per the gate), per affected repo:
   - Push the branch from its worktree: `git push -u origin <branch>` (the
     branch named in the implementation plan's `## Delivery` section — ask
     the worktree if unsure: `git symbolic-ref --short HEAD`).
   - Create the MR: GitLab host → `glab mr create` (source branch, target
     `default_branch`, title, description); GitHub host → `gh pr create`.
   - Reopened items (`feedback` re-entry) skip creation — the MR already
     exists and the push updated it. Instead post the round's replies on
     the discussion threads (addressed: what changed; answered: the
     drafted reply; a human change request needs no thread reply unless
     the human asked for one).
   - Record the delivery: set `task.md` `mr:` to the URL, then
     `scripts/event.sh <work-id> delivered mode=<human|auto> mr=<url>`
     (mode `auto` only under `Auto-deliver: on`) — this writes the gate-3
     Activity record and sets `status: awaiting-merge`. Reopened items
     run `scripts/event.sh <work-id> status from=delivering
     to=awaiting-merge -- "feedback round <n> delivered"` instead.
4. Write-time KB harvest (checklist, do not skip any item):
   - Draft new-learning docs from `templates/knowledge/` for anything
     learned this task.
   - Check every doc in `knowledge/repos/<affected-repo>/` against the
     delivered diff — update or deprecate any claim the diff invalidates.
   - Update the affected `index.md` files.
   Record it: `scripts/event.sh <work-id> harvest new=<n> updated=<n>`.
5. Hand over to the MR: `scripts/worktree.sh remove <repo-id> <work-id>`
   for each affected repo (the task branch stays — the MR points at it and
   a feedback round resumes it with `--existing`). The `delivered` event
   in step 3 already set `status: awaiting-merge`; the folder does NOT
   move: the item is delivered, not done. It closes in
   `phases/08-close.md` once the MR is merged, or re-enters via
   `phases/07-feedback.md` if the MR draws comments or the human wants a
   change first. Tell the human the MR URL(s) and that the item now waits
   on the merge.

## Exit

`status: awaiting-merge`, `mr:` recorded, no worktrees remaining for this
work item, folder still under `work/active/`. Never `done` here — that
requires the merge (`phases/08-close.md`).

## Hard rules

- No push, no MR, without gate-3 approval given IN THIS PHASE — the human's
  explicit go-ahead, or the documented Auto-deliver procedure
  (`Auto-deliver: on` + green verification + PASS diff review). Approvals
  from the plan-review or impl-review gates do not carry forward.
- Never skip the KB harvest, even for a small task.
- Leave no orphaned worktrees.
- Never close the item in this phase: delivered is `awaiting-merge`, not
  `done`.
