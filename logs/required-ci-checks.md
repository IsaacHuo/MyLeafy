# Required CI checks and duplicate runs

In this repository, cancelling the pull-request CI for a commit left a failed `CI result` even though the push CI for the same commit succeeded. The protected main branch rejected the fast-forward push with `Required status check "CI result" is failing`.

Historical behavior before the 2026-10-24 fast-CI change required both pipelines to complete. Do not manually cancel a remaining required run under the old workflow. When cancelled dependencies caused the result job to fail, rerun the entire affected workflow on the same commit; rerunning only the result job retains the cancelled dependency conclusions. Preserve the task commits and the local fast-forward while resolving checks. Do not reset or bypass branch protection.

Inspect each run's source SHA and all required conclusions before pushing main. A green run for another commit does not resolve a failed current check.

## Current fast-CI behavior (2026-10-24)

The first shared-concurrency trial completed basic CI in 90 seconds, but a duplicate same-SHA cancelled check still left the PR BLOCKED. Suppressing a failure aggregator alone does not remove that cancelled required check.

Basic CI now triggers once per repository-branch push; pull requests reuse the source commit's checks and do not trigger another run. The branch concurrency group still cancels obsolete commits, whose checks cannot block the newer SHA. The latest effective run must actually succeed for the exact current commit. Its aggregator rejects failed/cancelled/missing or unexpectedly skipped selected jobs. Manual Full validation has a separate result and does not publish or become a daily required check. Preserve branch protection; never force-push main.
