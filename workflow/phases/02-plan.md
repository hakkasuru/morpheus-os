# Phase: planning

## Entry

Status is `planning` (context complete).

## Steps

1. Create `02-plan.md` from `templates/work/02-plan.md`.
2. If drafting exposes a gap `01-context.md` doesn't cover, don't guess:
   dispatch an explorer subagent per `workflow/explorer.md` for the
   missing facts and append its findings to `01-context.md` first.
3. Fill it in, applying `config/preferences.md` (plan verbosity) as you go:
   - `## Problem & Goal`
   - `## Proposed Approach` — include alternatives considered and why they
     were rejected, briefly.
   - `## Scope` — `### In` / `### Out`.
   - `## Affected Repos & Components`.
   - `## Risks & Open Questions`.
   - `## Acceptance Criteria` — final, testable versions. Copy these back
     into `task.md` `## Acceptance Criteria`, replacing the draft criteria
     from intake.
4. GATE: `scripts/event.sh <work-id> status from=planning to=plan-review`,
   save the reviewer brief (`scripts/trace-capture.sh path <work-id> brief
   02 plan-reviewer`), then dispatch a plan-review subagent per
   `workflow/plan-reviewer.md` and run the gate procedure in
   `workflow/WORKFLOW.md` § Review gates. After EVERY review round record
   `scripts/event.sh <work-id> gate-review gate=1 round=<n>
   confidence=<score> barred=<yes|no> inherent=<yes|no> review=02-plan-review.md`.
   Auto-approve on a qualifying score (opt-in, no hard cap fired):
   `scripts/event.sh <work-id> gate-approved gate=1 by=auto confidence=<score>`;
   otherwise set `02-plan.md` `status: in-review`, present the summary, doc
   path and review findings to the human, STOP and wait.

## Exit

Approved → `02-plan.md` `status: approved` + `approved_at:` + `approved_by:`;
`scripts/event.sh <work-id> gate-approved gate=1 by=human confidence=<score>`
(when the human approved) and `scripts/event.sh <work-id> status
from=plan-review to=impl-planning`. Changes requested →
`02-plan.md` `status: changes-requested`, `scripts/event.sh <work-id>
changes-requested gate=1 by=<human|auto>` (auto = an autonomous revision
round), revise, re-present (the reviewer runs again on the revision;
autonomous rounds are bounded by the loop policy in `workflow/WORKFLOW.md`
§ Review gates — human-driven rounds are not).

## Hard rules

- The plan says WHAT and WHY. Never file-level HOW — that belongs in
  `03-implementation-plan.md`.
- Every acceptance criterion must be verifiable by a command or a direct
  observation, not by opinion.
- An unresolved open question blocks the gate: ask the human, don't bury it
  in the doc and proceed anyway.
