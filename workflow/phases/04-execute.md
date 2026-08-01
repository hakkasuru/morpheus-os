# Phase: executing

## Entry

The implementation plan is approved. Status is `executing`.

## Steps

1. For each affected repo, create its worktree:
   `scripts/worktree.sh add <repo-id> <work-id>`. ALWAYS work inside the
   worktree — never in `repos/<id>` directly. If parallel tasks or
   subagents touch the same repo concurrently, give each its own worktree
   (`worktree.sh add` again is not needed if one already exists for this
   work-id — reuse it; only give separate work-ids separate worktrees).
2. For each step in `03-implementation-plan.md`, dispatch an implementation
   subagent with a self-contained brief: goal, worktree path, exact files,
   constraints, and the verify command. One subagent per step. Independent
   steps MAY run as parallel subagents when they touch different worktrees
   or disjoint files.
3. Review each subagent's diff summary before building the next step on
   top of it — never chain a second step onto unreviewed work.
4. Commit per step, inside the worktree:
   `[<work-id>] <step summary>`.
5. Track completion in `03-implementation-plan.md` — check off each step or
   annotate it as done.

## Exit

All steps done and committed. Set `status: verifying`.

## Hard rules

- No work outside worktrees.
- Never commit to a repo's default branch.
- A failed step verification stops the phase — fix the step or set
  `status: blocked`. Never proceed on a red verification.
- Subagent briefs are self-contained: no "see conversation above" — the
  subagent has no other context.
