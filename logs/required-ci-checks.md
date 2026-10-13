# Required CI checks and duplicate runs

In this repository, cancelling the pull-request CI for a commit left a failed `CI result` even though the push CI for the same commit succeeded. The protected main branch rejected the fast-forward push with `Required status check "CI result" is failing`.

Allow both required pipelines on the current source to complete. Do not cancel a duplicate PR run merely because the push run passed. When cancelled dependencies caused the result job to fail, rerun the entire affected workflow on the same commit; rerunning only the result job retains the cancelled dependency conclusions. Preserve the task commits and the local fast-forward while resolving checks. Do not reset or bypass branch protection.

Inspect each run's source SHA and all required conclusions before pushing main. A green run for another commit does not resolve a failed current check.
