# Morpheus OS

> Agents: read [`AGENTS.md`](AGENTS.md) instead of this file — it is the
> canonical instruction set. This README is for humans.

Morpheus OS is a personal agent harness workspace: a repo registry, a
planning discipline, a knowledge base, and a set of runbooks that give any
coding agent a consistent, auditable process for working across your
repos. It works with Claude Code, GitHub Copilot, Codex, or any agent that
reads `AGENTS.md`.

## Directory map

| Path | Purpose |
| --- | --- |
| `config/` | Repo registry (`repos.yaml`) and personal preferences (`preferences.md`). |
| `repos/` | Clones of registered repos, one dir per repo id. |
| `worktrees/` | Per-task worktrees checked out from `repos/`. |
| `scripts/` | Bash automation: sync, work scaffolding, worktree management, validation. |
| `workflow/` | The work lifecycle definition and per-phase instructions. |
| `templates/` | Document shapes for work items and knowledge docs. |
| `work/` | Work items in flight (`backlog/`, `active/`, `done/`). |
| `knowledge/` | Durable knowledge base about your registered repos. |

## Workflow

```mermaid
flowchart LR
    intake --> context --> planning
    planning --> plan_review{{"PLAN REVIEW (human or auto)"}}
    plan_review --> impl_planning["impl-planning"]
    impl_planning --> impl_review{{"IMPL REVIEW (human or auto)"}}
    impl_review --> executing --> verifying
    verifying --> delivery_confirm{{"DELIVERY CONFIRM (human, always)"}}
    delivery_confirm --> done
```

There are three review gates: after the plan, after the implementation
plan, and before anything is pushed or opened as an MR/PR. A plan-review
subagent audits the first two and can auto-approve high-confidence plans
when you opt in (see How to use it); the delivery gate is always yours.

## First-time setup

### Make it yours

This repo is a **template** — don't work inside a clone that still points
at the public repo. Fork it (GitHub's **"Use this template"** button) or
make your own copy, and set it **private** if your repo registry or
knowledge base shouldn't be public:

```
git clone <public-template-url> my-workspace
cd my-workspace
git remote set-url origin <your-private-repo-url>
git push -u origin main
```

Optional: keep the public template as an update channel via a second
remote:

```
git remote add upstream <public-template-url>
git pull upstream main
```

**Recommended: never push to the template origin.** Your workspace
(registry, preferences, knowledge base) must not land on the public
template repo. Re-point `origin` to your own repo *before* your first
push (as shown above), and if you keep the template as `upstream`,
disable pushes to it so an accidental `git push upstream` can't happen:

```
git remote set-url --push upstream DISABLED
```

This stays low-conflict because personal layers (`config/`, `work/`,
`knowledge/`) rarely touch harness machinery (`scripts/`, `workflow/`,
`templates/`, `AGENTS.md`).

After any upstream pull, read [`CHANGELOG.md`](CHANGELOG.md) — every
entry says what changed in behavior and whether your copy needs action.
Then run `scripts/validate.sh`: the harness declares
which knowledge-format version it supports, and the validator compares it
against your knowledge base's `okf_version` stamp — if the update moved
the format ahead of your docs, it says so and points you at the
`kb-migrate` runbook to bring them up to date.

Committing your workspace is optional and always yours to trigger —
nothing in the harness auto-commits or auto-pushes it; skipping just
costs you git's history/backup/machine-migration benefits. Your
registered code repos are unaffected either way — `repos/` and
`worktrees/` are gitignored, and their changes ship via branches + MRs to
their own remotes.

### Recommended: agent-guided setup

1. Clone your copy (see "Make it yours" above).
2. Open your coding agent in the repo root.
3. Say **"set up my workspace"**.

The agent runs the `workspace-setup` runbook, which:

- Verifies prerequisites are installed and authenticated.
- Onboards your repos via the `add-repo` runbook — registry entry, clone,
  gate-command detection, and a seeded knowledge base section per repo.
- Interviews you to fill in `config/preferences.md`.
- Smoke-tests the result with `scripts/validate.sh`.

**Prerequisites:** `git`, `bash`, a coding agent, and `glab` and/or `gh`
authenticated (`glab auth login` / `gh auth login`) for whichever host(s)
you use. Optional: `yq`, `shellcheck`.

<details>
<summary>Manual setup path</summary>

1. Hand-edit `config/repos.yaml` to add your repos.
2. Run `scripts/sync-repos.sh` to clone them under `repos/`.
3. Hand-edit `config/preferences.md` with your conventions.
4. Run `scripts/validate.sh` to smoke-test the setup.

Repos added this way start with an empty knowledge base section — the
agent has not onboarded them, so nothing has been seeded under
`knowledge/repos/<id>/`.

</details>

**Known limitations:**

- The `CLAUDE.md` and `.github/copilot-instructions.md` symlinks require
  macOS or Linux. On Windows, enable `core.symlinks` in git or the files
  will check out as broken links.
- Server-side GitHub Copilot features may not follow symlinks; if Copilot
  doesn't pick up `AGENTS.md` via the symlink, point it at the file
  directly.

## How to use it

Start work by scaffolding a work item, or just tell the agent what you
want done and let it scaffold for you:

```
scripts/new-work.sh task|story|epic "<title>"
```

| Phase | What happens | What you're asked |
| --- | --- | --- |
| intake | Work item is scaffolded and framed. | — |
| context | Agent reads the relevant repo(s) and knowledge base. | — |
| planning | Agent drafts a plan. | — |
| plan-review | A plan-review subagent audits the plan (assumptions, doubts, missing context) and scores its confidence. | **Approve or revise the plan** — or nothing, if you've enabled auto-approval and the score clears your threshold. |
| impl-planning | Agent breaks the plan into an implementation plan. | — |
| impl-review | Same subagent review as plan-review, against the implementation plan. | **Approve or revise the implementation plan** — same optional auto-approval. |
| executing | Agent delegates implementation to subagents in worktrees. | — |
| verifying | Agent runs verification commands. | — |
| delivering | — | **Confirm before push / MR / PR — always; delivery never auto-approves.** |
| done | Work item is closed out and learnings are harvested to the KB. | — |

Review gates 1–2 can approve automatically: set an auto-approve threshold in
`config/preferences.md` (off by default) and plans whose review confidence
clears it proceed without waiting for you. Hard caps always override —
plans with open questions for you, destructive steps, or security-touching
scope come to you regardless of score (see `workflow/plan-reviewer.md`).
Every auto-approval is recorded in the doc (`approved_by:`) and the task's
Activity log, and you can veto one after the fact by setting the doc to
`changes-requested`.

Other things you can do:

- **Run a runbook:** "run the `<name>` runbook."
- **Ad-hoc ops:** ask the agent to run a one-off shell or MCP operation.
- **Ask questions:** the knowledge base can answer "how does repo X work?"
  without starting a work item.
- **Work in parallel:** every task executes in its own worktree, so
  multiple tasks are safe to run at once. List them with
  `scripts/worktree.sh list`.

## How to maintain it

**Weekly-ish:**

- Run `scripts/validate.sh`.
- Run the `kb-review` runbook.
- Prune finished items out of `work/done/`.

**Adding a repo:** tell the agent "add repo `<url>`", or do it manually
(see Manual setup path above).

**Removing a repo:** reverse the add — drop its `config/repos.yaml` entry
and its `repos/<id>` clone; optionally keep its `knowledge/repos/<id>/`
section for future reference.

**Where are we?** `scripts/status.sh` — a token-free dashboard: work items
by state (flagging gates waiting on you and blocked items), worktrees
(flagging orphans), repo clone state, and validation warnings.

**Housekeeping:** run `scripts/status.sh` periodically (it subsumes
`worktree.sh list` and the validation sweep), and keep
`config/preferences.md` current as your conventions change.

**Sharing knowledge bundles:** the knowledge base speaks
[OKF](https://github.com/GoogleCloudPlatform/knowledge-catalog) — a
knowledge bundle is just a directory of markdown concepts, so knowledge
moves in both directions:

- *Import:* "import bundle `<url>`" registers an external bundle in
  `config/bundles.yaml` and vendors it read-only under
  `knowledge/bundles/<name>/` (gitignored; `scripts/sync-bundles.sh`
  re-syncs it). Your agent navigates it like native knowledge.
- *Export:* "share my `<repo-id>` notes" runs the `share-bundle` runbook —
  it copies the subtree to a standalone repo, rebases links, stamps
  `okf_version`, checks conformance and sweeps for private material before
  you push it anywhere.

**Evolving the harness** — customize from the most specific layer down:

| Layer | Governs |
| --- | --- |
| `config/preferences.md` | Your personal conventions. |
| `config/repos.yaml` | Registered repos and their gate commands. |
| `templates/` | The shape of work-item and knowledge documents. |
| `workflow/phases/` | Process behavior at each phase. |
| `AGENTS.md` | Hard rules that apply everywhere. |

**Migrating machines:** clone this repo, then run `scripts/sync-repos.sh`
to re-clone your registered repos.
