-- Activity starts here; migrated profile timestamps are not app usage.
CREATE TABLE activity_collection (id INTEGER PRIMARY KEY CHECK(id=1), started_at TEXT NOT NULL);
INSERT INTO activity_collection VALUES(1,strftime('%Y-%m-%dT%H:%M:%f000Z','now'));
CREATE TABLE app_activity (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  campus_id TEXT,
  occurred_at TEXT NOT NULL,
  received_at TEXT NOT NULL,
  platform TEXT NOT NULL CHECK(platform IN ('ios','android')),
  app_version TEXT NOT NULL
);
CREATE INDEX app_activity_time ON app_activity(occurred_at,profile_id);
CREATE INDEX app_activity_profile ON app_activity(profile_id,occurred_at);
CREATE INDEX app_activity_campus ON app_activity(campus_id,occurred_at,profile_id);
