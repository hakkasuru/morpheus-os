---
task: {{ID}}
phase: implementation-plan
status: draft # draft | in-review | approved | changes-requested
approved_at: null
updated: {{DATE}}
---

# Implementation Plan — {{TITLE}}

## Overview

<3–5 sentences describing the implementation at a high level>

## Steps

### Step 1: <name>

- **Repo / worktree**: <repo-id> / `worktrees/<repo-id>--{{ID}}/`
- **Files**: <files to change>
- **Change**: <specific enough for a subagent with no other context>
- **Verify**: <command> — expected: <result>

<!-- Repeat one ### Step N: <name> block per step. -->

## Quality Gates

<!-- Exact commands per repo, from config/repos.yaml. -->

- <repo-id>: `<command>`

## Delivery

- Branch: `work/{{ID}}`
- MR title(s): <title>
- Target branch(es): <default_branch per repo>
