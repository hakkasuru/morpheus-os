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
   - Push the branch from its worktree: `git push -u origin work/<work-id>`.
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
5. Close out: `task.md` `status: done`, append the `## Activity` line, move
   the folder to `work/done/`, and
   `scripts/worktree.sh remove <repo-id> <work-id>` for each affected repo.

## Exit

`status: done`, folder under `work/done/`, no worktrees remaining for this
work item.

## Hard rules

- No push, no MR, without explicit human approval given IN THIS PHASE —
  approvals from the plan-review or impl-review gates do not carry forward.
- Never skip the KB harvest, even for a small task.
- Leave no orphaned worktrees.
