---
description: Show the run-record scorecard per harness version (read-only)
---

Run `scripts/scorecard.sh --summary` (add `$ARGUMENTS` after `scorecard.sh`
when the human names work ids or asks for per-item rows without
`--summary`) and relay the table. Explain the columns in one line each the
first time: auto_approve_rate is the share of gate approvals made by the
plan-reviewer, items_with_gaps counts items whose status requires a gate
doc they lack (the stamp and events log show per row, not in this count).
Do not change any work item from this result — it is data for evaluating
the harness (`workflow/WORKFLOW.md` § Run record).
