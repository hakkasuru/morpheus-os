---
type: Runbook
title: "KB review"
description: "Periodic knowledge-base maintenance: clear stale/draft warnings and sweep for silent drift against each repo's history."
status: stable
created: 2026-08-01
updated: 2026-08-01
stale_after: null # YYYY-MM-DD — re-verify after this date
tags: [knowledge-base, maintenance, review]
repo: null
generated_by: null # agent name when agent-authored
verified: null # YYYY-MM-DD — set when a human reviews an agent-authored doc
---

# KB review

## Trigger

The human asks for a KB review. Recommended weekly-ish.

## Preconditions

- Running from the workspace root.
- `knowledge/` contains at least one doc (otherwise there is nothing to
  review).

## Steps

1. Run validation and collect its `stale_after` and old-draft warnings.

   ```
   scripts/validate.sh
   ```

2. For each doc flagged stale: re-verify its claims against reality (the
   code, URLs, or other source it describes). Then either bump `updated:`
   and `stale_after:` to reflect the re-verification, or set
   `status: deprecated` if it no longer holds.

3. For each doc flagged as an old draft: promote it to `status: stable` if
   its content checks out, or update it if it needs fixing. **[destructive
   — confirm]** Delete it instead if it is no longer useful.

4. Silent-drift sweep: for each `knowledge/repos/<id>/`, compare its docs
   against what actually changed in the repo since each doc's `updated:`
   date.

   ```
   git -C repos/<id> log --oneline --since=<doc updated date>
   ```

   Investigate any doc whose subject area shows up in that log — it may be
   stale even without having crossed its `stale_after` date.

5. Update the `index.md` of every directory touched in steps 2-4.

## Rollback

Every doc is a plain file tracked in git — `git checkout -- <path>`
reverts a single edit. Deletions from step 3 are the only irreversible
action here and already require confirmation.

## Verification

`scripts/validate.sh` emits no stale or old-draft warnings, or every
warning remaining is one you deliberately chose to leave (e.g. a
`stale_after` bumped forward on purpose).
