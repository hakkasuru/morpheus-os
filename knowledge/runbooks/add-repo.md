---
type: Runbook
title: "Add repo"
description: "Register a new repo, clone it, detect its quality gates, and seed its knowledge-base section."
status: stable
created: 2026-08-01
updated: 2026-08-01
stale_after: null # YYYY-MM-DD — re-verify after this date
tags: [repo, registry, onboarding, knowledge-base]
repo: null
generated_by: null # agent name when agent-authored
---

# Add repo

## Trigger

The human says "add repo `<url>`", or this runbook is invoked from within
`workspace-setup`.

## Preconditions

- The git URL is reachable.
- Running from the workspace root.

## Steps

1. Derive `id` from the repo name (last path segment of the URL, without
   `.git`). Confirm the id with the human before using it.

2. Append the entry to `config/repos.yaml`. `id:` must be the entry's
   first key. Detect `default_branch` with:

   ```
   git ls-remote --symref <url> HEAD
   ```

   Leave `commands:` empty for now; set `notes: knowledge/repos/<id>/`.

   ```yaml
   - id: <id>
     remote: <url>
     default_branch: <detected-branch>
     notes: knowledge/repos/<id>/
   ```

3. Clone it.

   ```
   scripts/sync-repos.sh --repo <id>
   ```

4. Detect quality-gate commands from the clone: `package.json` scripts,
   `Makefile` targets, `mvnw`/`gradlew` wrappers, `cargo` (Cargo.toml),
   `go.mod`. Propose `commands:` entries (`test`/`lint`/`build` as
   applicable), confirm with the human, then write them into the registry
   entry under `commands:`.

5. Seed the knowledge-base section. Create `knowledge/repos/<id>/` with:
   - `index.md` (constraint 7 bullet format, no frontmatter).
   - `architecture.md` — from `templates/knowledge/note.md`, `type: Note`,
     `status: draft`, `repo: <id>`, `generated_by: <your agent name>`.
   - `conventions.md` — same template/status/repo/generated_by.

   Populate both by read-only exploration of `repos/<id>`: structure,
   entry points, key modules, data flow for `architecture.md`; code style,
   test layout, and branch/MR habits from `git log` for `conventions.md`.
   Never invent content the exploration didn't turn up.

6. Run validation.

   ```
   scripts/validate.sh
   ```

## Rollback

**[destructive — confirm]** Remove the registry entry from
`config/repos.yaml`, then:

```
rm -rf repos/<id> knowledge/repos/<id>
```

## Verification

`scripts/sync-repos.sh --repo <id>` reports the repo synced, and
`scripts/validate.sh` reports `validate: OK`.
