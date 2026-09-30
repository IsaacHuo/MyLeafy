-- Releases have their own write switch; community maintenance does not disable updates.
CREATE TABLE release_control(id INTEGER PRIMARY KEY CHECK(id=1),writable INTEGER NOT NULL CHECK(writable IN (0,1)));
INSERT INTO release_control VALUES(1,1);
CREATE TABLE android_releases(
 id TEXT PRIMARY KEY, package_name TEXT NOT NULL, channel TEXT NOT NULL CHECK(channel='official'),
 version_code INTEGER NOT NULL CHECK(version_code>0),artifact_key TEXT NOT NULL UNIQUE,
 metadata TEXT NOT NULL CHECK(json_valid(metadata)),status TEXT NOT NULL CHECK(status IN ('published','revoked')),
 published_at TEXT NOT NULL,revoked_at TEXT,UNIQUE(package_name,channel,version_code)
);
CREATE INDEX android_release_latest ON android_releases(package_name,channel,status,version_code DESC);
CREATE TABLE release_audit(id TEXT PRIMARY KEY,release_id TEXT NOT NULL,actor TEXT NOT NULL,action TEXT NOT NULL,occurred_at TEXT NOT NULL,details TEXT NOT NULL CHECK(json_valid(details)));
CREATE TRIGGER release_write_guard BEFORE INSERT ON android_releases
WHEN NOT EXISTS(SELECT 1 FROM release_control WHERE id=1 AND writable=1)
BEGIN SELECT RAISE(ABORT,'release_writes_disabled'); END;
