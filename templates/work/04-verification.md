---
task: {{ID}}
phase: verification
status: draft # draft | complete
updated: {{DATE}}
---

# Verification — {{TITLE}}

## Quality Gates

| Gate | Command | Result | Output excerpt |
| ---- | ------- | ------ | --------------- |
| <gate> | `<command>` | <pass/fail> | <excerpt> |

## Acceptance Criteria

- [ ] <criterion>
  - Evidence: <command output or observation>

## Diff Review

- Verdict: <PASS/FAIL per delivery target — from `04-diff-review.md`; one
  line per target, including any target outside a registered repo. Never
  `N/A`: a target that received a change has a review object.>
- Carried MINOR findings: <list, or —>

## Verdict

<PASS/FAIL> — <one line>
