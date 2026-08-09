# Phase: delivering

## Entry

Verification is complete and everything is green. Status is `delivering`.

## Steps

1. Pre-flight: for each affected repo, confirm the host CLI is authenticated
   (`scripts/lib.sh` host detection, then `glab auth status` for GitLab or
   `gh auth status` for GitHub).
2. GATE: present the verification report summary plus a proposed MR
   title/description per repo (apply `config/preferences.md` MR format) to
   the human. Wait for explicit approval — per
   `workflow/WORKFLOW.md` § Human gates.
3. On approval, per affected repo:
   - Push the branch from its worktree: `git push -u origin <branch>` (the
     branch named in the implementation plan's `## Delivery` section — ask
     the worktree if unsure: `git symbolic-ref --short HEAD`).
   - Create the MR: GitLab host → `glab mr create` (source branch, target
     `default_branch`, title, description); GitHub host → `gh pr create`.
   - Record the MR URL in `task.md` `mr:`, and append the gate-3 approval
     record to `## Activity`:
     `- YYYY-MM-DD — delivery approved, MR created: <url>`.
4. Write-time KB harvest (checklist, do not skip any item):
   - Draft new-learning docs from `templates/knowledge/` for anything
     learned this task.
   - Check every doc in `knowledge/repos/<affected-repo>/` against the
     delivered diff — update or deprecate any claim the diff invalidates.
   - Update the affected `index.md` files.
5. Close out: `task.md`/`epic.md` `status: done`, append the `## Activity`
   line, and `scripts/worktree.sh remove <repo-id> <work-id>` for each
   affected repo. How the folder moves depends on what kind of work item this
   is (per `workflow/WORKFLOW.md` § States):
   - Top-level item (standalone task/story, or an epic): move its folder to
     `work/done/`.
   - Epic CHILD (a story/task nested under `work/<state>/E-.../`): do NOT
     move its folder — it stays inside the epic for its whole lifecycle.
     Only update its `status:`/`## Activity`, then check off its line in the
     epic's own `epic.md` `## Stories` checklist. Once every child is
     `done`|`cancelled`, move the EPIC's own folder to `work/done/` (this
     carries the whole subtree, children included).

## Exit

`status: done`, no worktrees remaining for this work item. Folder under
`work/done/` for a top-level item or a fully-closed epic; an epic child stays
in place inside its epic's folder.

## Hard rules

- No push, no MR, without explicit human approval given IN THIS PHASE —
  approvals from the plan-review or impl-review gates do not carry forward.
- Never skip the KB harvest, even for a small task.
- Leave no orphaned worktrees.
