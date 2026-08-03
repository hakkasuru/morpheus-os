---
type: Runbook
title: "KB migrate"
description: "Adopt a newer OKF spec version: update templates, validation, rules, and sweep every knowledge doc to the new shape."
status: stable
created: 2026-08-04
updated: 2026-08-04
stale_after: null # YYYY-MM-DD — re-verify after this date
tags: [knowledge-base, okf, migration, format]
repo: null
generated_by: null # agent name when agent-authored
---

# KB migrate

## Trigger

- `scripts/validate.sh` warns that the knowledge base's `okf_version`
  stamp differs from the version the harness supports — the usual sign
  after pulling template updates from upstream (`git pull upstream main`).
- The human asks to adopt a newer OKF version (or a change to this
  workspace's own OKF-lite conventions).

## Preconditions

- A clean working tree (`git status`) — the migration lands as one
  reviewable commit, and rollback is a revert.
- The upstream spec is reachable (see the
  [OKF spec reference](/knowledge/references/okf-spec.md)).

## Steps

1. Establish the delta. Read the current version from the `okf_version`
   frontmatter in `/knowledge/index.md`, fetch the target spec version,
   and diff the two: fields added, renamed, or removed; changes to the
   reserved files (`index.md`, `log.md`); changes to conformance rules.
   Present the human an impact summary — which of this workspace's docs,
   templates, and checks each change touches — and WAIT for approval of
   the adoption scope. Not every upstream change must be adopted; OKF-lite
   deliberately omits optional machinery (see the
   [adoption decision](/knowledge/decisions/adopt-okf-lite-kb.md)).

2. Update the shapes: `templates/knowledge/*.md` frontmatter and body
   conventions to the approved target shape.

3. Update enforcement: the knowledge checks in `scripts/validate.sh`
   (required fields, type vocabulary, index rules) so the validator
   defines the NEW conformance. Keep it bash-3.2 portable and
   shellcheck-clean.

4. Update the rules: AGENTS.md §5 (knowledge base rules) and append a
   dated amendment to the
   [adopt-okf-lite decision](/knowledge/decisions/adopt-okf-lite-kb.md)
   recording the version move and what was (not) adopted.

5. Sweep the corpus: mechanically rewrite the frontmatter of every doc
   under `knowledge/` — excluding `knowledge/bundles/` (vendored; their
   owners migrate them) — to the new shape. Prefer a small script for
   mechanical renames; hand-edit only where content judgment is needed.
   Re-run `scripts/validate.sh` after each pass until it reports OK with
   no warnings.

6. Bump the stamps — BOTH, so they stay in lockstep: the `okf_version`
   frontmatter in `/knowledge/index.md` (what the corpus is), and
   `SUPPORTED_OKF_VERSION` in `scripts/validate.sh` (what the harness
   enforces — skip if an upstream pull already bumped it). Update this
   runbook and the [OKF spec reference](/knowledge/references/okf-spec.md)
   if the spec moved or the migration surface changed.

7. Commit everything as ONE commit
   (`[kb] migrate knowledge format to <version>`) so the whole migration
   is one reviewable, revertible unit.

## Rollback

The migration is a single commit — `git revert <sha>` restores the
previous format end to end (templates, validator, rules, and corpus
together, so they never drift apart).

## Verification

`scripts/validate.sh` reports OK with no warnings; `okf_version` in
`/knowledge/index.md` matches the target; spot-open two migrated docs and
confirm their frontmatter matches the updated templates.
