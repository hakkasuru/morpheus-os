# Phase: verifying

## Entry

All implementation steps are committed. Status is `verifying`.

## Steps

1. Run EVERY command from `03-implementation-plan.md` `## Quality Gates`
   inside the affected worktrees. Capture the real output.
2. Walk `02-plan.md` `## Acceptance Criteria` one by one. Verify each by
   command or direct observation. Record the evidence.
3. Independent diff review: for each affected repo, generate the diff
   file (`git -C <worktree> diff origin/<default_branch>...HEAD > /tmp/<work-id>--<repo-id>.diff`
   — against origin/, not the local branch: the local default branch can
   lag the fetch the worktree was branched from, and a stale merge-base
   would drag unrelated upstream commits into the reviewed diff)
   and save the reviewer brief (`scripts/trace-capture.sh path <work-id>
   brief 05 diff-reviewer`). Then dispatch a diff-reviewer subagent per
   `workflow/diff-reviewer.md` with the diff, the approved plans, and the
   repo's conventions doc. It writes `04-diff-review.md` and returns PASS
   or FAIL. Record the verdict: `scripts/event.sh <work-id>
   diff-review repo=<repo-id> verdict=<PASS|FAIL> findings=<n>`. FAIL →
   loop back through `phases/04-execute.md` to fix the blocking findings
   (revising the impl plan first if the fix needs an unplanned step), then
   re-run this phase.
   The gate's unit is the delivery TARGET, not the registered repo. When a
   step's change reaches the world by any other route — content written
   into an external system, generated files published elsewhere, a push
   onto an MR that already exists — that target gets a review too. Build
   its review object in place of the `git diff`: the workspace-local diff
   for whatever the steps added here, plus, for anything written outside,
   the list of every path written and the content of each read back FROM
   the target (not from local build output, which is what was meant to be
   sent, not what arrived). Hand that to the same brief and record the
   verdict the same way, with `repo=<target>`.
4. Run `scripts/validate.sh` (workspace hygiene).
5. Create `04-verification.md` from `templates/work/04-verification.md`:
   a per-gate table (gate | command | pass/fail | output excerpt), a
   criteria checklist with evidence per item, the diff-review verdict
   (with any MINOR findings carried for the human to see), and an
   overall verdict. Then `scripts/event.sh <work-id> verification
   gates=<passed>/<total> verdict=<PASS|FAIL>`.

## Exit

All gates pass, all criteria are met, and every delivery target has a
recorded diff-review verdict that is PASS →
`scripts/event.sh <work-id> status from=verifying to=delivering`. Any
failure → loop back through `phases/04-execute.md` to fix, or
`scripts/event.sh <work-id> blocked was=verifying
"unblock=<condition>"`.

## Hard rules

- Evidence, not assertions — paste real output excerpts into
  `04-verification.md`, not summaries of what you expect happened.
- Never edit a gate command to make it pass.
- A red gate is a stop, not a footnote — do not carry a failing gate
  forward into delivery.
- No change leaves this phase unreviewed, and `N/A` is not a verdict. If
  something shipped, something is reviewable — a target with nothing to
  review is one whose review object came out empty, which is itself worth
  saying out loud. Your own execution evidence is not a substitute: you
  wrote the change, and this gate exists so that someone else looks.
