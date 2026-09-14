---
type: Runbook
title: "Workspace setup"
description: "First-time setup of a freshly cloned workspace: prerequisites, remotes (template as push-disabled upstream, your repo as origin), repo onboarding, preferences interview, validation."
status: stable
created: 2026-08-01
updated: 2026-09-14
stale_after: null # YYYY-MM-DD — re-verify after this date
tags: [setup, onboarding, preferences, upstream]
repo: null
generated_by: null # agent name when agent-authored
verified: null # YYYY-MM-DD — set when a human reviews an agent-authored doc
---

# Workspace setup

## Trigger

Fresh clone (the registry still has only the example repos in
`config/repos.yaml`, `config/preferences.md` is untouched) or the human
asks for setup help.

## Preconditions

- None beyond a local clone of this workspace — this is usually the first
  runbook run in it.

## Steps

1. Verify prerequisites: `git` and `bash` present; `glab auth status`
   and/or `gh auth status` for whichever host(s) the human will use. Warn
   on any gap — do not stop.

   ```
   command -v git >/dev/null || echo "missing: git"
   command -v bash >/dev/null || echo "missing: bash"
   glab auth status || true
   gh auth status || true
   ```

2. Remotes: the public template must never receive this workspace's
   pushes, and it stays available as the update channel. Check where
   `origin` points:

   ```
   git remote -v
   ```

   - `origin` still points at the public template
     (`github.com/hakkasuru/morpheus-os`) → rename it to `upstream` and
     disable pushes to it:

     ```
     git remote rename origin upstream
     git remote set-url --push upstream DISABLED
     ```

     Then ask the human for the URL of their own (ideally private) repo
     and add it as `origin`. **[destructive — confirm]** the first push
     — it publishes `main` to that repo:

     ```
     git remote add origin <your-repo-url>
     git push -u origin main
     ```

     No repo yet → leave `origin` absent, say so, and note that
     `update-harness` step 6 and any `git push` will fail until one is
     added.

   - `origin` already points at the human's own repo → only make sure an
     `upstream` exists for updates, push-disabled:

     ```
     git remote add upstream <template-url>
     git remote set-url --push upstream DISABLED
     ```

   Either way, finish with `git remote -v` showing `upstream` with
   `DISABLED` as its push URL. Updates later come through the
   `update-harness` runbook (`/knowledge/runbooks/update-harness.md`).

3. Ask which repositories to manage. For each one, run the `add-repo`
   runbook (`/knowledge/runbooks/add-repo.md`).

4. Offer to remove the two example entries (`spring-petclinic`,
   `gitlab-nodejs-example`) from `config/repos.yaml` once real repos have
   been added.

5. Interview for `config/preferences.md`: ask one question per commented
   section (Git & Delivery, Coding Defaults, Working Style), and
   uncomment/fill whatever the human confirms. Skip sections freely when
   the human has no preference yet.

6. Run `scripts/validate.sh` and confirm it reports `validate: OK`.

   ```
   scripts/validate.sh
   ```

7. **[destructive — confirm]** Suggest a first commit of the personalized
   workspace, and — since step 2 guarantees `origin` is the human's own
   repo and `upstream` cannot be pushed to — offer to push it.

   ```
   git add config/ knowledge/
   git commit -m "chore: personalize workspace"
   git push origin main
   ```

## Rollback

Everything touched here is a plain file tracked in git —
`git checkout -- config/` restores `config/repos.yaml` and
`config/preferences.md` to their template state. Repos cloned via the
`add-repo` runbook are rolled back per that runbook. Remotes:
`git remote rename upstream origin` and `git remote set-url --push origin
<template-url>` undo step 2 (only sensible if the clone should go back to
being a plain template checkout).

## Verification

`scripts/validate.sh` reports `validate: OK`, at least one real
(non-example) repo is cloned under `repos/`, and `git remote -v` shows
`upstream` with push URL `DISABLED` and `origin` pointing at the human's
own repo (or absent, by their choice).
