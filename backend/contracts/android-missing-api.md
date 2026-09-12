# Android REST adapter contracts

The Android adapter uses the following routes, now implemented in the Worker. All authorization derives from actor; caller profile/campus IDs must never widen access.

- `GET /v1/catalog/:kind?search=&filter_value=&offset=0&limit=50` returns existing catalog item array. `filter_value` matches teacher `unit`, course `category`, dish `location`; preserve order rating_average DESC, rating_count DESC, name ASC, id ASC.
- `GET /v1/catalog/:kind/ratings` returns current profile's ratings, array `{ teacher_id?|course_id?|dish_id?, user_id, stars }` across catalog (not only first catalog page).
- `POST /v1/catalog/suggestions` body `{suggestion_type,user_id,name,unit,teacher_name?,category?,credit?,initial_stars,note?}`. Derive owner from actor, reject supplied user_id mismatch. Return created record. Existing Android values are `teacher`/`course`/`dish`.
- `GET /v1/timetables/invites` returns owned invites, newest first, limit 20, shape `{id,owner_id,semester_id,expires_at,accepted_by?,accepted_at?,created_at}`. Never include `code_hash` or plaintext historic codes.
- `GET /v1/timetables/members?direction=incoming` returns active memberships for viewer=current actor; default remains owned memberships. Adapter uses existing member-id revoke/leave endpoints after resolving owned viewer/incoming owner. No extra mutation route required.
- `GET /v1/community/posts/:id/comment-threads?limit=20` returns existing iOS/Android thread response `{comments:[{thread_root_id,id,post_id,author_id,body,is_anonymous,status,created_at,updated_at,parent_comment_id?,reply_to_comment_id?,reply_to_author_id?,reply_target_is_visible,like_count,viewer_has_liked,is_deleted_placeholder}],has_more,next_cursor_created_at?,next_cursor_id?}`. Limit refers to root threads, replies retained; deleted/blocked root placeholders must retain visible replies. Existing `/comments` flat row LIMIT loses thread/reply semantics.

Android original client does not support uploads, polls, email auth or realtime UI, so adding UI for these is out of scope. File transport and signals are available at the backend boundary for future consumers.
