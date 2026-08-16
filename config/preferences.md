# Preferences

> Personal conventions the agent reads at session start and applies across all work; kept out of AGENTS.md so harness upgrades never clobber personal taste; the agent offers to append here (dated) when the human corrects the same thing twice. Uncomment and edit to activate.

## Git & Delivery

<!-- Branch naming (default prefix `work/` when nothing is set anywhere)
- Default branch prefix: `work/`
  (the machine-enforced setting is per repo: `branch_prefix:` in
  config/repos.yaml — record your default here, set it there; for fully
  custom schemes the agent passes `--branch <name>` to scripts/worktree.sh)
- Branch naming scheme: <e.g. feature/<ticket>-<slug> — applied via --branch>

Commit message style
- Style: conventional commits (type: scope: description)

MR/PR description format
- Format: summary + test evidence + linked task id

Squash vs merge preference
- Strategy: squash on merge
-->

## Coding Defaults

<!-- Cross-repo style preferences (per-repo conventions belong in knowledge/repos/<id>/conventions.md)
- Type preferences: prefer explicit types
- Variable naming: no single-letter variables
- Error handling: explicit error returns
-->

## Working Style

<!-- Plan auto-approval (gates 1-2 only; delivery always needs the human)
- Auto-approve threshold: 85
  (0-100 confidence from the plan-review subagent — see
  workflow/plan-reviewer.md. Plans scoring at or above the threshold are
  approved without waiting for you, UNLESS a hard cap fired: open questions
  to you, destructive steps, or security-touching scope always come to you.
  Leave commented out to review every plan yourself.)

Max autonomous review rounds (only matters when auto-approval is enabled)
- Max autonomous review rounds: 2
  (revise + re-review cycles the orchestrator may run at gates 1-2 without
  you before presenting — see WORKFLOW.md § Review gates loop policy.
  Human-driven changes-requested rounds never count and reset the counter.
  Defaults to 2 when unset.)

Plan verbosity
- Verbosity: detailed plans with rationale

Max clarifying questions before proceeding
- Max questions: 3 before proceeding

Risk tolerance
- Safety: ask before any schema change; proceed on low-risk refactors
-->

## Log

<!-- The agent appends a dated entry here after offering, when the human corrects the same thing twice.
Format: - YYYY-MM-DD — <preference> -->
