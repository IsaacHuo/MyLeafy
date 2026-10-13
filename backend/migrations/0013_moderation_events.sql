CREATE TABLE moderation_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  target_type TEXT NOT NULL CHECK(target_type IN ('posts','comments')),
  target_id TEXT NOT NULL,
  campus_id TEXT,
  occurred_at TEXT NOT NULL
);
CREATE INDEX moderation_events_time ON moderation_events(target_type,occurred_at,campus_id);
CREATE TRIGGER posts_hidden_event AFTER UPDATE OF status ON posts
WHEN NEW.status='hidden' AND OLD.status<>'hidden' AND NEW.moderated_by IS NOT NULL AND NEW.moderated_at IS NOT NULL
BEGIN INSERT INTO moderation_events(target_type,target_id,campus_id,occurred_at) VALUES('posts',NEW.id,NEW.campus_id,NEW.moderated_at); END;
CREATE TRIGGER comments_hidden_event AFTER UPDATE OF status ON comments
WHEN NEW.status='hidden' AND OLD.status<>'hidden' AND NEW.moderated_by IS NOT NULL AND NEW.moderated_at IS NOT NULL
BEGIN INSERT INTO moderation_events(target_type,target_id,campus_id,occurred_at) SELECT 'comments',NEW.id,p.campus_id,NEW.moderated_at FROM posts p WHERE p.id=NEW.post_id; END;
