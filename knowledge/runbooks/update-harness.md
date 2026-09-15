---
type: Runbook
title: "Update harness"
description: "Pull the latest harness machinery from the public template (upstream) into this workspace, apply the changelog's action items, verify, push to origin."
status: stable
created: 2026-09-14
updated: 2026-09-15
stale_after: null # YYYY-MM-DD — re-verify after this date
tags: [maintenance, upstream, template]
repo: null
generated_by: null # agent name when agent-authored
verified: null # YYYY-MM-DD — set when a human reviews an agent-authored doc
---

# Update harness

## Trigger

The human asks to update the harness / pull the latest template
("update the harness", "pull upstream"), or wants to know whether the
template has moved.

## Preconditions

- An `upstream` remote pointing at the public template
  (`github.com/hakkasuru/morpheus-os`) with pushes disabled, and an
  `origin` pointing at the human's own repo — the `workspace-setup`
  runbook's remotes step creates both. If `upstream` is missing, run
  that step first (`/knowledge/runbooks/workspace-setup.md`, step 2).

  ```
  git remote -v
  # expected:
  #   origin    <your-repo-url> (fetch) / (push)
  #   upstream  <template-url>  (fetch)
  #   upstream  DISABLED        (push)
  ```

- A clean working tree on `main`. Uncommitted work would be dragged into
  the merge — stop and let the human commit or stash it first.

  ```
  git status --short
  git branch --show-current
  ```

## Steps

1. Fetch the template and show what is incoming: the commits, and the
   `CHANGELOG.md` entries the workspace does not have yet. Every entry
   says whether the human's copy needs action after pulling — read them
   out before merging anything.

   ```
   git fetch upstream
   git log --oneline HEAD..upstream/main
   git diff HEAD...upstream/main -- CHANGELOG.md
   ```

   Nothing listed → the harness is current; stop here and say so. The
   session brief also says `Harness update available: upstream/main is <v>`
   when `VERSION` upstream is newer — that line is the cheap way to
   notice.

2. **[destructive — confirm]** Merge `upstream/main` into `main`. Show the
   human the file list first (`git diff --stat HEAD...upstream/main`):
   personal layers (`config/`, `work/`, `knowledge/` outside
   `knowledge/bundles/`) should rarely appear — if they do, call it out.

   ```
   git merge --no-edit upstream/main
   ```

   On conflicts: harness machinery (`scripts/`, `workflow/`,
   `templates/`, `AGENTS.md`, `.claude/`, `.github/`) takes the upstream
   side unless the human customized it deliberately; personal layers
   take the local side. Resolve, `git add`, `git commit --no-edit`.
   When in doubt, stop and ask — never guess a conflict resolution.

3. Apply the changelog's action items. Re-read the entries from step 1
   and do exactly what each "Action needed after pulling?" says — a
   template refresh, a `kb-migrate` run, a preference to uncomment, a
   session restart. Note anything the human must do themselves.

4. Verify.

   ```
   scripts/validate.sh
   scripts/session-brief.sh --no-mr-check
   ```

   `validate: OK` is required. A knowledge-format (`okf_version`)
   mismatch is reported here and points at the `kb-migrate` runbook —
   run it if so.

5. If `.claude/settings.json`, `.github/hooks/` or anything under
   `.claude/` changed, tell the human to restart the session (or open
   `/hooks` once) so the client picks the changes up.

6. **[destructive — confirm]** Push the updated `main` to the human's own
   repo. Never to `upstream` — its push URL is `DISABLED` for exactly this
   reason; if a push to upstream ever "succeeds", the remotes are
   misconfigured (fix per `workspace-setup` step 2).

   ```
   git push origin main
   ```

## For template maintainers

Every change to the template bumps `VERSION` (major when the changelog
entry has an action item, minor for new behaviour, patch for fixes/docs)
and the new `CHANGELOG.md` entry heading is `## <version> — <date>`;
`scripts/validate.sh --harness` fails when they disagree.

## Rollback

- Merge still in progress (conflicts): `git merge --abort`.
- Merge committed but not pushed: `git reset --hard ORIG_HEAD`
  **[destructive — confirm]** — this also discards any conflict
  resolutions and action-item edits made since.
- Already pushed: revert the merge commit (`git revert -m 1 <merge-sha>`)
  rather than rewriting `origin/main`.

## Verification

`git log --oneline -1 upstream/main` is an ancestor of `main`
(`git merge-base --is-ancestor upstream/main main` exits 0),
`scripts/validate.sh` reports `validate: OK`, and `git status` shows
`main` up to date with `origin/main`.
