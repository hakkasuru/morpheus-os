# Workflow

The state machine for every work item (task, story, epic). Read this once
per work item, then read only the phase doc named by the current `status:`.

## States

Pipeline (linear progression, left to right):

```
intake → context → planning → plan-review → impl-planning → impl-review
  → executing → verifying → delivering → done
```

Exception states (not on the pipeline):

- `blocked` — work cannot proceed. Orthogonal to phase: a blocked item keeps
  whatever phase docs it already has. Record the unblock condition (what
  must become true) as an `## Activity` line in task.md/epic.md. To resume,
  read the existing phase docs' own `status:` fields to determine which
  pipeline status to restore, set it, and log the resume in `## Activity`.
- `cancelled` — terminal. Move the folder to `work/done/` like `done`.

Status lives in `task.md` (or `epic.md`) frontmatter `status:`. The folder a
work item sits in is its coarse state:

| Folder           | Legal status                          |
|------------------|----------------------------------------|
| `work/backlog/`  | `intake`                                |
| `work/active/`   | any pipeline status between `context` and `delivering`, or `blocked` |
| `work/done/`      | `done`, `cancelled`                     |

Moving the folder and updating `status:` are one atomic edit — never do one
without the other. `scripts/validate.sh` cross-checks folder vs. status, and
that phase docs exist only from the status onward that creates them.

## Human gates

Three gates. Never implied, never skipped, never batched — each is a stop
and an explicit wait for the human.

| Gate         | After doc                    | Human approves | Phase doc      |
|--------------|-------------------------------|-----------------|-----------------|
| plan-review  | `02-plan.md`                   | the WHAT        | `phases/02-plan.md` |
| impl-review  | `03-implementation-plan.md`    | the HOW         | `phases/03-implementation-plan.md` |
| delivering   | verification report            | the delivery (push + MR) | `phases/06-deliver.md` |

At a gate: set the phase doc's `status: in-review`, present a concise
summary plus the doc path, then STOP and wait.

- Approved → phase doc `status: approved` + `approved_at: <date>`, advance
  the work item's `status:` per the map below.
- Changes requested → phase doc `status: changes-requested`, revise, and
  re-present (loop until approved).

## Phase → doc → exit map

| Phase           | Doc created                     | Exit condition                          | Next status     |
|-----------------|----------------------------------|-------------------------------------------|-----------------|
| intake          | `task.md` (via `new-work.sh`)    | `task.md` exists                          | context         |
| context         | `01-context.md`                  | complete, questions answered              | planning        |
| planning        | `02-plan.md`                     | drafted                                   | plan-review     |
| plan-review     | —                                 | human approves                            | impl-planning   |
| impl-planning   | `03-implementation-plan.md`      | drafted                                   | impl-review     |
| impl-review     | —                                 | human approves                            | executing       |
| executing       | (commits in worktrees)           | all impl-plan steps done                  | verifying       |
| verifying       | `04-verification.md`             | complete, all gates pass                  | delivering      |
| delivering      | MR(s)                             | created, folder moved to `work/done/`     | done            |

## Epic flow

An epic runs `context` and `planning` once, at the epic level: its
`02-plan.md` covers decomposition into stories/tasks and must include a
`## Stories` list. Once the epic's plan is approved, each child story/task
— a subfolder inside the epic's folder, scaffolded with
`scripts/new-work.sh ... --parent <epic-folder>` — runs the full workflow
above individually, from its own `context` phase.

While children are in flight, the epic's own `status:` reflects the
furthest-behind child (e.g. one child still in `executing` keeps the epic at
`executing`, even if a sibling has reached `done`).

## Activity discipline

On every status change, append one line to `task.md`/`epic.md`
`## Activity`:

```
- YYYY-MM-DD — <status change or event>
```

## Hard rules

- Never skip a human gate.
- Never advance `status:` without its exit condition met.
- Blocked beats guessing — if information is missing or a check fails, set
  `status: blocked` and ask; never improvise past it.
- Update the doc's `updated:` field on every edit, not just on phase change.
- Never invent a status outside the vocabulary above.
