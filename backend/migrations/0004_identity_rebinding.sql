-- The previous trigger revoked even a no-op bootstrap session and revoked the
-- session performing an intentional identity switch. The authenticated bootstrap
-- transaction now owns rebinding and revokes the other sessions explicitly.
DROP TRIGGER profiles_revoke_changed_identity;

CREATE INDEX identity_session_expiry ON identity_session(expiresAt);
CREATE INDEX profiles_community_scope ON profiles(community_campus_id,community_access_status,id);
CREATE INDEX change_outbox_delivery ON change_outbox(delivered_at,created_at,id);
