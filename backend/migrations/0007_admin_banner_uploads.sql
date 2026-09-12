-- Admin-only, short-lived, single-use receipts for immutable R2 banner uploads.
CREATE TABLE admin_banner_uploads (
  id TEXT PRIMARY KEY,
  path TEXT NOT NULL UNIQUE,
  admin_id TEXT NOT NULL REFERENCES admin_accounts(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL,
  campus_id TEXT NOT NULL REFERENCES campuses(id),
  mime_type TEXT NOT NULL CHECK(mime_type IN ('image/jpeg','image/png')),
  byte_size INTEGER NOT NULL CHECK(byte_size BETWEEN 1 AND 2097152),
  expires_at TEXT NOT NULL,
  consumed_at TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX admin_banner_uploads_expiry ON admin_banner_uploads(expires_at,consumed_at);
