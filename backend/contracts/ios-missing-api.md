# iOS client REST contract completion

Owned coordination document for the current migration. All responses below use the existing snake_case DTO coding keys in `leafy/Shared/Models/CommunityModels.swift`. Dates are UTC ISO8601 strings. Private identities/email must remain stripped on public profile reads; signed media URLs must be hydrated by the server. All routes require the authenticated actor and server campus/access checks unless noted.

## Required additional routes

| Method/path | Input | Output / behavior |
|---|---|---|
| GET `/v1/community/terms` | none | `{accepted: boolean, terms_version: string}` |
| GET `/v1/profiles/:id` | UUID | public `CommunityProfile` (including signed_avatar_url, signed_cover_url) or 404 |
| POST `/v1/profiles/stats` | `{profile_ids: [UUID]}` | `{profiles: [CommunityProfileStats]}` using existing stats RPC DTO |
| GET `/v1/community/activity/posts` | `kind=authored|public|liked|favorited&user_id=UUID&limit=N` | hydrated `[CommunityPost]`; authored/liked/favorited only current actor, public excludes anonymous |
| GET `/v1/community/activity/comments` | `limit=N` | hydrated `[CommunityComment]` current actor only |
| GET `/v1/community/posts/:id/comment-threads` | `after_created_at`, `after_id`, `limit` | `{comments:[CommunityComment],has_more:boolean,next_cursor_created_at:string|null,next_cursor_id:UUID|null}`. Root pagination including all replies; root placeholders for deleted/blocked roots with visible replies. Supply thread_root_id, reply_to_author_id, reply_target_is_visible, is_deleted_placeholder, viewer_has_liked, author and reply_to_author. Existing comments route caps 100 rows and cannot preserve this behavior. |
| POST `/v1/community/comments/:id/toggle-like` | `{}` | `{comment_id:UUID,like_count:number,viewer_has_liked:boolean}` atomic toggle |
| POST `/v1/community/posts/:id/toggle-like` | `{}` | hydrated `CommunityPost` atomic toggle |
| POST `/v1/community/posts/:id/toggle-favorite` | `{}` | hydrated `CommunityPost` atomic toggle |
| GET `/v1/community/posts/:id/pending` | none | `{id,author_id,status}` or null, owner only |
| POST `/v1/community/posts/:id/abort` | `{}` | `{aborted:true}`, owner only, abort pending uploads and cleanup files |
| GET `/v1/community/polls` | `kind=feed|authored|voted&limit=N` | hydrated `[CommunityPoll]` including author, options, viewer_option_id |
| DELETE `/v1/community/polls/:id` | none | existing deleteOwnPoll behavior (see Supabase RPC), not deletion-request substitution |
| POST `/v1/feedback` | `{issue_type,body,contact,device_info:{...}}` | `{submitted:true}`, current profile nullable for signed-in session without bootstrap |
| POST `/v1/catalog/suggestions` | `{suggestion_type,name,unit,teacher_name,category,credit,initial_stars}` | `{submitted:true}`, authenticated user/profile resolved server-side |
| GET `/v1/community/banner` | none | `CommunityBanner` or null, server-selected campus, `image_url` signed |
| GET `/v1/announcements` | `limit=N` | `[SiteAnnouncement]` including read_at, active visible non-dismissed only |
| POST `/v1/announcements/:id/read` | `{}` | `{updated:true}`, must not resurrect dismissed announcement |
| POST `/v1/announcements/:id/dismiss` | `{}` | `{updated:true}` |
| POST `/v1/notifications/:id/dismiss` | `{}` | `{updated:true}` |
| GET `/v1/notifications/settings` | none | `{user_id,muted_all,updated_at}`; absent row yields false |
| PUT `/v1/notifications/settings` | `{muted_all:boolean}` | same settings DTO |
| GET `/v1/postgraduate-sources` | `limit=N` | published `[PostgraduateSource]` |
| GET `/v1/timetables/invites` | `semester_id` | current owner's invite metadata array (no code_hash; code null) |

## Existing route adjustments

- GET `/v1/profile`: profile_required before bootstrap should map to client nil (already handled); profile media must contain signed URLs.
- POST `/v1/profile/image`: support `{kind:'cover',path:null}` reset to default; otherwise upload then attach returned immutable path.
- Catalog GET needs `category`, `canteen`, `location` filters, and `id` for detail lookup; client maps `{...catalog,viewer_stars}` to existing summary model.
- `/v1/notifications` needs hydrated actor profile and post_title (existing notification DTO), or client will show missing actor metadata.
- `/v1/timetables/members` must include viewer profile and permit `direction=viewing` to return current viewer's membership IDs for leave action (existing API deletes by membership ID while UI identifies owner/viewer UUID).
- `PUT /v1/timetables` and invite accept response should include owner profile to match GET hydration.
- Registration follows Better Auth existing `/sign-up/email`, `/email-otp/send-verification-otp` (`type:email-verification`), `/email-otp/verify-email`. Verify endpoint must establish bearer session or client must sign in with password after OTP (client will retain password only in memory for that flow).
- `/v1/files/upload` already returns server-generated path. iOS background queue must persist that response path and never assume legacy storage paths. Attachment uploads max 10 MiB can use background URLSession whole-file transfer; file upload remains retryable/idempotent by upload UUID.
