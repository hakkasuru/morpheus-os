---
description: Export this workspace's run record into an experience store (read-only here)
---

Run the export-experience runbook (`knowledge/runbooks/export-experience.md`)
with the destination named in $ARGUMENTS (`--dest <store>`; add
`--workspace-name <name>` when the folder name is not the wanted store name).
Always show the `--dry-run` list first, then export. On a secrets-sweep hit,
stop and show the hits — never pass `--ignore-sweep` without the human
saying so.
