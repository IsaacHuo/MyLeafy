-- Runtime state is private to Workers. No public SQL execution endpoint exists.
CREATE TABLE backend_control (id INTEGER PRIMARY KEY CHECK(id=1), mode TEXT NOT NULL CHECK(mode IN ('active','read_only','importing')), generation INTEGER NOT NULL DEFAULT 1);
INSERT INTO backend_control(id,mode) VALUES(1,'read_only');
CREATE TABLE mutation_assertions (ok INTEGER NOT NULL CONSTRAINT mutation_precondition CHECK(ok=1));
CREATE TABLE change_outbox (id TEXT PRIMARY KEY, room TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')), delivered_at TEXT);
CREATE INDEX change_outbox_pending ON change_outbox(created_at) WHERE delivered_at IS NULL;
CREATE TABLE file_objects (bucket TEXT NOT NULL, path TEXT NOT NULL, owner_id TEXT REFERENCES profiles(id), post_id TEXT REFERENCES posts(id), sha256 TEXT NOT NULL, byte_size INTEGER NOT NULL CHECK(byte_size>0), content_type TEXT NOT NULL, state TEXT NOT NULL CHECK(state IN ('uploaded','attached','deleting')), created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')), PRIMARY KEY(bucket,path));
CREATE INDEX file_objects_post ON file_objects(post_id);
CREATE TABLE file_delete_jobs (bucket TEXT NOT NULL,path TEXT NOT NULL,attempts INTEGER NOT NULL DEFAULT 0,created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),last_error_code TEXT,PRIMARY KEY(bucket,path));
CREATE TABLE scheduled_runs (id TEXT PRIMARY KEY,job TEXT NOT NULL,started_at TEXT NOT NULL,finished_at TEXT,status TEXT NOT NULL CHECK(status IN ('running','succeeded','failed')),error_code TEXT);
CREATE TABLE legacy_session_exchanges (legacy_user_id TEXT NOT NULL,legacy_session_id TEXT NOT NULL,identity_session_id TEXT NOT NULL REFERENCES identity_session(id) ON DELETE CASCADE,created_at TEXT NOT NULL,PRIMARY KEY(legacy_user_id,legacy_session_id));
CREATE TRIGGER identity_user_anchor_insert AFTER INSERT ON identity_user BEGIN
  INSERT INTO auth_users(id,email,email_verified,is_anonymous,created_at,updated_at)
  VALUES(NEW.id,CASE WHEN NEW.isAnonymous=1 THEN NULL ELSE NEW.email END,NEW.emailVerified,coalesce(NEW.isAnonymous,0),strftime('%Y-%m-%dT%H:%M:%fZ',NEW.createdAt/1000.0,'unixepoch'),strftime('%Y-%m-%dT%H:%M:%fZ',NEW.updatedAt/1000.0,'unixepoch'))
  ON CONFLICT(id) DO NOTHING;
END;
CREATE TRIGGER identity_user_anchor_update AFTER UPDATE ON identity_user BEGIN
  UPDATE auth_users SET email=CASE WHEN NEW.isAnonymous=1 THEN NULL ELSE NEW.email END,email_verified=NEW.emailVerified,is_anonymous=coalesce(NEW.isAnonymous,0),updated_at=strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id=NEW.id;
END;
-- Profile/content deletion is performed by the account-deletion transaction BEFORE removing this anchor.
CREATE TRIGGER identity_user_anchor_delete AFTER DELETE ON identity_user BEGIN DELETE FROM auth_users WHERE id=OLD.id; END;
CREATE TRIGGER profiles_revoke_changed_identity AFTER UPDATE OF profile_id ON profile_auth_links BEGIN
  DELETE FROM identity_session WHERE userId=NEW.auth_user_id;
END;
