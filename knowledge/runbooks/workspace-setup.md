---
type: Runbook
title: "Workspace setup"
description: "First-time setup of a freshly cloned workspace: prerequisites, repo onboarding, preferences interview, validation."
status: stable
created: 2026-08-01
updated: 2026-08-01
stale_after: null # YYYY-MM-DD — re-verify after this date
tags: [setup, onboarding, preferences]
repo: null
generated_by: null # agent name when agent-authored
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

2. Ask which repositories to manage. For each one, run the `add-repo`
   runbook (`/knowledge/runbooks/add-repo.md`).

3. Offer to remove the two example entries (`spring-petclinic`,
   `gitlab-nodejs-example`) from `config/repos.yaml` once real repos have
   been added.

4. Interview for `config/preferences.md`: ask one question per commented
   section (Git & Delivery, Coding Defaults, Working Style), and
   uncomment/fill whatever the human confirms. Skip sections freely when
   the human has no preference yet.

5. Run `scripts/validate.sh` and confirm it reports `validate: OK`.

   ```
   scripts/validate.sh
   ```

6. **[destructive — confirm]** Suggest a first commit of the personalized
   workspace. Confirm with the human that `origin` points at their own
   fork/copy of this repo (not the upstream template) before any push —
   per README "Make it yours" — this runbook only ever proposes a local
   commit, never a push.

   ```
   git add config/ knowledge/
   git commit -m "chore: personalize workspace"
   ```

## Rollback

Everything touched here is a plain file tracked in git —
`git checkout -- config/` restores `config/repos.yaml` and
`config/preferences.md` to their template state. Repos cloned via the
`add-repo` runbook are rolled back per that runbook.

## Verification

`scripts/validate.sh` reports `validate: OK` and at least one real
(non-example) repo is cloned under `repos/`.
