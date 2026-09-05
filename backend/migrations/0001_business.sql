-- Generated from contracts/source-schema.json by npm run schema:convert.

-- Source RLS/functions are ported separately; this DDL does not grant client access.

CREATE TABLE auth_users (id TEXT PRIMARY KEY NOT NULL, email TEXT, email_verified INTEGER NOT NULL DEFAULT 0 CHECK(email_verified IN (0,1)), is_anonymous INTEGER NOT NULL DEFAULT 0 CHECK(is_anonymous IN (0,1)), banned_until TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);

CREATE TABLE "private_community_attachment_upload_receipts" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "auth_user_id" TEXT NOT NULL,
  "profile_id" TEXT NOT NULL,
  "post_id" TEXT NOT NULL,
  "object_path" TEXT NOT NULL,
  "display_name" TEXT NOT NULL,
  "content_type" TEXT NOT NULL,
  "file_extension" TEXT NOT NULL,
  "byte_size" INTEGER NOT NULL,
  "sha256" TEXT NOT NULL,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "expires_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now','+10 minutes')),
  "consumed_at" TEXT,
  CONSTRAINT "community_attachment_upload_receipts_auth_user_id_fkey" FOREIGN KEY (auth_user_id) REFERENCES "auth_users"(id) ON DELETE CASCADE,
  CONSTRAINT "community_attachment_upload_receipts_byte_size_check" CHECK (((byte_size >= 1) AND (byte_size <= 10485760))),
  CONSTRAINT "community_attachment_upload_receipts_object_path_key" UNIQUE (object_path),
  CONSTRAINT "community_attachment_upload_receipts_pkey" PRIMARY KEY (id),
  CONSTRAINT "community_attachment_upload_receipts_post_id_fkey" FOREIGN KEY (post_id) REFERENCES "posts"(id) ON DELETE CASCADE,
  CONSTRAINT "community_attachment_upload_receipts_profile_id_fkey" FOREIGN KEY (profile_id) REFERENCES "profiles"(id) ON DELETE CASCADE
);

CREATE TABLE "private_community_comment_like_requests" (
  "request_id" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "comment_id" TEXT NOT NULL,
  "like_count" INTEGER NOT NULL,
  "viewer_has_liked" INTEGER NOT NULL CHECK ("viewer_has_liked" IN (0,1)),
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CONSTRAINT "community_comment_like_requests_comment_id_fkey" FOREIGN KEY (comment_id) REFERENCES "comments"(id) ON DELETE CASCADE,
  CONSTRAINT "community_comment_like_requests_like_count_check" CHECK ((like_count >= 0)),
  CONSTRAINT "community_comment_like_requests_pkey" PRIMARY KEY (request_id, user_id),
  CONSTRAINT "community_comment_like_requests_user_id_fkey" FOREIGN KEY (user_id) REFERENCES "profiles"(id) ON DELETE CASCADE
);

CREATE TABLE "private_community_create_requests" (
  "actor_id" TEXT NOT NULL,
  "request_id" TEXT NOT NULL,
  "mutation_kind" TEXT NOT NULL,
  "resource_id" TEXT NOT NULL,
  "request_payload" TEXT NOT NULL CHECK ("request_payload" IS NULL OR json_valid("request_payload")),
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CONSTRAINT "community_create_requests_actor_id_fkey" FOREIGN KEY (actor_id) REFERENCES "profiles"(id) ON DELETE CASCADE,
  CONSTRAINT "community_create_requests_mutation_kind_check" CHECK ((mutation_kind IN ('post', 'comment'))),
  CONSTRAINT "community_create_requests_pkey" PRIMARY KEY (actor_id, request_id)
);

CREATE TABLE "private_community_identity_link_conflicts" (
  "auth_user_id" TEXT NOT NULL,
  "profile_id" TEXT NOT NULL,
  "campus_id" TEXT NOT NULL,
  "edu_id" TEXT NOT NULL,
  "created_at" TEXT NOT NULL,
  "last_seen_at" TEXT NOT NULL,
  "retained_auth_user_id" TEXT NOT NULL,
  "resolution_reason" TEXT NOT NULL,
  "archived_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CONSTRAINT "community_identity_link_conflicts_pkey" PRIMARY KEY (auth_user_id, profile_id, archived_at)
);

CREATE TABLE "private_community_upload_receipts" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "auth_user_id" TEXT NOT NULL,
  "profile_id" TEXT NOT NULL,
  "post_id" TEXT NOT NULL,
  "full_path" TEXT NOT NULL,
  "thumbnail_path" TEXT NOT NULL,
  "full_sha256" TEXT NOT NULL,
  "thumbnail_sha256" TEXT NOT NULL,
  "full_size" INTEGER NOT NULL,
  "thumbnail_size" INTEGER NOT NULL,
  "full_width" INTEGER NOT NULL,
  "full_height" INTEGER NOT NULL,
  "thumbnail_width" INTEGER NOT NULL,
  "thumbnail_height" INTEGER NOT NULL,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "expires_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now','+10 minutes')),
  "consumed_at" TEXT,
  CONSTRAINT "community_upload_receipts_auth_user_id_fkey" FOREIGN KEY (auth_user_id) REFERENCES "auth_users"(id) ON DELETE CASCADE,
  CONSTRAINT "community_upload_receipts_full_height_check" CHECK (((full_height >= 1) AND (full_height <= 1600))),
  CONSTRAINT "community_upload_receipts_full_path_key" UNIQUE (full_path),
  CONSTRAINT "community_upload_receipts_full_size_check" CHECK (((full_size >= 1) AND (full_size <= 1048576))),
  CONSTRAINT "community_upload_receipts_full_width_check" CHECK (((full_width >= 1) AND (full_width <= 1600))),
  CONSTRAINT "community_upload_receipts_pkey" PRIMARY KEY (id),
  CONSTRAINT "community_upload_receipts_post_id_fkey" FOREIGN KEY (post_id) REFERENCES "posts"(id) ON DELETE CASCADE,
  CONSTRAINT "community_upload_receipts_profile_id_fkey" FOREIGN KEY (profile_id) REFERENCES "profiles"(id) ON DELETE CASCADE,
  CONSTRAINT "community_upload_receipts_thumbnail_height_check" CHECK (((thumbnail_height >= 1) AND (thumbnail_height <= 480))),
  CONSTRAINT "community_upload_receipts_thumbnail_path_key" UNIQUE (thumbnail_path),
  CONSTRAINT "community_upload_receipts_thumbnail_size_check" CHECK (((thumbnail_size >= 1) AND (thumbnail_size <= 1048576))),
  CONSTRAINT "community_upload_receipts_thumbnail_width_check" CHECK (((thumbnail_width >= 1) AND (thumbnail_width <= 480)))
);

CREATE TABLE "admin_accounts" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "username" TEXT NOT NULL,
  "password_hash" TEXT NOT NULL,
  "display_name" TEXT NOT NULL,
  "role" TEXT NOT NULL DEFAULT ('super_admin'),
  "active" INTEGER NOT NULL DEFAULT (1) CHECK ("active" IN (0,1)),
  "last_login_at" TEXT,
  "created_by" TEXT,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CONSTRAINT "admin_accounts_created_by_fkey" FOREIGN KEY (created_by) REFERENCES "admin_accounts"(id) ON DELETE SET NULL,
  CONSTRAINT "admin_accounts_display_name_not_blank" CHECK ((NULLIF(trim(display_name), '') IS NOT NULL)),
  CONSTRAINT "admin_accounts_pkey" PRIMARY KEY (id),
  CONSTRAINT "admin_accounts_role_check" CHECK ((role IN ('super_admin', 'operator', 'viewer'))),
  CONSTRAINT "admin_accounts_username_format" CHECK(length(username) BETWEEN 3 AND 64 AND username NOT GLOB '*[^a-z0-9_.-]*'),
  CONSTRAINT "admin_accounts_username_key" UNIQUE (username)
);

CREATE TABLE "admin_audit_logs" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "admin_id" TEXT,
  "action" TEXT NOT NULL,
  "target_type" TEXT,
  "target_id" TEXT,
  "params" TEXT NOT NULL DEFAULT ('{}') CHECK ("params" IS NULL OR json_valid("params")),
  "ip_address" TEXT,
  "user_agent" TEXT,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "request_id" TEXT,
  "outcome" TEXT,
  "duration_ms" INTEGER,
  "error_code" TEXT,
  CONSTRAINT "admin_audit_logs_action_not_blank" CHECK ((NULLIF(trim(action), '') IS NOT NULL)),
  CONSTRAINT "admin_audit_logs_admin_id_fkey" FOREIGN KEY (admin_id) REFERENCES "admin_accounts"(id) ON DELETE SET NULL,
  CONSTRAINT "admin_audit_logs_duration_ms_nonnegative" CHECK (((duration_ms IS NULL) OR (duration_ms >= 0))),
  CONSTRAINT "admin_audit_logs_error_code_not_blank" CHECK (((error_code IS NULL) OR (NULLIF(trim(error_code), '') IS NOT NULL))),
  CONSTRAINT "admin_audit_logs_outcome_check" CHECK (((outcome IS NULL) OR (outcome IN ('success', 'failure'))))
);

CREATE TABLE "admin_login_attempts" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "username" TEXT NOT NULL,
  "normalized_username" TEXT GENERATED ALWAYS AS (lower(trim(username))) STORED,
  "ip_address" TEXT NOT NULL,
  "succeeded" INTEGER NOT NULL DEFAULT (0) CHECK ("succeeded" IN (0,1)),
  "error_code" TEXT,
  "attempted_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CONSTRAINT "admin_login_attempts_error_code_not_blank" CHECK (((error_code IS NULL) OR (NULLIF(trim(error_code), '') IS NOT NULL))),
  CONSTRAINT "admin_login_attempts_pkey" PRIMARY KEY (id),
  CONSTRAINT "admin_login_attempts_username_not_blank" CHECK ((NULLIF(trim(username), '') IS NOT NULL))
);

CREATE TABLE "admin_sessions" (
  "token_hash" TEXT NOT NULL,
  "admin_id" TEXT NOT NULL,
  "expires_at" TEXT NOT NULL,
  "revoked_at" TEXT,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "last_seen_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CONSTRAINT "admin_sessions_admin_id_fkey" FOREIGN KEY (admin_id) REFERENCES "admin_accounts"(id) ON DELETE CASCADE,
  CONSTRAINT "admin_sessions_expiry_future" CHECK ((expires_at > created_at)),
  CONSTRAINT "admin_sessions_pkey" PRIMARY KEY (token_hash),
  CONSTRAINT "admin_sessions_token_hash_length" CHECK ((length(token_hash) = 64))
);

CREATE TABLE "admin_users" (
  "user_id" TEXT NOT NULL,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CONSTRAINT "admin_users_pkey" PRIMARY KEY (user_id),
  CONSTRAINT "admin_users_user_id_fkey" FOREIGN KEY (user_id) REFERENCES "auth_users"(id) ON DELETE CASCADE
);

CREATE TABLE "campus_membership_requests" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "requester_profile_id" TEXT NOT NULL,
  "requester_auth_user_id" TEXT,
  "school_name" TEXT NOT NULL,
  "normalized_school_name" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT ('pending'),
  "approved_campus_id" TEXT,
  "admin_note" TEXT,
  "reviewed_by" TEXT,
  "reviewed_at" TEXT,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "request_type" TEXT NOT NULL DEFAULT ('initial_new_school'),
  "requested_campus_id" TEXT,
  "from_campus_id" TEXT,
  CONSTRAINT "campus_membership_requests_approved_campus_id_fkey" FOREIGN KEY (approved_campus_id) REFERENCES "campuses"(id) ON UPDATE CASCADE,
  CONSTRAINT "campus_membership_requests_from_campus_id_fkey" FOREIGN KEY (from_campus_id) REFERENCES "campuses"(id) ON UPDATE CASCADE,
  CONSTRAINT "campus_membership_requests_pkey" PRIMARY KEY (id),
  CONSTRAINT "campus_membership_requests_profile_status_shape" CHECK ((((status = 'approved') AND (approved_campus_id IS NOT NULL)) OR ((status <> 'approved') AND (approved_campus_id IS NULL)))),
  CONSTRAINT "campus_membership_requests_request_shape" CHECK ((((request_type = 'initial_new_school') AND (requested_campus_id IS NULL) AND (from_campus_id IS NULL)) OR ((request_type = 'school_change') AND (requested_campus_id IS NOT NULL) AND (from_campus_id IS NOT NULL)))),
  CONSTRAINT "campus_membership_requests_request_type_check" CHECK ((request_type IN ('initial_new_school', 'school_change'))),
  CONSTRAINT "campus_membership_requests_requested_campus_id_fkey" FOREIGN KEY (requested_campus_id) REFERENCES "campuses"(id) ON UPDATE CASCADE,
  CONSTRAINT "campus_membership_requests_requester_auth_user_id_fkey" FOREIGN KEY (requester_auth_user_id) REFERENCES "auth_users"(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT "campus_membership_requests_requester_profile_id_fkey" FOREIGN KEY (requester_profile_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "campus_membership_requests_school_name_not_blank" CHECK ((NULLIF(trim(school_name), '') IS NOT NULL)),
  CONSTRAINT "campus_membership_requests_status_check" CHECK ((status IN ('pending', 'approved', 'rejected')))
);

CREATE TABLE "campus_weather_cache" (
  "cache_key" TEXT NOT NULL,
  "temperature" REAL NOT NULL,
  "condition_key" TEXT NOT NULL,
  "observed_at" TEXT NOT NULL,
  "source" TEXT NOT NULL,
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "campus_id" TEXT NOT NULL DEFAULT ('bjfu'),
  CONSTRAINT "campus_weather_cache_campus_id_fkey" FOREIGN KEY (campus_id) REFERENCES "campuses"(id) ON UPDATE CASCADE,
  CONSTRAINT "campus_weather_cache_pkey" PRIMARY KEY (cache_key)
);

CREATE TABLE "campuses" (
  "id" TEXT NOT NULL,
  "display_name" TEXT NOT NULL,
  "short_name" TEXT NOT NULL,
  "connector_kind" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT ('active'),
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "normalized_name" TEXT NOT NULL,
  "is_community_enabled" INTEGER NOT NULL DEFAULT (1) CHECK ("is_community_enabled" IN (0,1)),
  "is_system" INTEGER NOT NULL DEFAULT (0) CHECK ("is_system" IN (0,1)),
  CONSTRAINT "campuses_id_not_blank" CHECK ((NULLIF(trim(id), '') IS NOT NULL)),
  CONSTRAINT "campuses_pkey" PRIMARY KEY (id),
  CONSTRAINT "campuses_status_check" CHECK ((status IN ('active', 'disabled')))
);

CREATE TABLE "catalog_suggestions" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "suggestion_type" TEXT NOT NULL,
  "user_id" TEXT,
  "name" TEXT NOT NULL,
  "unit" TEXT NOT NULL,
  "category" TEXT,
  "credit" REAL,
  "note" TEXT,
  "status" TEXT NOT NULL DEFAULT ('open'),
  "approved_teacher_id" INTEGER,
  "approved_course_id" INTEGER,
  "admin_note" TEXT,
  "reviewed_by" TEXT,
  "reviewed_at" TEXT,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "teacher_name" TEXT,
  "search_text" TEXT GENERATED ALWAYS AS (lower(((((((((COALESCE(name, '') || ' ') || COALESCE(unit, '')) || ' ') || COALESCE(teacher_name, '')) || ' ') || COALESCE(category, '')) || ' ') || COALESCE(note, '')))) STORED,
  "campus_id" TEXT NOT NULL,
  "initial_stars" INTEGER,
  "approved_dish_id" INTEGER,
  CONSTRAINT "catalog_suggestions_approved_course_id_fkey" FOREIGN KEY (approved_course_id) REFERENCES "course_catalog"(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT "catalog_suggestions_approved_dish_id_fkey" FOREIGN KEY (approved_dish_id) REFERENCES "dish_catalog"(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT "catalog_suggestions_approved_teacher_id_fkey" FOREIGN KEY (approved_teacher_id) REFERENCES "teachers"(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT "catalog_suggestions_campus_id_fkey" FOREIGN KEY (campus_id) REFERENCES "campuses"(id) ON UPDATE CASCADE,
  CONSTRAINT "catalog_suggestions_category_not_blank" CHECK (((category IS NULL) OR (NULLIF(trim(category), '') IS NOT NULL))),
  CONSTRAINT "catalog_suggestions_credit_valid" CHECK (((credit IS NULL) OR (credit >= (0)))),
  CONSTRAINT "catalog_suggestions_initial_stars_check" CHECK (((initial_stars IS NULL) OR ((initial_stars >= 1) AND (initial_stars <= 5)))),
  CONSTRAINT "catalog_suggestions_name_not_blank" CHECK ((NULLIF(trim(name), '') IS NOT NULL)),
  CONSTRAINT "catalog_suggestions_pkey" PRIMARY KEY (id),
  CONSTRAINT "catalog_suggestions_reviewed_by_fkey" FOREIGN KEY (reviewed_by) REFERENCES "admin_accounts"(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT "catalog_suggestions_status_check" CHECK ((status IN ('open', 'approved', 'rejected'))),
  CONSTRAINT "catalog_suggestions_type_check" CHECK ((suggestion_type IN ('teacher', 'course', 'dish'))),
  CONSTRAINT "catalog_suggestions_unit_not_blank" CHECK ((NULLIF(trim(unit), '') IS NOT NULL)),
  CONSTRAINT "catalog_suggestions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE SET NULL
);

CREATE TABLE "comment_likes" (
  "comment_id" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CONSTRAINT "comment_likes_comment_id_fkey" FOREIGN KEY (comment_id) REFERENCES "comments"(id) ON DELETE CASCADE,
  CONSTRAINT "comment_likes_pkey" PRIMARY KEY (comment_id, user_id),
  CONSTRAINT "comment_likes_user_id_fkey" FOREIGN KEY (user_id) REFERENCES "profiles"(id) ON DELETE CASCADE
);

CREATE TABLE "comments" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "post_id" TEXT NOT NULL,
  "author_id" TEXT NOT NULL,
  "body" TEXT NOT NULL,
  "is_anonymous" INTEGER NOT NULL DEFAULT (0) CHECK ("is_anonymous" IN (0,1)),
  "status" TEXT NOT NULL DEFAULT ('published'),
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "moderated_by" TEXT,
  "moderated_at" TEXT,
  "moderation_reason" TEXT,
  "parent_comment_id" TEXT,
  "reply_to_comment_id" TEXT,
  "like_count" INTEGER NOT NULL DEFAULT (0),
  CONSTRAINT "comments_author_id_fkey" FOREIGN KEY (author_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "comments_like_count_nonnegative" CHECK ((like_count >= 0)),
  CONSTRAINT "comments_moderated_by_fkey" FOREIGN KEY (moderated_by) REFERENCES "admin_accounts"(id) ON DELETE SET NULL,
  CONSTRAINT "comments_parent_comment_id_fkey" FOREIGN KEY (parent_comment_id) REFERENCES "comments"(id) ON DELETE RESTRICT,
  CONSTRAINT "comments_pkey" PRIMARY KEY (id),
  CONSTRAINT "comments_post_id_fkey" FOREIGN KEY (post_id) REFERENCES "posts"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "comments_reply_to_comment_id_fkey" FOREIGN KEY (reply_to_comment_id) REFERENCES "comments"(id) ON DELETE SET NULL,
  CONSTRAINT "comments_status_check" CHECK ((status IN ('published', 'deleted', 'hidden', 'pending_review')))
);

CREATE TABLE "community_banners" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "campus_id" TEXT NOT NULL,
  "revision" INTEGER NOT NULL DEFAULT (1),
  "title" TEXT NOT NULL,
  "subtitle" TEXT NOT NULL,
  "image_path" TEXT,
  "destination_kind" TEXT NOT NULL DEFAULT ('none'),
  "destination_value" TEXT,
  "status" TEXT NOT NULL DEFAULT ('draft'),
  "published_at" TEXT,
  "expires_at" TEXT,
  "created_by" TEXT,
  "updated_by" TEXT,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CONSTRAINT "community_banners_campus_id_fkey" FOREIGN KEY (campus_id) REFERENCES "campuses"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "community_banners_created_by_fkey" FOREIGN KEY (created_by) REFERENCES "admin_accounts"(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT "community_banners_destination_kind_check" CHECK ((destination_kind IN ('none', 'community_post', 'app_route', 'https_url'))),
  CONSTRAINT "community_banners_destination_value" CHECK ((((destination_kind = 'none') AND (destination_value IS NULL)) OR ((destination_kind <> 'none') AND (NULLIF(trim(destination_value), '') IS NOT NULL)))),
  CONSTRAINT "community_banners_expiry_after_publish" CHECK (((expires_at IS NULL) OR (published_at IS NULL) OR (expires_at > published_at))),
  CONSTRAINT "community_banners_pkey" PRIMARY KEY (id),
  CONSTRAINT "community_banners_published_at_required" CHECK (((status <> 'published') OR (published_at IS NOT NULL))),
  CONSTRAINT "community_banners_revision_check" CHECK ((revision > 0)),
  CONSTRAINT "community_banners_status_check" CHECK ((status IN ('draft', 'published', 'archived'))),
  CONSTRAINT "community_banners_subtitle_check" CHECK (((length(trim(subtitle)) >= 1) AND (length(trim(subtitle)) <= 180))),
  CONSTRAINT "community_banners_title_check" CHECK (((length(trim(title)) >= 1) AND (length(trim(title)) <= 60))),
  CONSTRAINT "community_banners_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES "admin_accounts"(id) ON UPDATE CASCADE ON DELETE SET NULL
);

CREATE TABLE "community_blocks" (
  "blocker_id" TEXT NOT NULL,
  "blocked_id" TEXT NOT NULL,
  "reason" TEXT,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CONSTRAINT "community_blocks_blocked_id_fkey" FOREIGN KEY (blocked_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "community_blocks_blocker_id_fkey" FOREIGN KEY (blocker_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "community_blocks_no_self_block" CHECK ((blocker_id <> blocked_id)),
  CONSTRAINT "community_blocks_pkey" PRIMARY KEY (blocker_id, blocked_id)
);

CREATE TABLE "community_notification_settings" (
  "user_id" TEXT NOT NULL,
  "muted_all" INTEGER NOT NULL DEFAULT (0) CHECK ("muted_all" IN (0,1)),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CONSTRAINT "community_notification_settings_pkey" PRIMARY KEY (user_id),
  CONSTRAINT "community_notification_settings_user_id_fkey" FOREIGN KEY (user_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE "community_notifications" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "recipient_id" TEXT NOT NULL,
  "actor_id" TEXT,
  "post_id" TEXT,
  "comment_id" TEXT,
  "type" TEXT NOT NULL,
  "title" TEXT NOT NULL,
  "body" TEXT,
  "is_read" INTEGER NOT NULL DEFAULT (0) CHECK ("is_read" IN (0,1)),
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "dismissed_at" TEXT,
  CONSTRAINT "community_notifications_actor_id_fkey" FOREIGN KEY (actor_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT "community_notifications_comment_id_fkey" FOREIGN KEY (comment_id) REFERENCES "comments"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "community_notifications_pkey" PRIMARY KEY (id),
  CONSTRAINT "community_notifications_post_id_fkey" FOREIGN KEY (post_id) REFERENCES "posts"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "community_notifications_recipient_id_fkey" FOREIGN KEY (recipient_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "community_notifications_type_check" CHECK ((type IN ('comment', 'like')))
);

CREATE TABLE "community_poll_options" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "poll_id" TEXT NOT NULL,
  "text" TEXT NOT NULL,
  "sort_order" INTEGER NOT NULL DEFAULT (0),
  "vote_count" INTEGER NOT NULL DEFAULT (0),
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CONSTRAINT "community_poll_options_pkey" PRIMARY KEY (id),
  CONSTRAINT "community_poll_options_poll_id_fkey" FOREIGN KEY (poll_id) REFERENCES "community_polls"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "community_poll_options_poll_id_sort_order_key" UNIQUE (poll_id, sort_order),
  CONSTRAINT "community_poll_options_sort_order_nonnegative" CHECK ((sort_order >= 0)),
  CONSTRAINT "community_poll_options_text_length" CHECK ((length(text) <= 80)),
  CONSTRAINT "community_poll_options_text_not_blank" CHECK ((NULLIF(trim(text), '') IS NOT NULL)),
  CONSTRAINT "community_poll_options_vote_count_check" CHECK ((vote_count >= 0))
);

CREATE TABLE "community_poll_votes" (
  "poll_id" TEXT NOT NULL,
  "option_id" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CONSTRAINT "community_poll_votes_option_id_fkey" FOREIGN KEY (option_id) REFERENCES "community_poll_options"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "community_poll_votes_pkey" PRIMARY KEY (poll_id, user_id),
  CONSTRAINT "community_poll_votes_poll_id_fkey" FOREIGN KEY (poll_id) REFERENCES "community_polls"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "community_poll_votes_user_id_fkey" FOREIGN KEY (user_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE "community_polls" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "author_id" TEXT NOT NULL,
  "question" TEXT NOT NULL,
  "detail" TEXT,
  "status" TEXT NOT NULL DEFAULT ('pending_review'),
  "total_vote_count" INTEGER NOT NULL DEFAULT (0),
  "closes_at" TEXT,
  "moderated_by" TEXT,
  "moderated_at" TEXT,
  "moderation_reason" TEXT,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "deletion_status" TEXT NOT NULL DEFAULT ('none'),
  "deletion_requested_at" TEXT,
  "deletion_reason" TEXT,
  "deletion_reviewed_at" TEXT,
  "deletion_reviewed_by" TEXT,
  "deletion_review_reason" TEXT,
  "campus_id" TEXT NOT NULL,
  CONSTRAINT "community_polls_author_id_fkey" FOREIGN KEY (author_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "community_polls_campus_id_fkey" FOREIGN KEY (campus_id) REFERENCES "campuses"(id) ON UPDATE CASCADE,
  CONSTRAINT "community_polls_deletion_reason_length" CHECK (((deletion_reason IS NULL) OR (length(deletion_reason) <= 300))),
  CONSTRAINT "community_polls_deletion_review_reason_length" CHECK (((deletion_review_reason IS NULL) OR (length(deletion_review_reason) <= 300))),
  CONSTRAINT "community_polls_deletion_reviewed_by_fkey" FOREIGN KEY (deletion_reviewed_by) REFERENCES "admin_accounts"(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT "community_polls_deletion_status_check" CHECK ((deletion_status IN ('none', 'pending', 'approved', 'rejected'))),
  CONSTRAINT "community_polls_detail_length" CHECK (((detail IS NULL) OR (length(detail) <= 500))),
  CONSTRAINT "community_polls_moderated_by_fkey" FOREIGN KEY (moderated_by) REFERENCES "admin_accounts"(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT "community_polls_pkey" PRIMARY KEY (id),
  CONSTRAINT "community_polls_question_length" CHECK ((length(question) <= 120)),
  CONSTRAINT "community_polls_question_not_blank" CHECK ((NULLIF(trim(question), '') IS NOT NULL)),
  CONSTRAINT "community_polls_status_check" CHECK ((status IN ('pending_review', 'published', 'hidden', 'deleted'))),
  CONSTRAINT "community_polls_total_vote_count_check" CHECK ((total_vote_count >= 0))
);

CREATE TABLE "community_post_pins" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "post_id" TEXT NOT NULL,
  "scope" TEXT NOT NULL,
  "category" TEXT,
  "priority" INTEGER NOT NULL DEFAULT (0),
  "starts_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "ends_at" TEXT,
  "status" TEXT NOT NULL DEFAULT ('active'),
  "reason" TEXT,
  "created_by" TEXT,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "campus_id" TEXT NOT NULL,
  CONSTRAINT "community_post_pins_campus_id_fkey" FOREIGN KEY (campus_id) REFERENCES "campuses"(id) ON UPDATE CASCADE,
  CONSTRAINT "community_post_pins_created_by_fkey" FOREIGN KEY (created_by) REFERENCES "admin_accounts"(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT "community_post_pins_pkey" PRIMARY KEY (id),
  CONSTRAINT "community_post_pins_post_id_fkey" FOREIGN KEY (post_id) REFERENCES "posts"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "community_post_pins_scope_category_shape" CHECK ((((scope = 'global') AND (category IS NULL)) OR ((scope = 'category') AND (NULLIF(trim(category), '') IS NOT NULL)))),
  CONSTRAINT "community_post_pins_scope_check" CHECK ((scope IN ('global', 'category'))),
  CONSTRAINT "community_post_pins_status_check" CHECK ((status IN ('active', 'inactive'))),
  CONSTRAINT "community_post_pins_time_range" CHECK (((ends_at IS NULL) OR (ends_at > starts_at)))
);

CREATE TABLE "community_reports" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "reporter_id" TEXT NOT NULL,
  "reported_user_id" TEXT,
  "target_type" TEXT NOT NULL,
  "post_id" TEXT,
  "comment_id" TEXT,
  "reason" TEXT NOT NULL,
  "detail" TEXT,
  "status" TEXT NOT NULL DEFAULT ('open'),
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "resolved_at" TEXT,
  "resolved_by" TEXT,
  "resolution_note" TEXT,
  CONSTRAINT "community_reports_comment_id_fkey" FOREIGN KEY (comment_id) REFERENCES "comments"(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT "community_reports_pkey" PRIMARY KEY (id),
  CONSTRAINT "community_reports_post_id_fkey" FOREIGN KEY (post_id) REFERENCES "posts"(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT "community_reports_reason_check" CHECK (((length(trim(reason)) >= 1) AND (length(trim(reason)) <= 80))),
  CONSTRAINT "community_reports_reported_user_id_fkey" FOREIGN KEY (reported_user_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT "community_reports_reporter_id_fkey" FOREIGN KEY (reporter_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "community_reports_resolved_by_fkey" FOREIGN KEY (resolved_by) REFERENCES "admin_accounts"(id) ON DELETE SET NULL,
  CONSTRAINT "community_reports_status_check" CHECK ((status IN ('open', 'reviewed', 'resolved', 'rejected'))),
  CONSTRAINT "community_reports_target_shape" CHECK ((((target_type = 'post') AND (post_id IS NOT NULL) AND (comment_id IS NULL)) OR ((target_type = 'comment') AND (comment_id IS NOT NULL)) OR ((target_type = 'user') AND (reported_user_id IS NOT NULL) AND (post_id IS NULL) AND (comment_id IS NULL)))),
  CONSTRAINT "community_reports_target_type_check" CHECK ((target_type IN ('post', 'comment', 'user')))
);

CREATE TABLE "community_terms_acceptances" (
  "user_id" TEXT NOT NULL,
  "terms_version" TEXT NOT NULL,
  "accepted_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CONSTRAINT "community_terms_acceptances_pkey" PRIMARY KEY (user_id, terms_version),
  CONSTRAINT "community_terms_acceptances_user_id_fkey" FOREIGN KEY (user_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "community_terms_acceptances_version_not_blank" CHECK ((NULLIF(trim(terms_version), '') IS NOT NULL))
);

CREATE TABLE "course_catalog" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "name" TEXT NOT NULL,
  "unit" TEXT NOT NULL,
  "category" TEXT NOT NULL DEFAULT ('公选课'),
  "credit" REAL NOT NULL DEFAULT (0),
  "status" TEXT NOT NULL DEFAULT ('published'),
  "search_text" TEXT GENERATED ALWAYS AS (lower(((((COALESCE(name, '') || ' ') || COALESCE(unit, '')) || ' ') || COALESCE(category, '')))) STORED,
  "rating_average" REAL NOT NULL DEFAULT (0),
  "rating_count" INTEGER NOT NULL DEFAULT (0),
  "rating_1_count" INTEGER NOT NULL DEFAULT (0),
  "rating_2_count" INTEGER NOT NULL DEFAULT (0),
  "rating_3_count" INTEGER NOT NULL DEFAULT (0),
  "rating_4_count" INTEGER NOT NULL DEFAULT (0),
  "rating_5_count" INTEGER NOT NULL DEFAULT (0),
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "campus_id" TEXT NOT NULL DEFAULT ('bjfu'),
  CONSTRAINT "course_catalog_campus_id_fkey" FOREIGN KEY (campus_id) REFERENCES "campuses"(id) ON UPDATE CASCADE,
  CONSTRAINT "course_catalog_category_not_blank" CHECK ((NULLIF(trim(category), '') IS NOT NULL)),
  CONSTRAINT "course_catalog_credit_valid" CHECK ((credit >= (0))),
  CONSTRAINT "course_catalog_name_not_blank" CHECK ((NULLIF(trim(name), '') IS NOT NULL)),
  CONSTRAINT "course_catalog_status_check" CHECK ((status IN ('published', 'hidden'))),
  CONSTRAINT "course_catalog_unit_not_blank" CHECK ((NULLIF(trim(unit), '') IS NOT NULL))
);

CREATE TABLE "course_ratings" (
  "course_id" INTEGER NOT NULL,
  "user_id" TEXT NOT NULL,
  "stars" INTEGER NOT NULL,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CONSTRAINT "course_ratings_course_id_fkey" FOREIGN KEY (course_id) REFERENCES "course_catalog"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "course_ratings_pkey" PRIMARY KEY (course_id, user_id),
  CONSTRAINT "course_ratings_stars_check" CHECK (((stars >= 1) AND (stars <= 5))),
  CONSTRAINT "course_ratings_user_id_fkey" FOREIGN KEY (user_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE "dish_catalog" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "campus_id" TEXT NOT NULL DEFAULT ('bjfu'),
  "name" TEXT NOT NULL,
  "location" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT ('published'),
  "search_text" TEXT GENERATED ALWAYS AS (lower(((COALESCE(name, '') || ' ') || COALESCE(location, '')))) STORED,
  "rating_average" REAL NOT NULL DEFAULT (0),
  "rating_count" INTEGER NOT NULL DEFAULT (0),
  "rating_1_count" INTEGER NOT NULL DEFAULT (0),
  "rating_2_count" INTEGER NOT NULL DEFAULT (0),
  "rating_3_count" INTEGER NOT NULL DEFAULT (0),
  "rating_4_count" INTEGER NOT NULL DEFAULT (0),
  "rating_5_count" INTEGER NOT NULL DEFAULT (0),
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CONSTRAINT "dish_catalog_campus_id_fkey" FOREIGN KEY (campus_id) REFERENCES "campuses"(id) ON UPDATE CASCADE,
  CONSTRAINT "dish_catalog_location_not_blank" CHECK ((NULLIF(trim(location), '') IS NOT NULL)),
  CONSTRAINT "dish_catalog_name_not_blank" CHECK ((NULLIF(trim(name), '') IS NOT NULL)),
  CONSTRAINT "dish_catalog_status_check" CHECK ((status IN ('published', 'hidden')))
);

CREATE TABLE "dish_ratings" (
  "dish_id" INTEGER NOT NULL,
  "user_id" TEXT NOT NULL,
  "stars" INTEGER NOT NULL,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CONSTRAINT "dish_ratings_dish_id_fkey" FOREIGN KEY (dish_id) REFERENCES "dish_catalog"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "dish_ratings_pkey" PRIMARY KEY (dish_id, user_id),
  CONSTRAINT "dish_ratings_stars_check" CHECK (((stars >= 1) AND (stars <= 5))),
  CONSTRAINT "dish_ratings_user_id_fkey" FOREIGN KEY (user_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE "feedback_submissions" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "user_id" TEXT,
  "issue_type" TEXT NOT NULL,
  "body" TEXT NOT NULL,
  "contact" TEXT,
  "device_info" TEXT NOT NULL DEFAULT ('{}') CHECK ("device_info" IS NULL OR json_valid("device_info")),
  "status" TEXT NOT NULL DEFAULT ('open'),
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "admin_note" TEXT,
  "reviewed_by" TEXT,
  "reviewed_at" TEXT,
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "campus_id" TEXT NOT NULL,
  CONSTRAINT "feedback_submissions_body_check" CHECK (((length(trim(body)) >= 1) AND (length(trim(body)) <= 4000))),
  CONSTRAINT "feedback_submissions_campus_id_fkey" FOREIGN KEY (campus_id) REFERENCES "campuses"(id) ON UPDATE CASCADE,
  CONSTRAINT "feedback_submissions_issue_type_check" CHECK (((length(trim(issue_type)) >= 1) AND (length(trim(issue_type)) <= 40))),
  CONSTRAINT "feedback_submissions_pkey" PRIMARY KEY (id),
  CONSTRAINT "feedback_submissions_reviewed_by_fkey" FOREIGN KEY (reviewed_by) REFERENCES "admin_accounts"(id) ON DELETE SET NULL,
  CONSTRAINT "feedback_submissions_status_check" CHECK ((status IN ('open', 'reviewed', 'closed'))),
  CONSTRAINT "feedback_submissions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE SET NULL
);

CREATE TABLE "national_calendar_runtime_configs" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "year" INTEGER NOT NULL,
  "holidays" TEXT NOT NULL DEFAULT ('[]') CHECK ("holidays" IS NULL OR json_valid("holidays")),
  "solar_terms" TEXT NOT NULL DEFAULT ('[]') CHECK ("solar_terms" IS NULL OR json_valid("solar_terms")),
  "is_active" INTEGER NOT NULL DEFAULT (0) CHECK ("is_active" IN (0,1)),
  "created_by" TEXT,
  "updated_by" TEXT,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CONSTRAINT "national_calendar_runtime_configs_created_by_fkey" FOREIGN KEY (created_by) REFERENCES "admin_accounts"(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT "national_calendar_runtime_configs_holidays_array" CHECK ((json_type(holidays) = 'array')),
  CONSTRAINT "national_calendar_runtime_configs_pkey" PRIMARY KEY (id),
  CONSTRAINT "national_calendar_runtime_configs_solar_terms_array" CHECK ((json_type(solar_terms) = 'array')),
  CONSTRAINT "national_calendar_runtime_configs_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES "admin_accounts"(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT "national_calendar_runtime_configs_year_unique" UNIQUE (year),
  CONSTRAINT "national_calendar_runtime_configs_year_valid" CHECK (((year >= 2000) AND (year <= 2100)))
);

CREATE TABLE "post_attachments" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "post_id" TEXT NOT NULL,
  "path" TEXT NOT NULL,
  "display_name" TEXT NOT NULL,
  "content_type" TEXT NOT NULL,
  "file_extension" TEXT NOT NULL,
  "byte_size" INTEGER NOT NULL,
  "sha256" TEXT NOT NULL,
  "sort_order" INTEGER NOT NULL,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CONSTRAINT "post_attachments_byte_size_check" CHECK (((byte_size >= 1) AND (byte_size <= 10485760))),
  CONSTRAINT "post_attachments_display_name_check" CHECK (((length(display_name) >= 1) AND (length(display_name) <= 180))),
  CONSTRAINT "post_attachments_file_extension_check" CHECK ((file_extension IN ('pdf', 'xlsx', 'docx', 'md'))),
  CONSTRAINT "post_attachments_path_key" UNIQUE (path),
  CONSTRAINT "post_attachments_pkey" PRIMARY KEY (id),
  CONSTRAINT "post_attachments_post_id_fkey" FOREIGN KEY (post_id) REFERENCES "posts"(id) ON DELETE CASCADE,
  CONSTRAINT "post_attachments_post_id_sort_order_key" UNIQUE (post_id, sort_order),
  CONSTRAINT "post_attachments_sha256_check" CHECK(length(sha256)=64 AND sha256 NOT GLOB '*[^0-9a-f]*'),
  CONSTRAINT "post_attachments_sort_order_check" CHECK (((sort_order >= 0) AND (sort_order <= 1)))
);

CREATE TABLE "post_favorites" (
  "post_id" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CONSTRAINT "post_favorites_pkey" PRIMARY KEY (post_id, user_id),
  CONSTRAINT "post_favorites_post_id_fkey" FOREIGN KEY (post_id) REFERENCES "posts"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "post_favorites_user_id_fkey" FOREIGN KEY (user_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE "post_images" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "post_id" TEXT NOT NULL,
  "path" TEXT NOT NULL,
  "sort_order" INTEGER NOT NULL DEFAULT (0),
  "width" INTEGER,
  "height" INTEGER,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "thumbnail_path" TEXT,
  "thumbnail_width" INTEGER,
  "thumbnail_height" INTEGER,
  "full_width" INTEGER,
  "full_height" INTEGER,
  CONSTRAINT "post_images_pkey" PRIMARY KEY (id),
  CONSTRAINT "post_images_post_id_fkey" FOREIGN KEY (post_id) REFERENCES "posts"(id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE "post_likes" (
  "post_id" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CONSTRAINT "post_likes_pkey" PRIMARY KEY (post_id, user_id),
  CONSTRAINT "post_likes_post_id_fkey" FOREIGN KEY (post_id) REFERENCES "posts"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "post_likes_user_id_fkey" FOREIGN KEY (user_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE "postgraduate_source_suggestions" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "user_id" TEXT,
  "title" TEXT NOT NULL,
  "source_url" TEXT NOT NULL,
  "school" TEXT,
  "unit" TEXT,
  "major" TEXT,
  "exam_year" INTEGER,
  "source_kind" TEXT NOT NULL DEFAULT ('other'),
  "note" TEXT,
  "status" TEXT NOT NULL DEFAULT ('open'),
  "approved_source_id" TEXT,
  "admin_note" TEXT,
  "reviewed_by" TEXT,
  "reviewed_at" TEXT,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "search_text" TEXT GENERATED ALWAYS AS (lower(((((((((((COALESCE(title, '') || ' ') || COALESCE(source_url, '')) || ' ') || COALESCE(school, '')) || ' ') || COALESCE(unit, '')) || ' ') || COALESCE(major, '')) || ' ') || COALESCE(note, '')))) STORED,
  CONSTRAINT "postgraduate_source_suggestions_approved_source_id_fkey" FOREIGN KEY (approved_source_id) REFERENCES "postgraduate_sources"(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT "postgraduate_source_suggestions_exam_year_valid" CHECK (((exam_year IS NULL) OR ((exam_year >= 2000) AND (exam_year <= 2100)))),
  CONSTRAINT "postgraduate_source_suggestions_pkey" PRIMARY KEY (id),
  CONSTRAINT "postgraduate_source_suggestions_reviewed_by_fkey" FOREIGN KEY (reviewed_by) REFERENCES "admin_accounts"(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT "postgraduate_source_suggestions_source_kind_check" CHECK ((source_kind IN ('admission_notice', 'major_catalog', 'score_line', 'enrollment_plan', 'bibliography', 'retest', 'registration', 'other'))),
  CONSTRAINT "postgraduate_source_suggestions_status_check" CHECK ((status IN ('open', 'approved', 'rejected'))),
  CONSTRAINT "postgraduate_source_suggestions_title_not_blank" CHECK ((NULLIF(trim(title), '') IS NOT NULL)),
  CONSTRAINT "postgraduate_source_suggestions_url_not_blank" CHECK ((NULLIF(trim(source_url), '') IS NOT NULL)),
  CONSTRAINT "postgraduate_source_suggestions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE SET NULL
);

CREATE TABLE "postgraduate_sources" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "title" TEXT NOT NULL,
  "summary" TEXT NOT NULL DEFAULT (''),
  "source_url" TEXT NOT NULL,
  "source_kind" TEXT NOT NULL DEFAULT ('other'),
  "trust_level" TEXT NOT NULL DEFAULT ('curated'),
  "school" TEXT,
  "unit" TEXT,
  "major" TEXT,
  "exam_year" INTEGER,
  "published_at" TEXT,
  "verified_at" TEXT,
  "status" TEXT NOT NULL DEFAULT ('published'),
  "created_by" TEXT,
  "updated_by" TEXT,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "search_text" TEXT GENERATED ALWAYS AS (lower(((((((((((COALESCE(title, '') || ' ') || COALESCE(summary, '')) || ' ') || COALESCE(school, '')) || ' ') || COALESCE(unit, '')) || ' ') || COALESCE(major, '')) || ' ') || COALESCE(source_url, '')))) STORED,
  CONSTRAINT "postgraduate_sources_created_by_fkey" FOREIGN KEY (created_by) REFERENCES "admin_accounts"(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT "postgraduate_sources_exam_year_valid" CHECK (((exam_year IS NULL) OR ((exam_year >= 2000) AND (exam_year <= 2100)))),
  CONSTRAINT "postgraduate_sources_pkey" PRIMARY KEY (id),
  CONSTRAINT "postgraduate_sources_source_kind_check" CHECK ((source_kind IN ('admission_notice', 'major_catalog', 'score_line', 'enrollment_plan', 'bibliography', 'retest', 'registration', 'other'))),
  CONSTRAINT "postgraduate_sources_status_check" CHECK ((status IN ('published', 'hidden', 'archived'))),
  CONSTRAINT "postgraduate_sources_title_not_blank" CHECK ((NULLIF(trim(title), '') IS NOT NULL)),
  CONSTRAINT "postgraduate_sources_trust_level_check" CHECK ((trust_level IN ('official', 'curated', 'verified_user'))),
  CONSTRAINT "postgraduate_sources_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES "admin_accounts"(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT "postgraduate_sources_url_not_blank" CHECK ((NULLIF(trim(source_url), '') IS NOT NULL))
);

CREATE TABLE "posts" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "author_id" TEXT NOT NULL,
  "title" TEXT NOT NULL,
  "body" TEXT NOT NULL,
  "category" TEXT,
  "is_anonymous" INTEGER NOT NULL DEFAULT (0) CHECK ("is_anonymous" IN (0,1)),
  "comment_count" INTEGER NOT NULL DEFAULT (0),
  "status" TEXT NOT NULL DEFAULT ('published'),
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "moderated_by" TEXT,
  "moderated_at" TEXT,
  "moderation_reason" TEXT,
  "like_count" INTEGER NOT NULL DEFAULT (0),
  "campus_id" TEXT NOT NULL,
  "expected_image_count" INTEGER,
  "image_upload_completed_at" TEXT,
  "expected_attachment_count" INTEGER NOT NULL DEFAULT (0),
  "attachment_upload_completed_at" TEXT,
  "media_purge_after" TEXT,
  "media_purged_at" TEXT,
  "media_cleanup_hold" INTEGER NOT NULL DEFAULT (0) CHECK ("media_cleanup_hold" IN (0,1)),
  CONSTRAINT "posts_author_id_fkey" FOREIGN KEY (author_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "posts_campus_id_fkey" FOREIGN KEY (campus_id) REFERENCES "campuses"(id) ON UPDATE CASCADE,
  CONSTRAINT "posts_expected_attachment_count_check" CHECK (((expected_attachment_count >= 0) AND (expected_attachment_count <= 2))),
  CONSTRAINT "posts_expected_image_count_check" CHECK (((expected_image_count IS NULL) OR ((expected_image_count >= 0) AND (expected_image_count <= 9)))),
  CONSTRAINT "posts_moderated_by_fkey" FOREIGN KEY (moderated_by) REFERENCES "admin_accounts"(id) ON DELETE SET NULL,
  CONSTRAINT "posts_pkey" PRIMARY KEY (id),
  CONSTRAINT "posts_status_check" CHECK ((status IN ('published', 'deleted', 'hidden', 'pending_review')))
);

CREATE TABLE "profile_auth_links" (
  "auth_user_id" TEXT NOT NULL,
  "profile_id" TEXT NOT NULL,
  "edu_id" TEXT NOT NULL,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "last_seen_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "campus_id" TEXT NOT NULL DEFAULT ('bjfu'),
  CONSTRAINT "profile_auth_links_auth_user_id_fkey" FOREIGN KEY (auth_user_id) REFERENCES "auth_users"(id) ON DELETE CASCADE,
  CONSTRAINT "profile_auth_links_campus_id_fkey" FOREIGN KEY (campus_id) REFERENCES "campuses"(id) ON UPDATE CASCADE,
  CONSTRAINT "profile_auth_links_edu_id_not_blank" CHECK ((NULLIF(trim(edu_id), '') IS NOT NULL)),
  CONSTRAINT "profile_auth_links_pkey" PRIMARY KEY (auth_user_id),
  CONSTRAINT "profile_auth_links_profile_id_fkey" FOREIGN KEY (profile_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE "profiles" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "edu_id" TEXT NOT NULL,
  "nickname" TEXT NOT NULL,
  "display_name" TEXT,
  "avatar_path" TEXT,
  "bio" TEXT,
  "is_profile_complete" INTEGER NOT NULL DEFAULT (0) CHECK ("is_profile_complete" IN (0,1)),
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "major" TEXT,
  "grade" TEXT,
  "bound_email" TEXT,
  "pending_bound_email" TEXT,
  "email_verification_sent_at" TEXT,
  "profile_edited_at" TEXT,
  "muted_until" TEXT,
  "muted_reason" TEXT,
  "muted_by" TEXT,
  "muted_at" TEXT,
  "campus_id" TEXT NOT NULL DEFAULT ('bjfu'),
  "shows_edu_verification_badge" INTEGER NOT NULL DEFAULT (0) CHECK ("shows_edu_verification_badge" IN (0,1)),
  "cover_path" TEXT,
  "community_campus_id" TEXT,
  "community_access_status" TEXT NOT NULL DEFAULT ('general'),
  "community_school_name" TEXT,
  "community_rejection_reason" TEXT,
  "community_request_id" TEXT,
  CONSTRAINT "profiles_campus_id_fkey" FOREIGN KEY (campus_id) REFERENCES "campuses"(id) ON UPDATE CASCADE,
  CONSTRAINT "profiles_community_access_status_check" CHECK ((community_access_status IN ('general', 'pending', 'approved', 'rejected'))),
  CONSTRAINT "profiles_community_campus_id_fkey" FOREIGN KEY (community_campus_id) REFERENCES "campuses"(id) ON UPDATE CASCADE,
  CONSTRAINT "profiles_community_request_id_fkey" FOREIGN KEY (community_request_id) REFERENCES "campus_membership_requests"(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT "profiles_muted_by_fkey" FOREIGN KEY (muted_by) REFERENCES "admin_accounts"(id) ON DELETE SET NULL,
  CONSTRAINT "profiles_pkey" PRIMARY KEY (id)
);

CREATE TABLE "semester_runtime_configs" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "semester_id" TEXT NOT NULL,
  "semester_start_date" TEXT NOT NULL,
  "supported_weeks" INTEGER NOT NULL DEFAULT (20),
  "graduate_timetable_term_code" TEXT NOT NULL,
  "calendar_events" TEXT NOT NULL DEFAULT ('[]') CHECK ("calendar_events" IS NULL OR json_valid("calendar_events")),
  "is_active" INTEGER NOT NULL DEFAULT (0) CHECK ("is_active" IN (0,1)),
  "created_by" TEXT,
  "updated_by" TEXT,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "campus_id" TEXT NOT NULL DEFAULT ('bjfu'),
  CONSTRAINT "semester_runtime_configs_calendar_events_array" CHECK ((json_type(calendar_events) = 'array')),
  CONSTRAINT "semester_runtime_configs_campus_id_fkey" FOREIGN KEY (campus_id) REFERENCES "campuses"(id) ON UPDATE CASCADE,
  CONSTRAINT "semester_runtime_configs_created_by_fkey" FOREIGN KEY (created_by) REFERENCES "admin_accounts"(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT "semester_runtime_configs_graduate_term_not_blank" CHECK ((NULLIF(trim(graduate_timetable_term_code), '') IS NOT NULL)),
  CONSTRAINT "semester_runtime_configs_pkey" PRIMARY KEY (id),
  CONSTRAINT "semester_runtime_configs_semester_not_blank" CHECK ((NULLIF(trim(semester_id), '') IS NOT NULL)),
  CONSTRAINT "semester_runtime_configs_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES "admin_accounts"(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT "semester_runtime_configs_weeks_valid" CHECK (((supported_weeks >= 1) AND (supported_weeks <= 30)))
);

CREATE TABLE "site_announcement_reads" (
  "announcement_id" TEXT NOT NULL,
  "user_id" TEXT NOT NULL,
  "read_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "dismissed_at" TEXT,
  CONSTRAINT "site_announcement_reads_announcement_id_fkey" FOREIGN KEY (announcement_id) REFERENCES "site_announcements"(id) ON DELETE CASCADE,
  CONSTRAINT "site_announcement_reads_pkey" PRIMARY KEY (announcement_id, user_id),
  CONSTRAINT "site_announcement_reads_user_id_fkey" FOREIGN KEY (user_id) REFERENCES "auth_users"(id) ON DELETE CASCADE
);

CREATE TABLE "site_announcements" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "title" TEXT NOT NULL,
  "body" TEXT NOT NULL,
  "level" TEXT NOT NULL DEFAULT ('info'),
  "status" TEXT NOT NULL DEFAULT ('draft'),
  "published_at" TEXT,
  "expires_at" TEXT,
  "created_by" TEXT NOT NULL,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "updated_by" TEXT,
  "campus_id" TEXT NOT NULL DEFAULT ('bjfu'),
  CONSTRAINT "site_announcements_body_check" CHECK (((length(trim(body)) >= 1) AND (length(trim(body)) <= 4000))),
  CONSTRAINT "site_announcements_campus_id_fkey" FOREIGN KEY (campus_id) REFERENCES "campuses"(id) ON UPDATE CASCADE,
  CONSTRAINT "site_announcements_expiry_after_publish" CHECK (((expires_at IS NULL) OR (published_at IS NULL) OR (expires_at > published_at))),
  CONSTRAINT "site_announcements_level_check" CHECK ((level IN ('info', 'warning', 'urgent'))),
  CONSTRAINT "site_announcements_pkey" PRIMARY KEY (id),
  CONSTRAINT "site_announcements_published_at_required" CHECK (((status <> 'published') OR (published_at IS NOT NULL))),
  CONSTRAINT "site_announcements_status_check" CHECK ((status IN ('draft', 'published', 'archived'))),
  CONSTRAINT "site_announcements_title_check" CHECK (((length(trim(title)) >= 1) AND (length(trim(title)) <= 120))),
  CONSTRAINT "site_announcements_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES "admin_accounts"(id) ON DELETE SET NULL
);

CREATE TABLE "teacher_ratings" (
  "teacher_id" INTEGER NOT NULL,
  "user_id" TEXT NOT NULL,
  "stars" INTEGER NOT NULL,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  CONSTRAINT "teacher_ratings_pkey" PRIMARY KEY (teacher_id, user_id),
  CONSTRAINT "teacher_ratings_stars_check" CHECK (((stars >= 1) AND (stars <= 5))),
  CONSTRAINT "teacher_ratings_teacher_id_fkey" FOREIGN KEY (teacher_id) REFERENCES "teachers"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "teacher_ratings_user_id_fkey" FOREIGN KEY (user_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE "teachers" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "name" TEXT NOT NULL,
  "unit" TEXT NOT NULL,
  "search_text" TEXT GENERATED ALWAYS AS (lower(((COALESCE(name, '') || ' ') || COALESCE(unit, '')))) STORED,
  "rating_average" REAL NOT NULL DEFAULT (0),
  "rating_count" INTEGER NOT NULL DEFAULT (0),
  "rating_1_count" INTEGER NOT NULL DEFAULT (0),
  "rating_2_count" INTEGER NOT NULL DEFAULT (0),
  "rating_3_count" INTEGER NOT NULL DEFAULT (0),
  "rating_4_count" INTEGER NOT NULL DEFAULT (0),
  "rating_5_count" INTEGER NOT NULL DEFAULT (0),
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "status" TEXT NOT NULL DEFAULT ('published'),
  "campus_id" TEXT NOT NULL DEFAULT ('bjfu'),
  CONSTRAINT "teachers_campus_id_fkey" FOREIGN KEY (campus_id) REFERENCES "campuses"(id) ON UPDATE CASCADE,
  CONSTRAINT "teachers_name_not_blank" CHECK ((NULLIF(trim(name), '') IS NOT NULL)),
  CONSTRAINT "teachers_status_check" CHECK ((status IN ('published', 'hidden'))),
  CONSTRAINT "teachers_unit_not_blank" CHECK ((NULLIF(trim(unit), '') IS NOT NULL))
);

CREATE TABLE "timetable_invites" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "owner_id" TEXT NOT NULL,
  "semester_id" TEXT NOT NULL,
  "code_hash" TEXT NOT NULL,
  "expires_at" TEXT NOT NULL,
  "accepted_by" TEXT,
  "accepted_at" TEXT,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "campus_id" TEXT NOT NULL,
  CONSTRAINT "timetable_invites_accepted_by_fkey" FOREIGN KEY (accepted_by) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT "timetable_invites_campus_id_fkey" FOREIGN KEY (campus_id) REFERENCES "campuses"(id) ON UPDATE CASCADE,
  CONSTRAINT "timetable_invites_code_hash_not_blank" CHECK ((NULLIF(trim(code_hash), '') IS NOT NULL)),
  CONSTRAINT "timetable_invites_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "timetable_invites_pkey" PRIMARY KEY (id),
  CONSTRAINT "timetable_invites_semester_not_blank" CHECK ((NULLIF(trim(semester_id), '') IS NOT NULL))
);

CREATE TABLE "timetable_share_members" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "owner_id" TEXT NOT NULL,
  "viewer_id" TEXT NOT NULL,
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "revoked_at" TEXT,
  "campus_id" TEXT NOT NULL,
  CONSTRAINT "timetable_share_members_campus_id_fkey" FOREIGN KEY (campus_id) REFERENCES "campuses"(id) ON UPDATE CASCADE,
  CONSTRAINT "timetable_share_members_not_self" CHECK ((owner_id <> viewer_id)),
  CONSTRAINT "timetable_share_members_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "timetable_share_members_owner_viewer_unique" UNIQUE (owner_id, viewer_id),
  CONSTRAINT "timetable_share_members_pkey" PRIMARY KEY (id),
  CONSTRAINT "timetable_share_members_viewer_id_fkey" FOREIGN KEY (viewer_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE "timetable_snapshots" (
  "id" TEXT NOT NULL DEFAULT (lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))),
  "owner_id" TEXT NOT NULL,
  "semester_id" TEXT NOT NULL,
  "courses" TEXT NOT NULL DEFAULT ('[]') CHECK ("courses" IS NULL OR json_valid("courses")),
  "course_count" INTEGER NOT NULL DEFAULT (0),
  "published_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "created_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "updated_at" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  "campus_id" TEXT NOT NULL,
  CONSTRAINT "timetable_snapshots_campus_id_fkey" FOREIGN KEY (campus_id) REFERENCES "campuses"(id) ON UPDATE CASCADE,
  CONSTRAINT "timetable_snapshots_course_count_valid" CHECK ((course_count >= 0)),
  CONSTRAINT "timetable_snapshots_courses_array" CHECK ((json_type(courses) = 'array')),
  CONSTRAINT "timetable_snapshots_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES "profiles"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "timetable_snapshots_owner_semester_unique" UNIQUE (owner_id, semester_id),
  CONSTRAINT "timetable_snapshots_pkey" PRIMARY KEY (id),
  CONSTRAINT "timetable_snapshots_semester_not_blank" CHECK ((NULLIF(trim(semester_id), '') IS NOT NULL))
);

CREATE TABLE migration_control (id INTEGER PRIMARY KEY CHECK(id=1), importing INTEGER NOT NULL CHECK(importing IN (0,1)));

INSERT INTO migration_control VALUES(1,0);

CREATE TRIGGER "catalog_suggestions_course_teacher_name_required_insert" BEFORE INSERT ON "catalog_suggestions" WHEN (SELECT importing FROM migration_control WHERE id=1)=0 AND NOT (((NEW."suggestion_type" <> 'course') OR (NEW."status" <> 'open') OR (NULLIF(trim(NEW."teacher_name"), '') IS NOT NULL))) BEGIN SELECT RAISE(ABORT,'catalog_suggestions_course_teacher_name_required'); END;

CREATE TRIGGER "catalog_suggestions_course_teacher_name_required_update" BEFORE UPDATE ON "catalog_suggestions" WHEN (SELECT importing FROM migration_control WHERE id=1)=0 AND NOT (((NEW."suggestion_type" <> 'course') OR (NEW."status" <> 'open') OR (NULLIF(trim(NEW."teacher_name"), '') IS NOT NULL))) BEGIN SELECT RAISE(ABORT,'catalog_suggestions_course_teacher_name_required'); END;

CREATE TRIGGER "catalog_suggestions_review_shape_insert" BEFORE INSERT ON "catalog_suggestions" WHEN (SELECT importing FROM migration_control WHERE id=1)=0 AND NOT ((((NEW."status" = 'open') AND (NEW."approved_teacher_id" IS NULL) AND (NEW."approved_course_id" IS NULL) AND (NEW."approved_dish_id" IS NULL) AND (NEW."reviewed_by" IS NULL) AND (NEW."reviewed_at" IS NULL)) OR ((NEW."status" = 'rejected') AND (NEW."approved_teacher_id" IS NULL) AND (NEW."approved_course_id" IS NULL) AND (NEW."approved_dish_id" IS NULL) AND (NEW."reviewed_at" IS NOT NULL)) OR ((NEW."status" = 'approved') AND (NEW."reviewed_at" IS NOT NULL) AND (((NEW."suggestion_type" = 'teacher') AND (NEW."approved_teacher_id" IS NOT NULL) AND (NEW."approved_course_id" IS NULL) AND (NEW."approved_dish_id" IS NULL)) OR ((NEW."suggestion_type" = 'course') AND (NEW."approved_teacher_id" IS NULL) AND (NEW."approved_course_id" IS NOT NULL) AND (NEW."approved_dish_id" IS NULL)) OR ((NEW."suggestion_type" = 'dish') AND (NEW."approved_teacher_id" IS NULL) AND (NEW."approved_course_id" IS NULL) AND (NEW."approved_dish_id" IS NOT NULL)))))) BEGIN SELECT RAISE(ABORT,'catalog_suggestions_review_shape'); END;

CREATE TRIGGER "catalog_suggestions_review_shape_update" BEFORE UPDATE ON "catalog_suggestions" WHEN (SELECT importing FROM migration_control WHERE id=1)=0 AND NOT ((((NEW."status" = 'open') AND (NEW."approved_teacher_id" IS NULL) AND (NEW."approved_course_id" IS NULL) AND (NEW."approved_dish_id" IS NULL) AND (NEW."reviewed_by" IS NULL) AND (NEW."reviewed_at" IS NULL)) OR ((NEW."status" = 'rejected') AND (NEW."approved_teacher_id" IS NULL) AND (NEW."approved_course_id" IS NULL) AND (NEW."approved_dish_id" IS NULL) AND (NEW."reviewed_at" IS NOT NULL)) OR ((NEW."status" = 'approved') AND (NEW."reviewed_at" IS NOT NULL) AND (((NEW."suggestion_type" = 'teacher') AND (NEW."approved_teacher_id" IS NOT NULL) AND (NEW."approved_course_id" IS NULL) AND (NEW."approved_dish_id" IS NULL)) OR ((NEW."suggestion_type" = 'course') AND (NEW."approved_teacher_id" IS NULL) AND (NEW."approved_course_id" IS NOT NULL) AND (NEW."approved_dish_id" IS NULL)) OR ((NEW."suggestion_type" = 'dish') AND (NEW."approved_teacher_id" IS NULL) AND (NEW."approved_course_id" IS NULL) AND (NEW."approved_dish_id" IS NOT NULL)))))) BEGIN SELECT RAISE(ABORT,'catalog_suggestions_review_shape'); END;

CREATE TRIGGER "comments_body_length_v2_insert" BEFORE INSERT ON "comments" WHEN (SELECT importing FROM migration_control WHERE id=1)=0 AND NOT (((length(trim(NEW."body")) >= 1) AND (length(trim(NEW."body")) <= 2000))) BEGIN SELECT RAISE(ABORT,'comments_body_length_v2'); END;

CREATE TRIGGER "comments_body_length_v2_update" BEFORE UPDATE ON "comments" WHEN (SELECT importing FROM migration_control WHERE id=1)=0 AND NOT (((length(trim(NEW."body")) >= 1) AND (length(trim(NEW."body")) <= 2000))) BEGIN SELECT RAISE(ABORT,'comments_body_length_v2'); END;

CREATE TRIGGER "community_reports_detail_length_v2_insert" BEFORE INSERT ON "community_reports" WHEN (SELECT importing FROM migration_control WHERE id=1)=0 AND NOT (((NEW."detail" IS NULL) OR ((length(trim(NEW."detail")) >= 1) AND (length(trim(NEW."detail")) <= 1000)))) BEGIN SELECT RAISE(ABORT,'community_reports_detail_length_v2'); END;

CREATE TRIGGER "community_reports_detail_length_v2_update" BEFORE UPDATE ON "community_reports" WHEN (SELECT importing FROM migration_control WHERE id=1)=0 AND NOT (((NEW."detail" IS NULL) OR ((length(trim(NEW."detail")) >= 1) AND (length(trim(NEW."detail")) <= 1000)))) BEGIN SELECT RAISE(ABORT,'community_reports_detail_length_v2'); END;

CREATE TRIGGER "posts_body_length_v2_insert" BEFORE INSERT ON "posts" WHEN (SELECT importing FROM migration_control WHERE id=1)=0 AND NOT (((length(trim(NEW."body")) >= 1) AND (length(trim(NEW."body")) <= 10000))) BEGIN SELECT RAISE(ABORT,'posts_body_length_v2'); END;

CREATE TRIGGER "posts_body_length_v2_update" BEFORE UPDATE ON "posts" WHEN (SELECT importing FROM migration_control WHERE id=1)=0 AND NOT (((length(trim(NEW."body")) >= 1) AND (length(trim(NEW."body")) <= 10000))) BEGIN SELECT RAISE(ABORT,'posts_body_length_v2'); END;

CREATE TRIGGER "posts_title_length_v2_insert" BEFORE INSERT ON "posts" WHEN (SELECT importing FROM migration_control WHERE id=1)=0 AND NOT (((length(trim(NEW."title")) >= 1) AND (length(trim(NEW."title")) <= 80))) BEGIN SELECT RAISE(ABORT,'posts_title_length_v2'); END;

CREATE TRIGGER "posts_title_length_v2_update" BEFORE UPDATE ON "posts" WHEN (SELECT importing FROM migration_control WHERE id=1)=0 AND NOT (((length(trim(NEW."title")) >= 1) AND (length(trim(NEW."title")) <= 80))) BEGIN SELECT RAISE(ABORT,'posts_title_length_v2'); END;

CREATE TRIGGER "profiles_completed_nickname_required_insert" BEFORE INSERT ON "profiles" WHEN (SELECT importing FROM migration_control WHERE id=1)=0 AND NOT (((NEW."is_profile_complete" = 0) OR (NULLIF(trim(NEW."nickname"), '') IS NOT NULL))) BEGIN SELECT RAISE(ABORT,'profiles_completed_nickname_required'); END;

CREATE TRIGGER "profiles_completed_nickname_required_update" BEFORE UPDATE ON "profiles" WHEN (SELECT importing FROM migration_control WHERE id=1)=0 AND NOT (((NEW."is_profile_complete" = 0) OR (NULLIF(trim(NEW."nickname"), '') IS NOT NULL))) BEGIN SELECT RAISE(ABORT,'profiles_completed_nickname_required'); END;

CREATE UNIQUE INDEX community_create_requests_resource_unique ON "private_community_create_requests" (mutation_kind, resource_id);

CREATE INDEX idx_admin_audit_logs_admin_id ON "admin_audit_logs" (admin_id, created_at DESC);

CREATE INDEX idx_admin_audit_logs_created_at ON "admin_audit_logs" (created_at DESC);

CREATE INDEX idx_admin_audit_logs_outcome_created_at ON "admin_audit_logs" (outcome, created_at DESC) WHERE (outcome IS NOT NULL);

CREATE INDEX idx_admin_audit_logs_request_id ON "admin_audit_logs" (request_id) WHERE (request_id IS NOT NULL);

CREATE INDEX idx_admin_login_attempts_ip_recent ON "admin_login_attempts" (ip_address, attempted_at DESC) WHERE (succeeded = 0);

CREATE INDEX idx_admin_login_attempts_retention ON "admin_login_attempts" (attempted_at);

CREATE INDEX idx_admin_login_attempts_username_ip_recent ON "admin_login_attempts" (normalized_username, ip_address, attempted_at DESC) WHERE (succeeded = 0);

CREATE INDEX idx_admin_sessions_active ON "admin_sessions" (expires_at) WHERE (revoked_at IS NULL);

CREATE INDEX idx_admin_sessions_admin_id ON "admin_sessions" (admin_id, created_at DESC);

CREATE INDEX idx_campus_membership_requests_normalized_status ON "campus_membership_requests" (normalized_school_name, status);

CREATE UNIQUE INDEX idx_campus_membership_requests_one_pending_per_profile ON "campus_membership_requests" (requester_profile_id) WHERE (status = 'pending');

CREATE INDEX idx_campus_membership_requests_requester ON "campus_membership_requests" (requester_profile_id, created_at DESC);

CREATE INDEX idx_campus_membership_requests_status_created ON "campus_membership_requests" (status, created_at DESC);

CREATE INDEX idx_campus_weather_cache_campus_id ON "campus_weather_cache" (campus_id);

CREATE UNIQUE INDEX idx_campuses_normalized_name_unique ON "campuses" (normalized_name);

CREATE INDEX idx_catalog_suggestions_campus_id ON "catalog_suggestions" (campus_id);

CREATE UNIQUE INDEX idx_catalog_suggestions_open_unique ON "catalog_suggestions" (campus_id, suggestion_type, lower(trim(name)), lower(trim(unit)), lower(trim(COALESCE(teacher_name, ''))), lower(trim(COALESCE(category, '')))) WHERE (status = 'open');

CREATE INDEX idx_catalog_suggestions_search_text ON "catalog_suggestions" (search_text);

CREATE INDEX idx_catalog_suggestions_status_created_at ON "catalog_suggestions" (status, created_at DESC);

CREATE INDEX idx_catalog_suggestions_type_status ON "catalog_suggestions" (suggestion_type, status, created_at DESC);

CREATE INDEX idx_catalog_suggestions_user_id ON "catalog_suggestions" (user_id, created_at DESC);

CREATE INDEX idx_comment_likes_user_comment ON "comment_likes" (user_id, comment_id);

CREATE INDEX idx_comments_author_id ON "comments" (author_id);

CREATE INDEX idx_comments_post_id ON "comments" (post_id, created_at);

CREATE INDEX idx_comments_thread_replies ON "comments" (parent_comment_id, created_at, id) WHERE (parent_comment_id IS NOT NULL);

CREATE INDEX idx_comments_thread_roots ON "comments" (post_id, created_at, id) WHERE (parent_comment_id IS NULL);

CREATE INDEX idx_community_banners_active ON "community_banners" (campus_id, published_at DESC) WHERE (status = 'published');

CREATE UNIQUE INDEX idx_community_banners_one_published_per_campus ON "community_banners" (campus_id) WHERE (status = 'published');

CREATE INDEX idx_community_blocks_blocked ON "community_blocks" (blocked_id);

CREATE INDEX idx_community_blocks_blocker ON "community_blocks" (blocker_id, created_at DESC);

CREATE INDEX idx_community_notifications_post_id ON "community_notifications" (post_id);

CREATE INDEX idx_community_notifications_recipient ON "community_notifications" (recipient_id, created_at DESC);

CREATE INDEX idx_community_notifications_recipient_visible ON "community_notifications" (recipient_id, created_at DESC) WHERE (dismissed_at IS NULL);

CREATE INDEX idx_community_poll_options_poll_sort ON "community_poll_options" (poll_id, sort_order);

CREATE INDEX idx_community_poll_votes_option_id ON "community_poll_votes" (option_id);

CREATE INDEX idx_community_poll_votes_user_created_at ON "community_poll_votes" (user_id, created_at DESC);

CREATE INDEX idx_community_polls_author_id ON "community_polls" (author_id, created_at DESC);

CREATE INDEX idx_community_polls_campus_id ON "community_polls" (campus_id);

CREATE INDEX idx_community_polls_created_at ON "community_polls" (created_at DESC) WHERE (status IN ('published', 'pending_review'));

CREATE INDEX idx_community_polls_deletion_pending ON "community_polls" (deletion_requested_at DESC) WHERE (deletion_status = 'pending');

CREATE INDEX idx_community_post_pins_active_lookup ON "community_post_pins" (scope, category, priority DESC, starts_at DESC) WHERE (status = 'active');

CREATE UNIQUE INDEX idx_community_post_pins_active_unique ON "community_post_pins" (post_id, scope, COALESCE(category, '')) WHERE (status = 'active');

CREATE INDEX idx_community_post_pins_campus_id ON "community_post_pins" (campus_id);

CREATE INDEX idx_community_post_pins_post_id ON "community_post_pins" (post_id);

CREATE UNIQUE INDEX idx_community_reports_open_comment_unique ON "community_reports" (reporter_id, comment_id) WHERE ((status = 'open') AND (target_type = 'comment'));

CREATE UNIQUE INDEX idx_community_reports_open_post_unique ON "community_reports" (reporter_id, post_id) WHERE ((status = 'open') AND (target_type = 'post'));

CREATE UNIQUE INDEX idx_community_reports_open_user_unique ON "community_reports" (reporter_id, reported_user_id) WHERE ((status = 'open') AND (target_type = 'user'));

CREATE INDEX idx_community_reports_reported_user ON "community_reports" (reported_user_id, created_at DESC);

CREATE INDEX idx_community_reports_reporter ON "community_reports" (reporter_id, created_at DESC);

CREATE INDEX idx_community_reports_status_created ON "community_reports" (status, created_at DESC);

CREATE INDEX idx_community_terms_acceptances_user ON "community_terms_acceptances" (user_id, accepted_at DESC);

CREATE INDEX idx_course_catalog_campus_id ON "course_catalog" (campus_id);

CREATE UNIQUE INDEX idx_course_catalog_campus_name_unit_category_unique ON "course_catalog" (campus_id, lower(trim(name)), lower(trim(unit)), lower(trim(category)));

CREATE INDEX idx_course_catalog_category ON "course_catalog" (category, status, rating_average DESC, rating_count DESC);

CREATE INDEX idx_course_catalog_rating ON "course_catalog" (rating_average DESC, rating_count DESC, id);

CREATE INDEX idx_course_catalog_search_text ON "course_catalog" (search_text);

CREATE INDEX idx_course_ratings_user_id ON "course_ratings" (user_id);

CREATE INDEX idx_dish_catalog_campus_id ON "dish_catalog" (campus_id);

CREATE UNIQUE INDEX idx_dish_catalog_campus_name_location_unique ON "dish_catalog" (campus_id, lower(trim(name)), lower(trim(location)));

CREATE INDEX idx_dish_catalog_location ON "dish_catalog" (campus_id, location, status, rating_average DESC, rating_count DESC);

CREATE INDEX idx_dish_catalog_rating ON "dish_catalog" (rating_average DESC, rating_count DESC, id);

CREATE INDEX idx_dish_catalog_search_text ON "dish_catalog" (search_text);

CREATE INDEX idx_dish_ratings_user_id ON "dish_ratings" (user_id);

CREATE INDEX idx_feedback_submissions_campus_id ON "feedback_submissions" (campus_id);

CREATE INDEX idx_feedback_submissions_created_at ON "feedback_submissions" (created_at DESC);

CREATE UNIQUE INDEX idx_national_calendar_runtime_configs_single_active ON "national_calendar_runtime_configs" (is_active) WHERE (is_active = 1);

CREATE INDEX idx_post_attachments_post ON "post_attachments" (post_id, sort_order);

CREATE INDEX idx_post_favorites_post_id ON "post_favorites" (post_id);

CREATE INDEX idx_post_favorites_user_created_at ON "post_favorites" (user_id, created_at DESC);

CREATE INDEX idx_post_favorites_user_post_id ON "post_favorites" (user_id, post_id);

CREATE INDEX idx_post_images_post_id ON "post_images" (post_id, sort_order);

CREATE INDEX idx_post_likes_post_id ON "post_likes" (post_id);

CREATE INDEX idx_post_likes_user_id ON "post_likes" (user_id);

CREATE INDEX idx_post_likes_user_post_id ON "post_likes" (user_id, post_id);

CREATE INDEX idx_postgraduate_source_suggestions_search_text ON "postgraduate_source_suggestions" (search_text);

CREATE INDEX idx_postgraduate_source_suggestions_status_created ON "postgraduate_source_suggestions" (status, created_at DESC);

CREATE INDEX idx_postgraduate_source_suggestions_user_created ON "postgraduate_source_suggestions" (user_id, created_at DESC);

CREATE UNIQUE INDEX idx_postgraduate_suggestions_open_unique ON "postgraduate_source_suggestions" (lower(trim(source_url)), lower(trim(COALESCE(school, ''))), lower(trim(COALESCE(major, ''))), COALESCE(exam_year, 0)) WHERE (status = 'open');

CREATE INDEX idx_postgraduate_sources_scope ON "postgraduate_sources" (school, major, exam_year) WHERE (status = 'published');

CREATE INDEX idx_postgraduate_sources_search_text ON "postgraduate_sources" (search_text);

CREATE INDEX idx_postgraduate_sources_status_verified ON "postgraduate_sources" (status, verified_at DESC, published_at DESC, created_at DESC);

CREATE INDEX idx_posts_author_id ON "posts" (author_id);

CREATE INDEX idx_posts_campus_id ON "posts" (campus_id);

CREATE INDEX idx_posts_campus_status_created_at ON "posts" (campus_id, status, created_at DESC);

CREATE INDEX idx_posts_created_at ON "posts" (created_at DESC);

CREATE INDEX idx_posts_pending_image_upload ON "posts" (created_at) WHERE (status = 'pending_review');

CREATE INDEX idx_posts_public_profile_stats ON "posts" (author_id, created_at DESC) WHERE ((status = 'published') AND (is_anonymous = 0));

CREATE INDEX idx_posts_published_category_created_at ON "posts" (category, created_at DESC) WHERE (status = 'published');

CREATE INDEX idx_posts_published_created_at ON "posts" (created_at DESC) WHERE (status = 'published');

CREATE INDEX idx_profile_auth_links_campus_edu_id ON "profile_auth_links" (campus_id, edu_id);

CREATE INDEX idx_profile_auth_links_campus_id ON "profile_auth_links" (campus_id);

CREATE INDEX idx_profile_auth_links_edu_id ON "profile_auth_links" (edu_id);

CREATE INDEX idx_profile_auth_links_profile_id ON "profile_auth_links" (profile_id);

CREATE UNIQUE INDEX idx_profiles_campus_edu_id_unique ON "profiles" (campus_id, edu_id);

CREATE INDEX idx_profiles_campus_id ON "profiles" (campus_id);

CREATE INDEX idx_profiles_edu_id ON "profiles" (edu_id);

CREATE INDEX idx_profiles_muted_until ON "profiles" (muted_until) WHERE (muted_until IS NOT NULL);

CREATE UNIQUE INDEX profiles_bound_email_unique ON "profiles" (lower(bound_email)) WHERE (NULLIF(trim(bound_email), '') IS NOT NULL);

CREATE INDEX idx_semester_runtime_configs_campus_id ON "semester_runtime_configs" (campus_id);

CREATE UNIQUE INDEX idx_semester_runtime_configs_campus_semester_unique ON "semester_runtime_configs" (campus_id, semester_id);

CREATE UNIQUE INDEX idx_semester_runtime_configs_campus_single_active ON "semester_runtime_configs" (campus_id) WHERE (is_active = 1);

CREATE INDEX idx_site_announcement_reads_user ON "site_announcement_reads" (user_id, read_at DESC);

CREATE INDEX idx_site_announcements_campus_id ON "site_announcements" (campus_id);

CREATE INDEX idx_site_announcements_expires_at ON "site_announcements" (expires_at);

CREATE INDEX idx_site_announcements_public_feed ON "site_announcements" (status, published_at DESC);

CREATE INDEX idx_teacher_ratings_user_id ON "teacher_ratings" (user_id);

CREATE INDEX idx_teachers_campus_id ON "teachers" (campus_id);

CREATE UNIQUE INDEX idx_teachers_campus_name_unit_unique ON "teachers" (campus_id, lower(trim(name)), lower(trim(unit)));

CREATE INDEX idx_teachers_rating ON "teachers" (rating_average DESC, rating_count DESC, id);

CREATE INDEX idx_teachers_search_text ON "teachers" (search_text);

CREATE UNIQUE INDEX idx_timetable_invites_campus_code_hash_unique ON "timetable_invites" (campus_id, code_hash);

CREATE INDEX idx_timetable_invites_campus_id ON "timetable_invites" (campus_id);

CREATE INDEX idx_timetable_invites_owner_created ON "timetable_invites" (owner_id, created_at DESC);

CREATE INDEX idx_timetable_share_members_campus_id ON "timetable_share_members" (campus_id);

CREATE INDEX idx_timetable_share_members_owner_active ON "timetable_share_members" (owner_id, created_at DESC) WHERE (revoked_at IS NULL);

CREATE INDEX idx_timetable_share_members_viewer_active ON "timetable_share_members" (viewer_id, created_at DESC) WHERE (revoked_at IS NULL);

CREATE INDEX idx_timetable_snapshots_campus_id ON "timetable_snapshots" (campus_id);

CREATE INDEX idx_timetable_snapshots_owner_published ON "timetable_snapshots" (owner_id, published_at DESC);

CREATE VIRTUAL TABLE "posts_search" USING fts5("title","body","category",content='posts',content_rowid='rowid',tokenize='trigram');

CREATE TRIGGER "posts_search_insert" AFTER INSERT ON "posts" BEGIN INSERT INTO "posts_search"(rowid,"title","body","category") VALUES(NEW.rowid,NEW."title",NEW."body",NEW."category"); END;

CREATE TRIGGER "posts_search_delete" AFTER DELETE ON "posts" BEGIN INSERT INTO "posts_search"("posts_search",rowid,"title","body","category") VALUES('delete',OLD.rowid,OLD."title",OLD."body",OLD."category"); END;

CREATE TRIGGER "posts_search_update" AFTER UPDATE ON "posts" BEGIN INSERT INTO "posts_search"("posts_search",rowid,"title","body","category") VALUES('delete',OLD.rowid,OLD."title",OLD."body",OLD."category"); INSERT INTO "posts_search"(rowid,"title","body","category") VALUES(NEW.rowid,NEW."title",NEW."body",NEW."category"); END;

CREATE VIRTUAL TABLE "comments_search" USING fts5("body",content='comments',content_rowid='rowid',tokenize='trigram');

CREATE TRIGGER "comments_search_insert" AFTER INSERT ON "comments" BEGIN INSERT INTO "comments_search"(rowid,"body") VALUES(NEW.rowid,NEW."body"); END;

CREATE TRIGGER "comments_search_delete" AFTER DELETE ON "comments" BEGIN INSERT INTO "comments_search"("comments_search",rowid,"body") VALUES('delete',OLD.rowid,OLD."body"); END;

CREATE TRIGGER "comments_search_update" AFTER UPDATE ON "comments" BEGIN INSERT INTO "comments_search"("comments_search",rowid,"body") VALUES('delete',OLD.rowid,OLD."body"); INSERT INTO "comments_search"(rowid,"body") VALUES(NEW.rowid,NEW."body"); END;

CREATE VIRTUAL TABLE "profiles_search" USING fts5("nickname","display_name","edu_id","bound_email",content='profiles',content_rowid='rowid',tokenize='trigram');

CREATE TRIGGER "profiles_search_insert" AFTER INSERT ON "profiles" BEGIN INSERT INTO "profiles_search"(rowid,"nickname","display_name","edu_id","bound_email") VALUES(NEW.rowid,NEW."nickname",NEW."display_name",NEW."edu_id",NEW."bound_email"); END;

CREATE TRIGGER "profiles_search_delete" AFTER DELETE ON "profiles" BEGIN INSERT INTO "profiles_search"("profiles_search",rowid,"nickname","display_name","edu_id","bound_email") VALUES('delete',OLD.rowid,OLD."nickname",OLD."display_name",OLD."edu_id",OLD."bound_email"); END;

CREATE TRIGGER "profiles_search_update" AFTER UPDATE ON "profiles" BEGIN INSERT INTO "profiles_search"("profiles_search",rowid,"nickname","display_name","edu_id","bound_email") VALUES('delete',OLD.rowid,OLD."nickname",OLD."display_name",OLD."edu_id",OLD."bound_email"); INSERT INTO "profiles_search"(rowid,"nickname","display_name","edu_id","bound_email") VALUES(NEW.rowid,NEW."nickname",NEW."display_name",NEW."edu_id",NEW."bound_email"); END;

CREATE VIRTUAL TABLE "teachers_search" USING fts5("search_text",content='teachers',content_rowid='rowid',tokenize='trigram');

CREATE TRIGGER "teachers_search_insert" AFTER INSERT ON "teachers" BEGIN INSERT INTO "teachers_search"(rowid,"search_text") VALUES(NEW.rowid,NEW."search_text"); END;

CREATE TRIGGER "teachers_search_delete" AFTER DELETE ON "teachers" BEGIN INSERT INTO "teachers_search"("teachers_search",rowid,"search_text") VALUES('delete',OLD.rowid,OLD."search_text"); END;

CREATE TRIGGER "teachers_search_update" AFTER UPDATE ON "teachers" BEGIN INSERT INTO "teachers_search"("teachers_search",rowid,"search_text") VALUES('delete',OLD.rowid,OLD."search_text"); INSERT INTO "teachers_search"(rowid,"search_text") VALUES(NEW.rowid,NEW."search_text"); END;

CREATE VIRTUAL TABLE "course_catalog_search" USING fts5("search_text",content='course_catalog',content_rowid='rowid',tokenize='trigram');

CREATE TRIGGER "course_catalog_search_insert" AFTER INSERT ON "course_catalog" BEGIN INSERT INTO "course_catalog_search"(rowid,"search_text") VALUES(NEW.rowid,NEW."search_text"); END;

CREATE TRIGGER "course_catalog_search_delete" AFTER DELETE ON "course_catalog" BEGIN INSERT INTO "course_catalog_search"("course_catalog_search",rowid,"search_text") VALUES('delete',OLD.rowid,OLD."search_text"); END;

CREATE TRIGGER "course_catalog_search_update" AFTER UPDATE ON "course_catalog" BEGIN INSERT INTO "course_catalog_search"("course_catalog_search",rowid,"search_text") VALUES('delete',OLD.rowid,OLD."search_text"); INSERT INTO "course_catalog_search"(rowid,"search_text") VALUES(NEW.rowid,NEW."search_text"); END;

CREATE VIRTUAL TABLE "dish_catalog_search" USING fts5("search_text",content='dish_catalog',content_rowid='rowid',tokenize='trigram');

CREATE TRIGGER "dish_catalog_search_insert" AFTER INSERT ON "dish_catalog" BEGIN INSERT INTO "dish_catalog_search"(rowid,"search_text") VALUES(NEW.rowid,NEW."search_text"); END;

CREATE TRIGGER "dish_catalog_search_delete" AFTER DELETE ON "dish_catalog" BEGIN INSERT INTO "dish_catalog_search"("dish_catalog_search",rowid,"search_text") VALUES('delete',OLD.rowid,OLD."search_text"); END;

CREATE TRIGGER "dish_catalog_search_update" AFTER UPDATE ON "dish_catalog" BEGIN INSERT INTO "dish_catalog_search"("dish_catalog_search",rowid,"search_text") VALUES('delete',OLD.rowid,OLD."search_text"); INSERT INTO "dish_catalog_search"(rowid,"search_text") VALUES(NEW.rowid,NEW."search_text"); END;

CREATE VIRTUAL TABLE "postgraduate_sources_search" USING fts5("search_text",content='postgraduate_sources',content_rowid='rowid',tokenize='trigram');

CREATE TRIGGER "postgraduate_sources_search_insert" AFTER INSERT ON "postgraduate_sources" BEGIN INSERT INTO "postgraduate_sources_search"(rowid,"search_text") VALUES(NEW.rowid,NEW."search_text"); END;

CREATE TRIGGER "postgraduate_sources_search_delete" AFTER DELETE ON "postgraduate_sources" BEGIN INSERT INTO "postgraduate_sources_search"("postgraduate_sources_search",rowid,"search_text") VALUES('delete',OLD.rowid,OLD."search_text"); END;

CREATE TRIGGER "postgraduate_sources_search_update" AFTER UPDATE ON "postgraduate_sources" BEGIN INSERT INTO "postgraduate_sources_search"("postgraduate_sources_search",rowid,"search_text") VALUES('delete',OLD.rowid,OLD."search_text"); INSERT INTO "postgraduate_sources_search"(rowid,"search_text") VALUES(NEW.rowid,NEW."search_text"); END;

CREATE VIRTUAL TABLE "campuses_search" USING fts5("display_name","short_name",content='campuses',content_rowid='rowid',tokenize='trigram');

CREATE TRIGGER "campuses_search_insert" AFTER INSERT ON "campuses" BEGIN INSERT INTO "campuses_search"(rowid,"display_name","short_name") VALUES(NEW.rowid,NEW."display_name",NEW."short_name"); END;

CREATE TRIGGER "campuses_search_delete" AFTER DELETE ON "campuses" BEGIN INSERT INTO "campuses_search"("campuses_search",rowid,"display_name","short_name") VALUES('delete',OLD.rowid,OLD."display_name",OLD."short_name"); END;

CREATE TRIGGER "campuses_search_update" AFTER UPDATE ON "campuses" BEGIN INSERT INTO "campuses_search"("campuses_search",rowid,"display_name","short_name") VALUES('delete',OLD.rowid,OLD."display_name",OLD."short_name"); INSERT INTO "campuses_search"(rowid,"display_name","short_name") VALUES(NEW.rowid,NEW."display_name",NEW."short_name"); END;

CREATE VIRTUAL TABLE "site_announcements_search" USING fts5("title","body",content='site_announcements',content_rowid='rowid',tokenize='trigram');

CREATE TRIGGER "site_announcements_search_insert" AFTER INSERT ON "site_announcements" BEGIN INSERT INTO "site_announcements_search"(rowid,"title","body") VALUES(NEW.rowid,NEW."title",NEW."body"); END;

CREATE TRIGGER "site_announcements_search_delete" AFTER DELETE ON "site_announcements" BEGIN INSERT INTO "site_announcements_search"("site_announcements_search",rowid,"title","body") VALUES('delete',OLD.rowid,OLD."title",OLD."body"); END;

CREATE TRIGGER "site_announcements_search_update" AFTER UPDATE ON "site_announcements" BEGIN INSERT INTO "site_announcements_search"("site_announcements_search",rowid,"title","body") VALUES('delete',OLD.rowid,OLD."title",OLD."body"); INSERT INTO "site_announcements_search"(rowid,"title","body") VALUES(NEW.rowid,NEW."title",NEW."body"); END;

CREATE VIRTUAL TABLE "feedback_submissions_search" USING fts5("body","contact","issue_type",content='feedback_submissions',content_rowid='rowid',tokenize='trigram');

CREATE TRIGGER "feedback_submissions_search_insert" AFTER INSERT ON "feedback_submissions" BEGIN INSERT INTO "feedback_submissions_search"(rowid,"body","contact","issue_type") VALUES(NEW.rowid,NEW."body",NEW."contact",NEW."issue_type"); END;

CREATE TRIGGER "feedback_submissions_search_delete" AFTER DELETE ON "feedback_submissions" BEGIN INSERT INTO "feedback_submissions_search"("feedback_submissions_search",rowid,"body","contact","issue_type") VALUES('delete',OLD.rowid,OLD."body",OLD."contact",OLD."issue_type"); END;

CREATE TRIGGER "feedback_submissions_search_update" AFTER UPDATE ON "feedback_submissions" BEGIN INSERT INTO "feedback_submissions_search"("feedback_submissions_search",rowid,"body","contact","issue_type") VALUES('delete',OLD.rowid,OLD."body",OLD."contact",OLD."issue_type"); INSERT INTO "feedback_submissions_search"(rowid,"body","contact","issue_type") VALUES(NEW.rowid,NEW."body",NEW."contact",NEW."issue_type"); END;
