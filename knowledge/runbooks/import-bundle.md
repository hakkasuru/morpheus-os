---
type: Runbook
title: "Import bundle"
description: "Register an external knowledge bundle and vendor it read-only under knowledge/bundles/."
status: stable
created: 2026-08-04
updated: 2026-08-04
stale_after: null # YYYY-MM-DD — re-verify after this date
tags: [knowledge-base, bundle, sharing, import]
repo: null
generated_by: null # agent name when agent-authored
verified: null # YYYY-MM-DD — set when a human reviews an agent-authored doc
---

# Import bundle

## Trigger

The human says "import bundle `<url>`" (or asks to use someone else's
knowledge bundle).

## Preconditions

- The git URL is reachable and points at a repo of OKF-style markdown
  concepts (frontmatter + `index.md` files). A plain docs repo also works —
  it just navigates less cleanly.
- Running from the workspace root.

## Steps

1. Derive `name` from the repo name (last path segment of the URL, without
   `.git`). Confirm the name with the human before using it.

2. Append the entry to `config/bundles.yaml`. `name:` must be the entry's
   first key; `ref:` is optional (branch or tag to track).

   ```yaml
   - name: <name>
     remote: <url>
     ref: <branch-or-tag>   # optional
   ```

3. Sync it.

   ```
   scripts/sync-bundles.sh --bundle <name>
   ```

4. Orient: read `knowledge/bundles/<name>/index.md` (or the repo README when
   there is no index) and report to the human what the bundle contains.

5. Treat the vendored copy as READ-ONLY. Never edit files under
   `knowledge/bundles/` — corrections or observations about imported
   knowledge go in your own `knowledge/notes/` docs, linking to the bundle
   doc they concern. Re-sync updates with `scripts/sync-bundles.sh`.

## Rollback

**[destructive — confirm]** Remove the entry from `config/bundles.yaml`,
then:

```
rm -rf knowledge/bundles/<name>
```

## Verification

`scripts/sync-bundles.sh` reports the bundle up to date, and
`scripts/validate.sh` reports `validate: OK` (vendored bundles are excluded
from validation).
