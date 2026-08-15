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
   step, dispatch an implementation subagent with a self-contained brief:
   goal, worktree path, exact files, constraints, and the verify command.
   One subagent per step. All steps of the current stage MAY be dispatched
   in parallel — the plan already guaranteed they are independent and
   touch disjoint files.
3. A stage is a barrier: review every subagent's diff summary and run each
   step's verify command; only when all of the stage's steps are reviewed,
   verified, and committed does the next stage start. Never chain work
   onto unreviewed steps.
4. Commit per step, inside the worktree: `[<work-id>] <step summary>`.
   When parallel steps share a worktree (same repo, disjoint files),
   serialize the commits: commit each step's files one at a time as its
   review completes — parallel subagents edit concurrently, but only the
   orchestrator commits, never two commits racing in one worktree.
5. Track completion in `03-implementation-plan.md` — check off each step or
   annotate it as done.

## Exit

All steps done and committed. Set `status: verifying`.

## Hard rules

- No work outside worktrees.
- Never commit to a repo's default branch.
- A failed step verification stops the phase — fix the step or set
  `status: blocked`. Never proceed on a red verification, and never start
  a stage while any earlier-stage step is unverified or uncommitted.
- Parallelism comes from the approved plan's stages, never improvised: if
  reality contradicts a stage's independence claim (a subagent needs a
  sibling's files), stop the stage and return the plan to
  `changes-requested`.
- Subagent briefs are self-contained: no "see conversation above" — the
  subagent has no other context.
