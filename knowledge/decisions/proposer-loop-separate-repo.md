---
type: Decision
title: "The proposer is a separate repo, pulling exports on demand"
description: "The Meta-Harness proposer lives in its own repo (meta-morpheus-os) and pulls a workspace's exported run record; the template never reads or knows about the store."
status: draft
created: 2026-09-16
updated: 2026-09-16
stale_after: null # YYYY-MM-DD — re-verify after this date
tags: [harness, evaluation, meta-harness, proposer]
repo: null
generated_by: claude-code # agent name when agent-authored
verified: null # YYYY-MM-DD — set when a human reviews an agent-authored doc
---

# The proposer is a separate repo, pulling exports on demand

## Context

The run record (`WORKFLOW.md` § Run record) already exists on every work
item: a version stamp, structured events, per-item traces and a scorecard.
The Meta-Harness method needs a proposer that reads this record across
harness versions and suggests changes to the harness itself. Where that
proposer lives, and how it gets at the record, was still undecided.

## Decision

- (a) The proposer is a SEPARATE repo, `meta-morpheus-os`, not part of this
  template — the candidate under evaluation must not contain its own
  evaluator.
- (b) Pull model: the proposer repo registers live workspaces and runs
  their `scripts/export-experience.sh` itself to pull an experience store
  snapshot. Live workspaces know nothing about the proposer — this
  workspace never reads the store, and nothing in the workflow depends on
  the export.
- (c) The store is a plain file-tree mirror (`manifest.tsv`, `items/`,
  `sessions/`, scorecard/summary snapshots) that the proposer greps
  directly — no database, no API.
- (d) The proposer edits the template in a candidate clone and opens a
  PR/MR against it; the human's review of that PR/MR is the gate, exactly
  like any other change to this template.
- (e) The proposer repo itself is public code; any given deployment of it
  runs as a private instance clone over the human's own workspaces.

## Rationale

Confound avoidance: a harness that could see and reason about its own
evaluation data would contaminate the evaluation. A one-way, on-demand pull
keeps the data flow from workspace to proposer strictly one-directional and
opt-in. Keeping the store a plain file tree matches the Meta-Harness paper's
method of proposing from filesystem-level feedback (raw traces, not just
scores) and needs no bespoke API. Routing changes through a PR/MR reuses
the human's existing review habit as the sole gate — no new trust
boundary is introduced.

## Consequences

- Two codebases to maintain: this template and `meta-morpheus-os`.
- The store layout is a versioned contract (`store_version` in
  `manifest.tsv`) — a proposer and an exporter must agree on it, and a
  layout change is a breaking change to that contract.
- This template gains one inert script (`scripts/export-experience.sh`)
  and no proposer-side logic, preferences key, or workflow phase.
- `sessions_missing` in a manifest counts session rows not resolvable in the
  store at export time; once a transcript is in the store, later exports
  resolve to the store copy even if the source file is gone.

## Reversible

Yes — delete `scripts/export-experience.sh`, its runbook and commands, and
retire the `meta-morpheus-os` repo; the run record itself is unaffected and
stays exactly as useful for local `scorecard.sh` reporting.
