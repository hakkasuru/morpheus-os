# Phase: verifying

## Entry

All implementation steps are committed. Status is `verifying`.

## Steps

1. Run EVERY command from `03-implementation-plan.md` `## Quality Gates`
   inside the affected worktrees. Capture the real output.
2. Walk `02-plan.md` `## Acceptance Criteria` one by one. Verify each by
   command or direct observation. Record the evidence.
3. Independent diff review: for each affected repo, generate the diff
   file (`git -C <worktree> diff <default_branch>...HEAD > /tmp/<work-id>--<repo-id>.diff`)
   and dispatch a diff-reviewer subagent per `workflow/diff-reviewer.md`
   with the diff, the approved plans, and the repo's conventions doc. It
   writes `04-diff-review.md` and returns PASS or FAIL. FAIL → loop back
   through `phases/04-execute.md` to fix the blocking findings (revising
   the impl plan first if the fix needs an unplanned step), then re-run
   this phase.
4. Run `scripts/validate.sh` (workspace hygiene).
5. Create `04-verification.md` from `templates/work/04-verification.md`:
   a per-gate table (gate | command | pass/fail | output excerpt), a
   criteria checklist with evidence per item, the diff-review verdict
   (with any MINOR findings carried for the human to see), and an
   overall verdict.

## Exit

All gates pass, all criteria are met, and the diff review is PASS →
`status: delivering`. Any failure → loop back through
`phases/04-execute.md` to fix, or set `status: blocked`.

## Hard rules

- Evidence, not assertions — paste real output excerpts into
  `04-verification.md`, not summaries of what you expect happened.
- Never edit a gate command to make it pass.
- A red gate is a stop, not a footnote — do not carry a failing gate
  forward into delivery.
