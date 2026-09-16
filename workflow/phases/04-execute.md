# Phase: executing

## Entry

The implementation plan is approved. Status is `executing`.

## Steps

1. For each affected repo, create its worktree once:
   `scripts/worktree.sh add <repo-id> <work-id>`. ALWAYS work inside the
   worktree — never in `repos/<id>` directly. The worktree is scoped to
   this work-id: reuse the same one for every step against this repo;
   parallel subagents only get separate worktrees when they belong to
   different work-ids.
2. Execute stage by stage, following the plan's `## Execution Order`. Per
   step: obtain the two trace paths —
   `scripts/trace-capture.sh path <work-id> brief 04 implementer --step <k>`
   and `scripts/trace-capture.sh path <work-id> report 04 implementer --step <k>`
   — write the self-contained step brief to the brief path (the step block
   verbatim, the worktree path, the repo's conventions, what not to touch
   for shared worktrees, AND the report path as "Write your report to:
   <path>"), then dispatch an implementer subagent per
   `workflow/implementer.md` with that brief. One subagent per step. All
   steps of the current stage MAY be dispatched in parallel — the plan
   already guaranteed they are independent and touch disjoint files.
3. A stage is a barrier: review every subagent's diff summary and run each
   step's verify command; only when all of the stage's steps are reviewed,
   verified, and committed does the next stage start. Never chain work
   onto unreviewed steps. Record each step once its verify is confirmed:
   `scripts/event.sh <work-id> step step=<k> result=<pass|fail>
   attempts=<n> repo=<repo-id>` — a failed verify is logged as
   `result=fail` and the step retried or the item blocked
   (`scripts/event.sh <work-id> blocked was=executing
   "unblock=<condition>"`).
4. Commit per step, inside the worktree: `[<work-id>] <step summary>`.
   Implementers never commit — the ORCHESTRATOR commits each step's files
   after reviewing its diff. When parallel steps share a worktree (same
   repo, disjoint files), serialize those commits one at a time as each
   review completes — never two commits racing in one worktree.
5. Track completion in `03-implementation-plan.md` — check off each step or
   annotate it as done.

## Exit

All steps done and committed. `scripts/event.sh <work-id> status
from=executing to=verifying`.

## Hard rules

- No work outside worktrees.
- Never commit to a repo's default branch.
- A failed step verification stops the phase — fix the step or
  `scripts/event.sh <work-id> blocked was=executing "unblock=<condition>"`.
  Never proceed on a red verification, and never start a stage while any
  earlier-stage step is unverified or uncommitted.
- Parallelism comes from the approved plan's stages, never improvised: if
  reality contradicts a stage's independence claim (a subagent needs a
  sibling's files), stop the stage and return the plan to
  `changes-requested`.
- Subagent briefs are self-contained: no "see conversation above" — the
  subagent has no other context.
