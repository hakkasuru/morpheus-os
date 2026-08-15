# Changelog

Human-consequence changes to the harness, newest first — what changed in
how the workspace behaves, and whether your copy needs action after
pulling (`git pull upstream main`). Machinery details live in `git log`.

Every entry answers: **Action needed after pulling?**

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
