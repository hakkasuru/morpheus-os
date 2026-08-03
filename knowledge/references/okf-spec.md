---
type: Reference
title: "OKF spec"
description: "Where the upstream Open Knowledge Format spec lives, and which version this knowledge base tracks."
status: stable
created: 2026-08-04
updated: 2026-08-04
stale_after: 2027-02-04 # YYYY-MM-DD — re-verify after this date
tags: [knowledge-base, okf, spec]
repo: null
generated_by: null # agent name when agent-authored
verified: null # YYYY-MM-DD — set when a human reviews an agent-authored doc
---

# OKF spec

## What it is

The Open Knowledge Format (OKF) — the upstream convention this knowledge
base's OKF-lite format derives from: markdown concepts with YAML
frontmatter, per-directory `index.md` progressive disclosure, and a small
conformance bar (`type:` is the only required field). This workspace
tracks the version stamped as `okf_version` in `/knowledge/index.md`; what
was adopted vs. deliberately omitted is recorded in the
[adoption decision](/knowledge/decisions/adopt-okf-lite-kb.md).

## URLs

- Spec (authoritative): <https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md>
- Repo with example bundles and tooling: <https://github.com/GoogleCloudPlatform/knowledge-catalog>

## When to use

- Checking whether a newer spec version exists and what changed — the
  first step of the [KB migrate runbook](/knowledge/runbooks/kb-migrate.md).
- Settling a format question the templates don't answer (link semantics,
  reserved filenames, conformance rules).
