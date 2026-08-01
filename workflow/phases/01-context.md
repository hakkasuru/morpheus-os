# Phase: context

## Entry

Status is `context`. Folder already moved `work/backlog/` → `work/active/`
and `status:` already set to `context` (this happens together, per
WORKFLOW.md).

## Steps

1. Read `task.md` `## Request` and `## Acceptance Criteria`. For every repo
   listed in its `repos:` field, read `knowledge/repos/<id>/index.md` and
   whatever relevant docs it points to. Read `config/preferences.md` if not
   already loaded this session.
2. Write clarifying questions FIRST, before exploring: create
   `01-context.md` from `templates/work/01-context.md`, fill in
   `## Questions for the human`. Ask the human. Record the answers inline
   before moving on.
3. Explore: dispatch read-only subagents into `repos/<id>` for each
   affected repo. Never modify anything in this phase — this is a read-only
   phase. Land findings as `## Findings` bullets, each citing a concrete
   `repo/path/file.ext:line`.
4. Read-time KB check: for every knowledge doc you consulted in step 1,
   check its `stale_after:` against today and check it against what
   exploration actually found. If it's past `stale_after` or contradicts
   what you found: verify the doc's claims against the code NOW, then
   either fix the doc and bump its `updated:` (and `stale_after:`), or mark
   it `status: deprecated`. Note the correction in `01-context.md`.
5. Fill the remaining sections of `01-context.md`: `## Repos involved`,
   `## Findings`, `## Constraints`, `## Related knowledge` (links into
   `/knowledge/...`, noting any doc you corrected or deprecated).

## Exit

All questions answered, and findings are sufficient to write a plan. Set
`status: planning`.

## Hard rules

- This phase never touches `repos/<id>` beyond reading — no edits, no
  worktrees.
- Questions come before exploration, not after.
- Every finding cites `file:line`. No unsupported claims.
- Never skip the read-time KB staleness check.
