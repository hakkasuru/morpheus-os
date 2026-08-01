# Phase: planning

## Entry

Status is `planning` (context complete).

## Steps

1. Create `02-plan.md` from `templates/work/02-plan.md`.
2. Fill it in, applying `config/preferences.md` (plan verbosity) as you go:
   - `## Problem & Goal`
   - `## Proposed Approach` — include alternatives considered and why they
     were rejected, briefly.
   - `## Scope` — `### In` / `### Out`.
   - `## Affected Repos & Components`.
   - `## Risks & Open Questions`.
   - `## Acceptance Criteria` — final, testable versions. Copy these back
     into `task.md` `## Acceptance Criteria`, replacing the draft criteria
     from intake.
3. GATE: set `02-plan.md` `status: in-review`, set the work item's
   `status: plan-review`, present a concise summary plus the doc path to
   the human per `workflow/WORKFLOW.md` § Human gates. STOP and wait.

## Exit

Human approves → `02-plan.md` `status: approved` + `approved_at:`, work item
`status: impl-planning`. Changes requested → `status: changes-requested`,
revise, re-present.

## Hard rules

- The plan says WHAT and WHY. Never file-level HOW — that belongs in
  `03-implementation-plan.md`.
- Every acceptance criterion must be verifiable by a command or a direct
  observation, not by opinion.
- An unresolved open question blocks the gate: ask the human, don't bury it
  in the doc and proceed anyway.
