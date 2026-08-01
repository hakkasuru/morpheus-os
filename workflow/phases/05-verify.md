# Phase: verifying

## Entry

All implementation steps are committed. Status is `verifying`.

## Steps

1. Run EVERY command from `03-implementation-plan.md` `## Quality Gates`
   inside the affected worktrees. Capture the real output.
2. Walk `02-plan.md` `## Acceptance Criteria` one by one. Verify each by
   command or direct observation. Record the evidence.
3. Self-review the full diff for every affected repo:
   `git -C <worktree> diff <default_branch>...HEAD`. Check correctness,
   scope creep, leftover debug output, and style against
   `knowledge/repos/<id>/conventions.md`.
4. Run `scripts/validate.sh` (workspace hygiene).
5. Create `04-verification.md` from `templates/work/04-verification.md`:
   a per-gate table (gate | command | pass/fail | output excerpt), a
   criteria checklist with evidence per item, self-review notes, and an
   overall verdict.

## Exit

All gates pass and all criteria are met → `status: delivering`. Any
failure → loop back through `phases/04-execute.md` to fix, or set
`status: blocked`.

## Hard rules

- Evidence, not assertions — paste real output excerpts into
  `04-verification.md`, not summaries of what you expect happened.
- Never edit a gate command to make it pass.
- A red gate is a stop, not a footnote — do not carry a failing gate
  forward into delivery.
