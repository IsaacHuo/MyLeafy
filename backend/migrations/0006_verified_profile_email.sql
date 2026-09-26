-- Only a verified identity update may publish a notification email. This runs
-- atomically with Better Auth's user update, including the profile email unique constraint.
CREATE TRIGGER identity_verified_profile_email
AFTER UPDATE OF email,emailVerified ON identity_user
WHEN NEW.emailVerified=1 AND (OLD.email<>NEW.email OR OLD.emailVerified<>1)
  AND NEW.email NOT LIKE '%@anonymous.invalid'
BEGIN
  UPDATE profiles SET bound_email=lower(trim(NEW.email)),pending_bound_email=NULL,
    email_verification_sent_at=NULL,updated_at=strftime('%Y-%m-%dT%H:%M:%f','now')||'000Z'
  WHERE id IN(SELECT profile_id FROM profile_auth_links WHERE auth_user_id=NEW.id);
END;
