---
type: Runbook
title: "Share bundle"
description: "Export a knowledge/ subtree as a standalone OKF bundle others can import."
status: stable
created: 2026-08-04
updated: 2026-08-04
stale_after: null # YYYY-MM-DD — re-verify after this date
tags: [knowledge-base, bundle, sharing, export]
repo: null
generated_by: null # agent name when agent-authored
verified: null # YYYY-MM-DD — set when a human reviews an agent-authored doc
---

# Share bundle

## Trigger

The human asks to share or publish part of the knowledge base (e.g. "share
my `<repo-id>` notes with the team").

## Preconditions

- The human has named the subtree to export (typically
  `knowledge/repos/<id>/`, or a topic directory).
- The human has a destination in mind (a new git repo they own).

## Steps

1. Confirm scope with the human: exactly which directory, and where the
   standalone repo will live. Warn that everything in the subtree becomes
   visible to whoever can read the destination — sweep it for anything
   private before exporting.

2. Copy the subtree to a fresh directory outside this workspace and
   `git init` it. The copied directory root is the new bundle root.

3. Rebase links. Workspace docs use bundle-relative links rooted at this
   workspace (`/knowledge/...`); in the exported bundle they must be
   relative to the NEW bundle root. Rewrite:
   - links into the exported subtree → root-relative within the new bundle
     (e.g. `/knowledge/repos/<id>/gotchas.md` → `/gotchas.md`);
   - links that point OUTSIDE the exported subtree → either drop the link
     (keep the text), or leave it and note in the bundle README that it
     refers to knowledge not included. Broken links are legal in OKF, but
     be deliberate about them.

4. Stamp conformance: ensure the bundle root has an `index.md` listing its
   contents, carrying `okf_version: "0.2"` frontmatter (the root index is
   the only index allowed frontmatter).

5. Review trust fields with the human: every doc already carries
   `generated_by:`; docs the human has actually reviewed should get
   `verified: YYYY-MM-DD` in their frontmatter so consumers can tell
   reviewed knowledge from raw agent output.

6. Conformance check over the export: every non-index `.md` has frontmatter
   with a non-empty `type:`; every directory has an `index.md` listing its
   real contents; no secrets, tokens, internal hostnames, or personal data
   anywhere (grep before shipping).

7. Commit inside the new repo and hand it to the human to push
   **[destructive — confirm]** (pushing publishes the content to wherever
   the remote lives).

## Rollback

Before the human pushes, the export is just a local directory — delete it.
After a push, treat it as published: removing it from the remote does not
un-share it.

## Verification

The exported bundle opens cleanly from its own root: `index.md` navigates to
every doc, `okf_version` is stamped, and a grep for private material comes
back empty.
