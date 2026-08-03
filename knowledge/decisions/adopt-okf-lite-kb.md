---
type: Decision
title: "Adopt OKF-lite for the knowledge base"
description: "Use a lightweight, OKF-inspired markdown+frontmatter convention for all knowledge-base docs."
status: stable
created: 2026-08-01
updated: 2026-08-04
stale_after: null # YYYY-MM-DD — re-verify after this date
tags: [knowledge-base, format, okf-lite]
repo: null
generated_by: null # agent name when agent-authored
---

# Adopt OKF-lite for the knowledge base

## Context

The knowledge base needs a format that agents can parse reliably without
extra tooling and that humans can read as plain markdown. It also needs to
stay lean under context limits, since agents read it every session.

## Decision

Adopt an OKF-inspired ("OKF-lite") convention for every knowledge doc:

- Markdown body with a YAML frontmatter block.
- `type` (`Note | Decision | Runbook | Reference`) as the routing key.
- Per-directory `index.md` files for progressive disclosure — read the
  index before opening any document it lists.
- `status: draft | stable | deprecated` on every doc.
- Absolute `stale_after` dates (`YYYY-MM-DD`) rather than relative TTLs.
- Bundle-relative links (e.g. `/knowledge/runbooks/add-repo.md`).
- Broken links are legal — the KB is allowed to reference a doc that does
  not exist yet.

## Rationale

Frontmatter plus a fixed `type` set is agent-parseable with plain
`awk`/`grep`, no YAML library required. Markdown diffs cleanly and is
portable outside this harness. Full OKF's attestation and provenance
machinery solves problems (multi-party trust, cryptographic signing) a
personal, single-operator KB does not have — carrying it here would add
weight without benefit.

## Consequences

- Every KB doc (except `index.md`) carries the standard frontmatter
  fields: `type`, `title`, `description`, `status`, `created`, `updated`,
  `stale_after`, `tags`, `repo`, `generated_by`.
- Every KB directory's `index.md` must be kept current whenever a doc is
  added, removed, or renamed.
- `scripts/validate.sh` enforces the type set, frontmatter presence,
  `stale_after` staleness, and draft age — humans and agents both get an
  early warning when the convention drifts.

## Reversible

Yes — this is plain markdown with no external dependency. Migrating to a
different convention is a frontmatter rewrite across `knowledge/**/*.md`,
not a data migration.

## Amendments

Dated changes to this decision. New knowledge docs always take their shape
from `templates/knowledge/` and are enforced by `scripts/validate.sh` — an
amendment here records *why* those moved, it does not itself change them.

### 2026-08-04 — versioning, sharing, and the verified field

- The KB is now explicitly stamped: `okf_version: "0.2"` in
  `/knowledge/index.md`, mirrored by `SUPPORTED_OKF_VERSION` in
  `scripts/validate.sh`, which warns on drift between the two. Adopting a
  newer OKF version is a defined procedure — the
  [KB migrate runbook](/knowledge/runbooks/kb-migrate.md) — that amends
  this record as one of its steps.
- Knowledge now moves across trust boundaries: external bundles vendor in
  read-only under `knowledge/bundles/`
  ([import-bundle](/knowledge/runbooks/import-bundle.md)), and subtrees
  export as standalone conformant bundles
  ([share-bundle](/knowledge/runbooks/share-bundle.md)).
- One piece of OKF's trust machinery graduated from "omitted" to adopted,
  because sharing makes it meaningful: an optional `verified: YYYY-MM-DD`
  field, added when a human reviews an agent-authored doc, so bundle
  consumers can tell reviewed knowledge from raw agent output. The rest of
  the provenance/attestation machinery remains deliberately omitted.
