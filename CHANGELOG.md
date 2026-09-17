# Changelog

Human-consequence changes to the harness, newest first — what changed in
how the workspace behaves, and whether your copy needs action after
pulling (`git pull upstream main`). Machinery details live in `git log`.

Every entry answers: **Action needed after pulling?**

## 1.1.1 — 2026-09-17

- **The pre-delivery diff review covers every delivery target, not only
  registered-repo worktrees** (`workflow/phases/05-verify.md`,
  `templates/work/04-verification.md`). When a step ships a change by a route
  that leaves no worktree diff, the orchestrator assembles a review object
  (the local diff plus every path written and its content read back from the
  target) and hands it to the same reviewer; `N/A` is no longer a verdict and
  the phase Exit needs a recorded verdict per target. Action needed after
  pulling? No — instruction text only; in-flight items keep validating.

## 1.1.0 — 2026-09-16

- **Export the run record to an experience store**
  (`scripts/export-experience.sh`, new `knowledge/runbooks/export-experience.md`
  runbook, `/export-experience` command). Copies finished work items
  (`work/done/`, or also `work/active/` with `--include-active`) — their
  docs, `events.log`, `trace/` and the session transcripts their
  `trace/sessions.tsv` point at — plus a `scripts/scorecard.sh` snapshot
  and `config/preferences.md`, into `<store>/<workspace>/` (contract:
  `manifest.tsv`, `items/<id>/`, `sessions/<sid>.jsonl`,
  `scorecard-<ts>.tsv`, `summary-<ts>.tsv`, `config/preferences.md`;
  `store_version: 1`). It is strictly read-only on this workspace — it
  writes only under `--dest`, which must be a directory outside the
  workspace. A secrets sweep runs over everything first; any token-shaped
  hit aborts with the offending `file:line` list before any write, unless
  `--ignore-sweep` is given (which exports anyway and warns loudly).
  `--dry-run` lists what would be exported without writing anything.
- **The proposer is a separate repo**
  (`knowledge/decisions/proposer-loop-separate-repo.md`). The exporter
  above is the whole of this template's side of the Meta-Harness loop: a
  separate repo (`meta-morpheus-os`) registers live workspaces, runs their
  exporter to pull a store snapshot, and proposes harness changes back as
  pull/merge requests reviewed like any other change. This workspace never
  reads the store and nothing in the workflow depends on the export
  existing.
- **Action needed after pulling?** None — the exporter is inert until a
  proposer runs it. Optionally try
  `scripts/export-experience.sh --dest <dir> --dry-run` to see what it
  would export.

## 1.0.0 — 2026-09-15

- **The template has a version.** `VERSION` (semver) at the root; this is
  the first versioned entry. Every entry from now on is headed
  `## <version> — <date>`, and `scripts/validate.sh --harness` (new: the
  template self-check, also run in CI) fails when the two disagree.
- **Run record on every work item** (`WORKFLOW.md` § Run record,
  § Activity discipline; new `scripts/event.sh`, `scripts/stamp.sh`,
  `scripts/trace-capture.sh`, `scripts/scorecard.sh`; `/scorecard`).
  `new-work.sh` stamps `harness: <VERSION>+<template commit>` and
  `workspace_rev:` into the frontmatter and creates `events.log`. Status
  changes and gate/step/review/delivery/merge results go through
  `scripts/event.sh`, which writes the structured log line, the prose
  Activity line and the `status:` field in one call — hand-edited status
  now fails validation. Every subagent brief is saved under
  `trace/briefs/`, the implementer writes its report under
  `trace/reports/`, and project hooks (Claude Code `SubagentStop`/`Stop`;
  Copilot CLI `agentStop`/`subagentStop` in
  `.github/hooks/trace-capture.json`) record session-transcript pointers
  in `trace/sessions.tsv` and copy subagent transcripts into the gitignored
  `trace/raw/`. `scripts/scorecard.sh` turns records into one row per item
  or a per-version summary; `status.sh` shows a one-line summary; the
  session brief prints the running harness version and upstream drift.
- **Gate consistency is validated.** For items with an `events.log`, a
  status past a gate without an approved gate doc and its review, or a
  delivered item without a complete verification and a PASS diff review,
  is an error; older items get warnings. Epics whose status runs ahead of
  their furthest-behind child are warned about.
- **Action needed after pulling?** Yes, five things. (1) Restart the
  session (or open `/hooks` once) so the new hooks load. (2) Run
  `scripts/stamp.sh --backfill` once, then commit the stamps — this maps
  every existing item to the template version that ran it. (3) Expect
  gate-consistency warnings on old items that skipped a gate doc; leave
  them — they are data the scorecard counts, not debt to backfill.
  (4) Copilot CLI users: `.github/hooks/trace-capture.json` loads on the
  next session start; session pointers resolve to
  `~/.copilot/session-state/<sessionId>/events.jsonl` (honours
  `COPILOT_HOME`). Token counts are unavailable on Copilot.
  (5) `work/.trace-unassigned/` (gitignored) receives a pointer row for
  every session plus copies of the subagent transcripts that touched no
  work item; it grows by several MB per session and is safe to delete at
  any time. A retention policy is deferred.

## 2026-09-14

- **Update-harness runbook and template-safe remotes**
  (`knowledge/runbooks/update-harness.md`, `/update-harness` command,
  `workspace-setup` runbook step 2, README "Make it yours"). "Update the
  harness" now has a runbook: fetch `upstream`, show the incoming
  `CHANGELOG.md` entries and commits, merge on your confirmation, apply
  each entry's action items, validate, push to `origin`. Workspace setup
  gained a remotes step: a clone whose `origin` is still the public
  template gets it renamed to `upstream` with pushes `DISABLED`, and your
  own repo added as `origin`.
- **Done means merged** (`WORKFLOW.md` § States, § Closing on merge, new
  `awaiting-merge` status, `phases/06-deliver.md`, new
  `phases/08-close.md`, `/close` command). Delivery no longer closes a
  work item: creating the MR/PR removes the worktrees and parks the item
  in `awaiting-merge` under `work/active/`. It moves to `done` only after
  the MR is merged — you say so ("close <work-id>"), the agent confirms
  the merge on the host, deletes the local task branch and moves the
  folder to `work/done/`. An MR closed without merging is your call:
  cancel the item or rework it.
- **Feedback before merge, from reviewers or from you** (`WORKFLOW.md`
  § Feedback, `phases/07-feedback.md`). The `feedback` state is now
  entered from `awaiting-merge` (not from `done`), and for two reasons: MR
  comments, or you wanting something changed before the merge. Your own
  scope changes are recorded as `## Amendments` in `02-plan.md` and go
  straight to the implementation plan (gate 2) — no gate-1 re-review of a
  decision you already made. Merged items are never reopened; further
  changes become new work items.
- **Pending-MR check** (new `scripts/mr-check.sh`, `/mr-check` command,
  `scripts/session-brief.sh`). One read-only line per pending MR — merged,
  open, attention (changes requested / unresolved threads), closed without
  merge, or error — via `glab`/`gh`. The session brief runs it at every
  session start and folds the verdicts into the open-work list and the
  priorities ("close the N merged item(s)", "look at the N MR(s) with
  requested changes"). It never acts: closing and reopening stay on your
  explicit ask. Skip it with `session-brief.sh --no-mr-check` or
  `MOS_BRIEF_NO_MR_CHECK=1`.
- **Action needed after pulling?** Three things. (0) If your clone has no
  `upstream` remote yet, or `upstream` still accepts pushes, run the
  `workspace-setup` runbook's step 2 once (`git remote -v` shows the
  state). (1) The session-start hook
  timeout went from 20s to 45s to leave room for the MR queries
  (`.claude/settings.json`, `.github/hooks/session-brief.json`) — restart
  the session (or open `/hooks` once) so Claude Code picks it up. (2) Any
  item you delivered before this change already sits in `work/done/` as
  `done`; leave it. Items delivered from now on wait in `awaiting-merge`
  until you close them.

## 2026-09-05

- **Session-start brief** (`scripts/session-brief.sh`, new
  `.claude/settings.json` and `.github/hooks/session-brief.json`). Every
  session start and resume in this workspace — Claude Code and Copilot
  CLI — now runs a read-only brief and hands it to the agent to relay:
  open work items (gates waiting on you, blocked, in progress, backlog),
  knowledge docs due for maintenance (past `stale_after`, drafts older
  than 30 days, agent-authored docs with no `verified:` stamp) and an
  ordered priority list — or an explicit "nothing to pick up". Both hooks
  are project-scoped and checked in; nothing is written to `~/.claude` or
  `~/.copilot`. The script is client-agnostic: run it by hand, or wire its
  plain-text output into another agent's session-start mechanism.
- **Action needed after pulling?** Claude Code only picks up a new
  project settings file on the next start — restart the session (or open
  `/hooks` once) after pulling. Copilot CLI loads `.github/hooks/` on
  start as well.

## 2026-08-30

- **Opt-in auto-delivery (gate 3)** (`WORKFLOW.md` § Review gates,
  `phases/06-deliver.md`, `config/preferences.md`). Setting
  `Auto-deliver: on` in `config/preferences.md` lets a fully green run —
  every quality gate green in `04-verification.md` AND a PASS diff
  review — push and create its MR without waiting at the delivery
  confirm. Anything less (a red gate, a FAIL or missing diff review, a
  blocked item) still stops for the human. Carried MINOR diff-review
  findings move into the MR description, and every auto-delivery is
  recorded in the task's Activity log
  (`delivery auto-approved (Auto-deliver: on)`).
- **MR feedback loop** (`WORKFLOW.md` § Feedback re-entry,
  `phases/07-feedback.md`, new `feedback` status, `/feedback` command).
  "Address the feedback on <work-id>" reopens a delivered item: the
  worktree comes back on the existing branch
  (`worktree.sh add --existing`, new flag), MR comments are triaged into
  `feedback-round-<n>` steps on the implementation plan, gate 2
  re-reviews the revision, and delivery pushes the same branch and
  answers the threads instead of opening a new MR. Reopening is always
  human-initiated — nothing polls MRs.
- **Intake phase doc** (`workflow/phases/00-intake.md`). Intake's exit is
  now explicit: `## Request` pasted verbatim, draft acceptance criteria,
  and a filled `repos:` before entering context. `validate.sh` warns when
  a task/story past intake still has `repos: []`.
- **Diff baseline fix** (`phases/05-verify.md`, `workflow/diff-reviewer.md`).
  The pre-delivery diff is generated against `origin/<default_branch>`,
  not the local default branch — a lagging local branch used to drag
  unrelated upstream commits into the reviewed diff, which the
  diff-reviewer would then FAIL as unexplained changes.
- **Action needed after pulling?** No — auto-delivery is off by default
  (uncomment `Auto-deliver: on` in `config/preferences.md` to enable);
  the `feedback` status and intake rules only affect items going forward.

## 2026-08-16

- **Bounded gate-review loops** (`WORKFLOW.md` § Review gates, loop
  policy). Autonomous revise + re-review rounds at gates 1-2 (possible
  only with auto-approval enabled) now stop at the first of: an inherent
  hard cap (security scope, unavoidable destructive step — straight to
  the human, no revision round), a near-miss score (within 5 points of
  the threshold), no progress (score up by <5, or a finding unresolved
  twice), or the round cap (`Max autonomous review rounds` in
  `config/preferences.md`, default 2). Human-driven changes-requested
  rounds stay unbounded and reset the counter.
- **Delta-aware re-reviews** (`workflow/plan-reviewer.md` + both native
  definitions). On round 2+ the reviewer reads the prior report and
  dispositions every prior finding (resolved / unresolved / disputed);
  late findings are allowed but flagged `new-in-round-<n>`; the score is
  recomputed from scratch each round. Fired hard caps are classified
  inherent vs fixable; reports gain `inherent_cap:`, `review_round:`,
  `previous_confidence:` frontmatter.
- **Action needed after pulling?** No — only relevant if you enabled
  auto-approval; the round cap defaults to 2, override it in
  `config/preferences.md`.

## 2026-08-15

- **Native implementer subagent** (`workflow/implementer.md` + Claude/
  Copilot definitions, Sonnet-pinned). Phase 04 now dispatches it per
  step; implementers never commit — the orchestrator reviews diffs and
  commits, universally.
- **Diff-review gate before delivery** (`workflow/diff-reviewer.md` +
  native definitions, Opus-pinned). Phase 05 dispatches it per affected
  repo: plan conformance, scope creep, hygiene, secrets, suspicious
  changes. CRITICAL/MAJOR findings fail the phase back into execution;
  the report lands as `04-diff-review.md`.
- **`scripts/status.sh`** — token-free dashboard: work items (flags gates
  waiting on you, blocked items), worktrees (flags orphans), repo clone
  state, validation warnings.
- **Hardening batch** (the deferred-minors ledger, cleared): duplicate
  registry ids now warn; CRLF-authored knowledge docs parse correctly
  instead of failing with a misleading diagnosis; accented titles
  transliterate to ASCII slugs where iconv supports it; titles containing
  quotes produce valid YAML; `new-work.sh --parent` refuses epic folders
  outside `work/`; the usage-error contract is centralized in `lib.sh`;
  missing-registry errors print once; `worktree.sh remove` prunes stale
  registrations when the directory was deleted by hand.
- **Action needed after pulling?** No. In-flight items simply gain the
  diff review the next time they pass through phase 05.

## 2026-08-10

- **Plan-review subagent with confidence-scored gates 1-2**
  (`workflow/plan-reviewer.md` + native definitions, Opus-pinned).
  Opt-in auto-approval via a threshold in `config/preferences.md` (off by
  default); hard caps always force human review; delivery never
  auto-approves.
- **Explorer subagent** (`workflow/explorer.md` + native definitions,
  Sonnet-pinned, no shell). Phases 01/02 and the add-repo runbook now
  route exploration through it.
- **Staged parallel execution**: implementation-plan steps carry
  `Depends on:` and a `## Execution Order` groups them into stages;
  phase 04 dispatches whole stages as parallel subagents with stage-end
  barriers.
- **Action needed after pulling?** No — unless you want auto-approval:
  uncomment the threshold in `config/preferences.md`. In-flight
  implementation plans without `Depends on:` fields will draw a gate-2
  reviewer finding; annotate them or re-draft.

## 2026-08-09

- **Configurable task-branch naming**: per-repo `branch_prefix:` in
  `config/repos.yaml` (verbatim, include your separator) and
  `worktree.sh add --branch <name>` for fully custom schemes; branch
  names validated with `git check-ref-format`; `remove --delete-branch`
  resolves the worktree's real branch.
- **Action needed after pulling?** No — the default `work/` prefix is
  unchanged.

## 2026-08-04

- **Knowledge bundles**: import external bundles read-only under
  `knowledge/bundles/` (`config/bundles.yaml` + `scripts/sync-bundles.sh`,
  import-bundle runbook); export subtrees as standalone OKF bundles
  (share-bundle runbook).
- **KB format versioning**: `okf_version` stamped on `knowledge/index.md`,
  `SUPPORTED_OKF_VERSION` in `validate.sh` warns on drift, kb-migrate
  runbook defines the upgrade procedure.
- **`verified:` field** on all knowledge docs (set when a human reviews an
  agent-authored doc); `status:` vocabulary and `{{DATE}}` placeholders
  now validated; frontmatter parsing strips inline comments (staleness
  warnings previously never fired on template-styled values).
- **Copilot prompt-file wrappers** (`.github/prompts/`) mirroring the
  Claude slash commands.
- **Action needed after pulling?** Run `scripts/validate.sh`: docs missing
  `status:` or carrying malformed values will now error; add
  `verified: null` to docs you author by hand (templates already carry it).

## 2026-08-01

- Initial public template: AGENTS.md-canonical instructions (symlinked
  adapters), repo registry + sync, worktree-first execution, the
  six-phase gated workflow, work-item and OKF-lite knowledge templates,
  seed runbooks (workspace-setup, add-repo, kb-review), validate.sh.
