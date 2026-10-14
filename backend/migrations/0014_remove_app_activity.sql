CREATE TABLE moderation_collection (id INTEGER PRIMARY KEY CHECK(id=1), started_at TEXT NOT NULL);
INSERT INTO moderation_collection SELECT id,started_at FROM activity_collection;
DROP TABLE app_activity;
DROP TABLE activity_collection;
