---
type: Decision
title: "Instrument every work item as a run record for harness evaluation"
description: "Stamp each item with the template version, log structured events beside the Activity prose, keep subagent briefs/reports and raw transcripts per item, and extract a scorecard — so production runs can evaluate harness changes Meta-Harness style."
status: stable
created: 2026-09-15
updated: 2026-09-16
stale_after: null # YYYY-MM-DD — re-verify after this date
tags: [harness, evaluation, meta-harness, run-record, scorecard]
repo: null
generated_by: claude-code # agent name when agent-authored
verified: 2026-09-16
---

# Instrument every work item as a run record for harness evaluation

## Context

Morpheus OS is a harness in the Meta-Harness sense (arXiv 2603.28052):
the code and prose around a fixed model that decide what the model sees.
The paper's method needs, per harness version, its scores and raw
execution traces on a filesystem a proposer can grep. Live workspaces
built on this template had completed dozens of items, but nothing tied an
item to the template version that ran it, the Activity log was
unparseable prose, subagent replies vanished with the orchestrator's
context, and skipped gates went unnoticed by `validate.sh`.

## Decision

Every work item carries a run record from creation:

- `harness: <semver>+<template-commit>` and `workspace_rev:` in its
  frontmatter, from a new root `VERSION` file (`scripts/stamp.sh`).
- `events.log`, a closed vocabulary of TAB-separated events, written by
  `scripts/event.sh` together with the prose Activity line and the
  `status:` field — the only sanctioned way to change status.
- `trace/`: every subagent brief the orchestrator sent, the implementer's
  own report, session pointer rows, and (Claude Code, via SubagentStop and
  Stop hooks) raw subagent transcripts in a gitignored `raw/`.
- `scripts/scorecard.sh` turns records into one row per item and a
  per-version summary; `validate.sh` enforces gate consistency (errors for
  instrumented items, warnings for older ones) and gains a `--harness`
  smoke mode run in CI.

Export of the record to a private experience store and the proposer
skill are deliberately deferred to a second decision.

## Rationale

Production runs are the only evaluation set this harness has: tasks are
one-off and human-gated, so a benchmark would not represent them. What the
paper shows is that a proposer wins by reading raw traces and doing
counterfactual diagnosis, not by reading scores — so traces must be kept,
attributed to a harness version, and be cheap to grep. Old items keep
their gaps as data rather than being backfilled; only the version stamp
is backfilled because it is mechanically derivable from git history.

## Consequences

- Each status change costs one `event.sh` call instead of a hand edit;
  the agent can no longer record a status without its event.
- Workspaces grow by a few small committed files per item; raw
  transcripts stay local and are only durable once exported.
- Skipped gates on new items fail validation; on pre-existing items they
  surface as warnings in `scripts/status.sh` and `scripts/validate.sh`.
- The template has a version, a CHANGELOG keyed by it, and CI.

## Reversible

yes — delete the four scripts, the hooks, the `VERSION` file and the two
frontmatter fields; existing `events.log` and `trace/` folders are inert
data and can stay or be removed. The prose Activity log is unchanged
throughout, so nothing else depends on the record.
