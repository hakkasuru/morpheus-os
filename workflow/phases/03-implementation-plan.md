# Phase: impl-planning

## Entry

The plan is approved. Status is `impl-planning`.

## Steps

1. Create `03-implementation-plan.md` from
   `templates/work/03-implementation-plan.md`.
2. `## Overview` — 3-5 sentences.
3. `## Steps` — one `### Step N: <name>` block per step. Each names: the
   repo and worktree, the exact files, the change (specific enough that a
   subagent with NO other context than this step could execute it), and a
   verify command + expected result.
4. `## Quality Gates` — the exact commands per affected repo, copied
   verbatim from that repo's `commands:` block in `config/repos.yaml`.
5. `## Delivery` — branch name per repo (`work/<work-id>`), MR title(s),
   target branch per repo (its `default_branch:` from `config/repos.yaml`).
6. GATE: set `03-implementation-plan.md` `status: in-review`, work item
   `status: impl-review`, present to the human per
   `workflow/WORKFLOW.md` § Human gates. STOP and wait.

## Exit

Human approves → `03-implementation-plan.md` `status: approved` +
`approved_at:`, work item `status: executing`. Changes requested →
`status: changes-requested`, revise, re-present.

## Hard rules

- Every step must be independently verifiable by its own verify command.
- Steps are ordered by dependency — a later step may rely on an earlier
  one's result, never the reverse.
- No single step touches more than one repo.
- If a step cannot be specified precisely enough for a context-free
  subagent to execute it, split the step into smaller ones, or return to
  `planning` — do not hand-wave it.
