# Workflow

The state machine for every work item (task, story, epic). Read this once per
work item, then read only the phase doc named by the current `status:`.

## States

Pipeline (linear progression, left to right):

```
intake → context → planning → plan-review → impl-planning → impl-review
  → executing → verifying → delivering → done
```

Exception states (not on the pipeline):

- `blocked` — work cannot proceed; orthogonal to phase, keeps whatever phase
  docs it already has. Setting `status: blocked` appends an `## Activity`
  line: `- YYYY-MM-DD — blocked (was: <status>; unblock: <condition>)`. To
  resume: restore `status:` to that `was:` value, then append
  `- YYYY-MM-DD — unblocked, resuming <status>`.
- `cancelled` — terminal. Move the folder to `work/done/` like `done`.

Status lives in `task.md` (or `epic.md`) frontmatter `status:`. The folder a
work item sits in is its coarse state — this table applies to TOP-LEVEL work
items only (standalone tasks/stories, and epics themselves):

| Folder           | Legal status                          |
|------------------|----------------------------------------|
| `work/backlog/`  | `intake`                                |
| `work/active/`   | any pipeline status between `context` and `delivering`, or `blocked` |
| `work/done/`      | `done`, `cancelled`                     |

Moving the folder and updating `status:` are one atomic edit — never do one
without the other. `scripts/validate.sh` cross-checks folder vs. status for
top-level items, and that phase docs exist only from the status onward that
creates them.

Epic children are the exception: a child story/task lives inside its epic's
folder (`work/<coarse-state>/E-.../<child-id>/`) for its ENTIRE lifecycle,
from `intake` to `done`|`cancelled` — it never moves on its own. The folder
column above does not constrain a child's status; only the EPIC's own folder
moves, as the unit, `backlog/` → `active/` → `done/`, and only when *all* of
its children are `done` or `cancelled` does the epic (and everything nested
under it) move to `work/done/`.

## Review gates

Three gates — never implied, never skipped, never batched. Each is a stop:
gates 1-2 are reviewed by a plan-review subagent (`plan-reviewer.md`) and
wait for the human unless auto-approval applies; gate 3 always waits for
the human.

| Gate         | After doc                    | Approves | Phase doc      |
|--------------|-------------------------------|-----------------|-----------------|
| plan-review  | `02-plan.md`                   | the WHAT        | `phases/02-plan.md` |
| impl-review  | `03-implementation-plan.md`    | the HOW         | `phases/03-implementation-plan.md` |
| delivering   | `04-verification.md`           | the delivery (push + MR) — human, always | `phases/06-deliver.md` |

Gates 1-2 (plan-review, impl-review) use their doc's own approval-state field
— only `02-plan.md` and `03-implementation-plan.md` carry
`status: draft|in-review|approved|changes-requested` + `approved_at:` +
`approved_by:`. At the gate:

1. Dispatch a plan-review subagent per `workflow/plan-reviewer.md`. It
   writes `<gate-doc>-review.md` next to the doc and returns a confidence
   score (0-100) plus whether auto-approval is barred by a hard cap.
2. **Auto-approval (opt-in):** if `config/preferences.md` sets an
   auto-approve threshold, the score meets it, and no hard cap fired → set
   the doc `status: approved`, `approved_at: <date>`,
   `approved_by: plan-reviewer (confidence <score>)`, append an Activity
   line `- YYYY-MM-DD — gate auto-approved (confidence <score>, review:
   <review-doc>)`, and advance. The human can veto any auto-approval later
   by setting `status: changes-requested` — treat that like any
   changes-requested loop.
3. **Otherwise (no threshold set, score below it, or a cap fired):** set
   the doc `status: in-review`, present a concise summary, the doc path,
   and the review's score + top findings, then STOP and wait.
   Approved → `status: approved` + `approved_at: <date>` +
   `approved_by: human`, advance the work item's `status:` per the map
   below. Changes requested → `status: changes-requested`, revise,
   re-present — the reviewer runs again on the revised doc (loop until
   approved).

Gate 3 (delivering) has no such doc field — approval is interactive only and
is NEVER auto-approved, whatever the preferences say: the human's explicit
go-ahead in `phases/06-deliver.md`'s gate step authorizes push+MR. Record it
via `mr:` in task.md plus an Activity line:
`- YYYY-MM-DD — delivery approved, MR created: <url>`.

## Phase → doc → exit map

| Phase           | Doc created                     | Exit condition                          | Next status     |
|-----------------|----------------------------------|-------------------------------------------|-----------------|
| intake          | `task.md` (via `new-work.sh`)    | `task.md` exists                          | context         |
| context         | `01-context.md`                  | complete, questions answered              | planning        |
| planning        | `02-plan.md`                     | drafted                                   | plan-review     |
| plan-review     | `02-plan-review.md` (subagent)    | approved (human or auto)                  | impl-planning   |
| impl-planning   | `03-implementation-plan.md`      | drafted                                   | impl-review     |
| impl-review     | `03-implementation-plan-review.md` (subagent) | approved (human or auto)      | executing       |
| executing       | (commits in worktrees)           | all impl-plan steps done                  | verifying       |
| verifying       | `04-verification.md`             | complete, all gates pass                  | delivering      |
| delivering      | MR(s)                             | created, folder moved to `work/done/`     | done            |

## Epic flow

An epic runs `context` and `planning` once, at the epic level: its
`02-plan.md` covers decomposition into stories/tasks and must include a
`## Stories` list. Once approved, each child story/task — a subfolder
scaffolded with e.g. `scripts/new-work.sh story "Add payment retry logic"
--parent work/active/E-20260801-payments-v2` — runs the full workflow
individually, from its own `context` phase, entirely inside the epic's
folder: a child's own status moves from `intake` through `done`|`cancelled`
without ever relocating itself (see § States). While children are in flight,
the epic's own `status:` reflects the furthest-behind child. The epic's
folder moves to `work/done/` only once every child is `done` or `cancelled` —
per § States, that move carries the whole epic subtree, children included.

## Activity discipline

On every status change, append one line to `task.md`/`epic.md` `## Activity`:

```
- YYYY-MM-DD — <status change or event>
```

## Hard rules

- Never skip a gate. Gates 1-2 may be auto-approved only via the documented
  plan-review procedure (opt-in threshold in `config/preferences.md`, no
  hard cap fired); gate 3 always requires the human.
- Never advance `status:` without its exit condition met.
- Blocked beats guessing — if information is missing or a check fails, set
  `status: blocked` and ask; never improvise past it.
- Update the doc's `updated:` field on every edit, not just on phase change.
- Never invent a status outside the vocabulary above.
