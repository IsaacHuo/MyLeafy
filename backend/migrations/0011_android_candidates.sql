-- Candidates are private until an administrator authorizes this exact artifact.
CREATE TABLE android_release_candidates(
 id TEXT PRIMARY KEY, metadata TEXT NOT NULL CHECK(json_valid(metadata)),
 version_code INTEGER NOT NULL UNIQUE, github_release_id INTEGER NOT NULL UNIQUE,
 github_asset_id INTEGER NOT NULL UNIQUE, preparation_run_id INTEGER NOT NULL,
 created_at TEXT NOT NULL, operation_id TEXT
);
CREATE TABLE android_release_operations(
 id TEXT PRIMARY KEY, candidate_id TEXT NOT NULL REFERENCES android_release_candidates(id),
 approved_by TEXT NOT NULL REFERENCES admin_accounts(id), approved_at TEXT NOT NULL,
 status TEXT NOT NULL CHECK(status IN('pending','running','failed','succeeded')),
 run_id INTEGER, error_code TEXT, updated_at TEXT NOT NULL
);
CREATE UNIQUE INDEX android_one_active_publication ON android_release_operations(candidate_id)
 WHERE status IN('pending','running');
