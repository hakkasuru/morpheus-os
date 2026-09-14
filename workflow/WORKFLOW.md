# Workflow

The state machine for every work item (task, story, epic). Read this once per
work item, then read only the phase doc named by the current `status:`.

## States

Pipeline (linear progression, left to right):

```
intake → context → planning → plan-review → impl-planning → impl-review
  → executing → verifying → delivering → awaiting-merge → done
```

`awaiting-merge` — delivered, not done: the MR/PR exists and is open. The
item stays under `work/active/` with no worktrees (the branch and the MR
carry the work) until the MR is merged — see § Closing on merge. `done`
means merged.

Re-entry state: `feedback` — an `awaiting-merge` item re-enters the
pipeline at `feedback` when its MR drew comments needing attention OR the
human wants something changed before merge, and flows
`feedback → executing → verifying → delivering → awaiting-merge` again.
Entered only on the human's explicit ask — see § Feedback. A merged item
(`done`) has no re-entry: further changes are new work items.

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
| `work/active/`   | any pipeline status between `context` and `awaiting-merge`, `feedback`, or `blocked` |
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
wait for the human unless auto-approval applies; gate 3 waits for the
human unless the opt-in Auto-deliver preference applies (see below).

| Gate         | After doc                    | Approves | Phase doc      |
|--------------|-------------------------------|-----------------|-----------------|
| plan-review  | `02-plan.md`                   | the WHAT        | `phases/02-plan.md` |
| impl-review  | `03-implementation-plan.md`    | the HOW         | `phases/03-implementation-plan.md` |
| delivering   | `04-verification.md`           | the delivery (push + MR) — human by default, opt-in auto | `phases/06-deliver.md` |

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
3. **Autonomous revision (opt-in, bounded):** auto-approval is enabled,
   the score fell short, and NO stop condition in the loop policy below
   fired → the orchestrator may revise the doc against the review's
   findings and re-dispatch the reviewer (back to step 1). Append an
   Activity line per round:
   `- YYYY-MM-DD — gate review round <n> (confidence <score>)`.
4. **Otherwise (no threshold set, a stop condition fired, or a hard cap
   fired):** set the doc `status: in-review`, present a concise summary,
   the doc path, and the review's score + top findings — plus, after any
   autonomous rounds, the round history (scores, what improved, what's
   still open) — then STOP and wait.
   Approved → `status: approved` + `approved_at: <date>` +
   `approved_by: human`, advance the work item's `status:` per the map
   below. Changes requested → `status: changes-requested`, revise,
   re-present — the reviewer runs again on the revised doc, and the loop
   continues until the human approves. Human-driven rounds are unbounded
   by design and reset the autonomous round counter to zero.

**Loop policy — stop conditions.** An *autonomous round* is one
revise-and-re-review cycle with no human contact in between (step 3).
After every review, check these in order; the first that fires ends
autonomous revision and routes the gate to step 4 (the human):

1. **Inherent cap** — the review fired a hard cap classified `inherent`
   (a property of the task, not the doc — revision can never lift it,
   see `plan-reviewer.md` § Hard caps). Go to the human immediately,
   listing the fixable findings too, so one pass of human feedback can
   cover everything.
2. **Near miss** — the score is within 5 points below the threshold. A
   human glance costs less than another revise + re-review cycle.
3. **No progress** — the score improved by fewer than 5 points since the
   previous round, or any finding stands unresolved or disputed across
   two consecutive reviews.
4. **Round cap** — the autonomous rounds already spent at this gate have
   reached the limit (`Max autonomous review rounds` in
   `config/preferences.md`; 2 when unset).

The counter counts autonomous rounds only and resets to zero on any human
input at the gate (approval, changes-requested, veto). The reviewer's
report carries `review_round:` and `previous_confidence:` so the counter
and the no-progress check survive context loss.

Gate 3 (delivering) has no such doc field — approval is interactive by
default: the human's explicit go-ahead in `phases/06-deliver.md`'s gate step
authorizes push+MR. **Auto-deliver (opt-in):** when `config/preferences.md`
sets `Auto-deliver: on`, the gate proceeds without waiting — but only when
`04-verification.md` is all green AND the diff review verdict is PASS. Any
red gate, FAIL or missing diff review, or blocked state still stops for the
human, and carried MINOR diff-review findings are listed in the MR
description (they no longer have a guaranteed human viewer at the gate).
Record the outcome via `mr:` in task.md plus an Activity line:
`- YYYY-MM-DD — delivery approved, MR created: <url>` (human), or
`- YYYY-MM-DD — delivery auto-approved (Auto-deliver: on), MR created: <url>`.

## Phase → doc → exit map

| Phase           | Doc created                     | Exit condition                          | Next status     |
|-----------------|----------------------------------|-------------------------------------------|-----------------|
| intake          | `task.md` (via `new-work.sh`)    | framed per `phases/00-intake.md`: Request verbatim, draft criteria, `repos:` filled | context         |
| context         | `01-context.md`                  | complete, questions answered              | planning        |
| planning        | `02-plan.md`                     | drafted                                   | plan-review     |
| plan-review     | `02-plan-review.md` (subagent)    | approved (human or auto)                  | impl-planning   |
| impl-planning   | `03-implementation-plan.md`      | drafted                                   | impl-review     |
| impl-review     | `03-implementation-plan-review.md` (subagent) | approved (human or auto)      | executing       |
| executing       | (commits in worktrees)           | all impl-plan steps done                  | verifying       |
| verifying       | `04-verification.md`             | complete, all gates pass                  | delivering      |
| delivering      | MR(s)                             | created, `mr:` recorded, worktrees removed | awaiting-merge  |
| awaiting-merge  | —                                 | MR merged (host CLI confirms) and the human asks to close — `phases/08-close.md`; folder moved to `work/done/` | done            |
| feedback        | `03-implementation-plan.md` addendum (`feedback-round-<n>` steps) | feedback triaged, addendum approved at gate 2 | executing       |

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

## Pending MRs

`scripts/mr-check.sh` reads the live state of every MR recorded in `mr:`
on an `awaiting-merge` or `feedback` item and reports one verdict per MR:
`merged`, `attention` (changes requested / unresolved threads), `open`,
`closed` (without merging) or `error`. The session brief runs it at every
session start; the human can also ask for it any time ("check MRs",
`/mr-check`). It is read-only and it decides nothing: the orchestrator
never closes, cancels or reopens an item because of what it reports — it
relays the verdicts and waits for the human's ask (§ Closing on merge,
§ Feedback).

## Feedback (before merge)

An `awaiting-merge` item enters `feedback` on the human's explicit ask,
for either of two reasons:

- **MR feedback** — reviewers left comments or requested changes
  ("address the feedback on <work-id>").
- **Human change request** — the human wants something changed or added
  before the MR merges ("on <work-id>, also change X").

The orchestrator never reopens an item on its own, whatever `mr-check.sh`
reports. The reopen is one atomic edit: set `status: feedback` (the folder
stays under `work/active/`), append
`- YYYY-MM-DD — reopened: <MR feedback | change request> (round <n>)`.

Then follow `phases/07-feedback.md`: recreate worktrees on the existing
task branches (`scripts/worktree.sh add <repo-id> <work-id> --existing`),
triage the MR discussion and/or the human's request, append the needed
steps to `03-implementation-plan.md` tagged `feedback-round-<n>`, and
re-run gate 2 on the revision (auto-approval and the loop policy apply as
at any gate-2 visit). From there the normal pipeline applies — executing,
verifying, delivering — except delivery pushes the existing branch and
answers the discussion threads instead of creating a new MR (gate 3 /
Auto-deliver applies as usual), and lands back in `awaiting-merge`.

## Closing on merge

An item closes only when its MR is merged. Two ways the orchestrator
learns that, both ending in the human's ask:

- the human says so ("<work-id> was merged" / "close <work-id>");
- `mr-check.sh` — at session start or on demand — reports `merged`, the
  orchestrator relays it, and the human says to close.

Then follow `phases/08-close.md`: confirm the merge via the host CLI
(`glab mr view` / `gh pr view`) before closing — the human's word plus a
CLI confirmation, never one alone unless the CLI is unavailable and the
human confirms that explicitly; delete the merged local task branch; set
`status: done`, append `- YYYY-MM-DD — MR merged, closed`, and move the
folder to `work/done/` (epic children stay in place; the epic moves when
all children are `done`|`cancelled`). An MR closed WITHOUT merging is the
human's call: `cancelled`, or `feedback` to rework and reopen the MR.

## Activity discipline

On every status change, append one line to `task.md`/`epic.md` `## Activity`:

```
- YYYY-MM-DD — <status change or event>
```

## Hard rules

- Never skip a gate. Gates 1-2 may be auto-approved only via the documented
  plan-review procedure (opt-in threshold in `config/preferences.md`, no
  hard cap fired); gate 3 requires the human unless `Auto-deliver: on` is
  set in `config/preferences.md` and the run is fully green (verification
  green + diff review PASS — see § Review gates).
- Gate loops are bounded: autonomous revise-and-re-review rounds follow
  the § Review gates loop policy — when a stop condition fires, present
  to the human. Never keep revising to chase a threshold.
- Never advance `status:` without its exit condition met. In particular,
  never set `status: done` before the MR is merged — delivery ends in
  `awaiting-merge`, not `done`.
- MR state is read, never acted on: `scripts/mr-check.sh` (run by the
  session brief and on request) only reports. Closing (§ Closing on
  merge) and reopening (§ Feedback) happen on the human's explicit ask.
- Blocked beats guessing — if information is missing or a check fails, set
  `status: blocked` and ask; never improvise past it.
- Update the doc's `updated:` field on every edit, not just on phase change.
- Never invent a status outside the vocabulary above.
