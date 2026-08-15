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
4. GATE: set the work item's `status: plan-review`, then dispatch a
   plan-review subagent per `workflow/plan-reviewer.md` and run the gate
   procedure in `workflow/WORKFLOW.md` § Review gates — auto-approve on a
   qualifying confidence score (opt-in, no hard cap fired), otherwise set
   `02-plan.md` `status: in-review`, present the summary, doc path, and
   review findings to the human, STOP and wait.

## Exit

Approved (human, or auto per the gate procedure) → `02-plan.md`
`status: approved` + `approved_at:` + `approved_by:`, work item
`status: impl-planning`. Changes requested → `status: changes-requested`,
revise, re-present (the reviewer runs again on the revision).

## Hard rules

- The plan says WHAT and WHY. Never file-level HOW — that belongs in
  `03-implementation-plan.md`.
- Every acceptance criterion must be verifiable by a command or a direct
  observation, not by opinion.
- An unresolved open question blocks the gate: ask the human, don't bury it
  in the doc and proceed anyway.
