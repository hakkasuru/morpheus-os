# Phase: impl-planning

## Entry

The plan is approved. Status is `impl-planning`.

## Steps

1. Create `03-implementation-plan.md` from
   `templates/work/03-implementation-plan.md`.
2. `## Overview` — 3-5 sentences.
3. `## Steps` — one `### Step N: <name>` block per step. Each names: the
   repo and worktree, the exact files, its dependencies (`Depends on:` —
   the step numbers it builds on, or `—` for none), the change (specific
   enough that a subagent with NO other context than this step could
   execute it), and a verify command + expected result.
4. `## Execution Order` — group the steps into stages derived from the
   `Depends on:` fields: steps with no dependency between them (direct or
   transitive) AND disjoint files belong to the same stage and may execute
   as parallel subagents; a step goes in the earliest stage after all its
   dependencies. Steps that share files go in different stages even when
   logically independent.
5. `## Quality Gates` — the exact commands per affected repo, copied
   verbatim from that repo's `commands:` block in `config/repos.yaml`.
6. `## Delivery` — branch name per repo (default `<branch_prefix><work-id>`,
   prefix from the repo's registry entry or `work/`; apply the branch-naming
   scheme from `config/preferences.md` if one is set), MR title(s),
   target branch per repo (its `default_branch:` from `config/repos.yaml`).
7. GATE: set the work item's `status: impl-review`, then dispatch a
   plan-review subagent per `workflow/plan-reviewer.md` and run the gate
   procedure in `workflow/WORKFLOW.md` § Review gates — auto-approve on a
   qualifying confidence score (opt-in, no hard cap fired), otherwise set
   `03-implementation-plan.md` `status: in-review`, present to the human,
   STOP and wait.

## Exit

Approved (human, or auto per the gate procedure) →
`03-implementation-plan.md` `status: approved` + `approved_at:` +
`approved_by:`, work item `status: executing`. Changes requested →
`status: changes-requested`, revise, re-present (the reviewer runs again on
the revision; autonomous rounds are bounded by the loop policy in
`workflow/WORKFLOW.md` § Review gates — human-driven rounds are not).

## Hard rules

- Every step must be independently verifiable by its own verify command.
- Dependencies are explicit: every step carries `Depends on:`, a step may
  rely only on steps it names, and the graph has no cycles.
- Same-stage steps are genuinely independent: no dependency between them,
  and disjoint files (different repos always qualify). When in doubt,
  sequence — a wrong parallel claim corrupts a worktree; a wasted stage
  costs a few minutes.
- No single step touches more than one repo.
- If a step cannot be specified precisely enough for a context-free
  subagent to execute it, split the step into smaller ones, or return to
  `planning` — do not hand-wave it.
