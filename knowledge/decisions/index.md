# Decisions

* [Adopt OKF-lite for the knowledge base](/knowledge/decisions/adopt-okf-lite-kb.md) - why the KB uses a lightweight, OKF-inspired markdown+frontmatter convention.
* [Instrument every work item as a run record for harness evaluation](/knowledge/decisions/instrument-runs-for-harness-evaluation.md) - version stamp, structured events, per-item traces and a scorecard so production runs can evaluate harness changes.
* [The proposer is a separate repo, pulling exports on demand](/knowledge/decisions/proposer-loop-separate-repo.md) - the Meta-Harness proposer lives in its own repo and pulls a workspace's exported run record; the template never reads or knows about the store.
