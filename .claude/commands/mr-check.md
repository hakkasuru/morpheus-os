---
description: Report the live state of every pending MR/PR (read-only)
---

Run `scripts/mr-check.sh` ($ARGUMENTS may name specific work ids) and
relay the verdicts per `workflow/WORKFLOW.md` § Pending MRs. Do not close,
cancel or reopen anything from the result — say what each verdict means
(merged → offer to close via `/close`; attention → offer `/feedback`;
closed without merge → ask whether to cancel or rework) and wait for the
human's ask.
