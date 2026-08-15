---
task: {{ID}}
phase: implementation-plan
status: draft # draft | in-review | approved | changes-requested
approved_at: null
approved_by: null # human | plan-reviewer (confidence <score>)
updated: {{DATE}}
---

# Implementation Plan — {{TITLE}}

## Overview

<3–5 sentences describing the implementation at a high level>

## Steps

### Step 1: <name>

- **Repo / worktree**: <repo-id> / `worktrees/<repo-id>--{{ID}}/`
- **Files**: <files to change>
- **Depends on**: — <step numbers this step builds on, or "—" for none>
- **Change**: <specific enough for a subagent with no other context>
- **Verify**: <command> — expected: <result>

<!-- Repeat one ### Step N: <name> block per step. -->

## Execution Order

<!-- Stages derived from the Depends on fields. Steps in the same stage
     share no dependency (direct or transitive) and touch disjoint files —
     they may execute as parallel subagents. A stage starts only after
     every step of the previous stage is verified and committed. -->

- Stage 1 (parallel): Step 1, Step 2
- Stage 2: Step 3 — depends on Steps 1, 2

## Quality Gates

<!-- Exact commands per repo, from config/repos.yaml. -->

- <repo-id>: `<command>`

## Delivery

- Branch: `work/{{ID}}` <!-- default <branch_prefix>{{ID}}; follow the repo's branch_prefix / preferences branch-naming scheme -->
- MR title(s): <title>
- Target branch(es): <default_branch per repo>
