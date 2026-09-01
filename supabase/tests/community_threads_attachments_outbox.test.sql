begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = 'a1000000-0000-0000-0000-000000000001';

select plan(36);

select ok(
  to_regprocedure('public.create_community_comment_v2(uuid,uuid,text,boolean,uuid)') is not null
    and has_function_privilege(
      'authenticated',
      'public.create_community_comment_v2(uuid,uuid,text,boolean,uuid)',
      'EXECUTE'
    ),
  'authenticated clients can call the five-argument top-level comment compatibility overload'
);

insert into auth.users (id) values
  ('a1000000-0000-0000-0000-000000000001'),
  ('a1000000-0000-0000-0000-000000000002');

insert into public.profiles (
  id, campus_id, edu_id, nickname, display_name,
  community_campus_id, community_access_status, is_profile_complete
) values
  (
    'a2000000-0000-0000-0000-000000000001', 'bjfu', 'threads-user-one',
    '用户一', '用户一', 'bjfu', 'approved', true
  ),
  (
    'a2000000-0000-0000-0000-000000000002', 'bjfu', 'threads-user-two',
    '用户二', '用户二', 'bjfu', 'approved', true
  );

insert into public.profile_auth_links (auth_user_id, profile_id, campus_id, edu_id) values
  (
    'a1000000-0000-0000-0000-000000000001',
    'a2000000-0000-0000-0000-000000000001',
    'bjfu',
    'threads-user-one'
  ),
  (
    'a1000000-0000-0000-0000-000000000002',
    'a2000000-0000-0000-0000-000000000002',
    'bjfu',
    'threads-user-two'
  );

insert into public.community_terms_acceptances (user_id, terms_version)
values
  ('a2000000-0000-0000-0000-000000000001', public.community_latest_terms_version()),
  ('a2000000-0000-0000-0000-000000000002', public.community_latest_terms_version());

select is(
  (public.create_community_post_v4(
    'a3000000-0000-0000-0000-000000000001',
    '评论线程测试',
    '正文',
    '测试',
    false,
    0,
    0
  )).status,
  'published',
  'a text-only v4 post publishes immediately'
);

select is(
  (public.create_community_comment_v2(
    'a4000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000001',
    '一级评论',
    null,
    null,
    false
  )).parent_comment_id,
  null,
  'a root comment has no parent'
);

set local request.jwt.claim.sub = 'a1000000-0000-0000-0000-000000000002';

select is(
  (public.create_community_comment_v2(
    'a4000000-0000-0000-0000-000000000002',
    'a3000000-0000-0000-0000-000000000001',
    '回复一级',
    'a4000000-0000-0000-0000-000000000001',
    'a4000000-0000-0000-0000-000000000001',
    false
  )).parent_comment_id,
  'a4000000-0000-0000-0000-000000000001'::uuid,
  'a reply belongs to the root thread'
);

set local request.jwt.claim.sub = 'a1000000-0000-0000-0000-000000000001';

select is(
  (public.create_community_comment_v2(
    'a4000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000001',
    '回复二级但仍然扁平',
    'a4000000-0000-0000-0000-000000000001',
    'a4000000-0000-0000-0000-000000000002',
    false
  )).parent_comment_id,
  'a4000000-0000-0000-0000-000000000001'::uuid,
  'replying to a reply remains at level two'
);

select throws_ok(
  $$select public.create_community_comment_v2(
    gen_random_uuid(),
    'a3000000-0000-0000-0000-000000000001',
    '错误的第三级',
    'a4000000-0000-0000-0000-000000000002',
    'a4000000-0000-0000-0000-000000000003',
    false
  )$$,
  '22023',
  'COMMUNITY_REPLY_TARGET_INVALID',
  'a second-level comment cannot be used as a parent'
);

select is(
  (select comment_count from public.posts where id = 'a3000000-0000-0000-0000-000000000001'),
  3,
  'root comments and replies contribute to the post comment count'
);

select throws_ok(
  $$select * from public.toggle_community_comment_like_v1(
    'a4000000-0000-0000-0000-000000000001',
    'b1000000-0000-0000-0000-000000000001'
  )$$,
  'P0001',
  'COMMUNITY_COMMENT_SELF_LIKE_FORBIDDEN',
  'authors cannot like their own comments'
);

set local request.jwt.claim.sub = 'a1000000-0000-0000-0000-000000000002';

select is(
  (select viewer_has_liked from public.toggle_community_comment_like_v1(
    'a4000000-0000-0000-0000-000000000001',
    'b1000000-0000-0000-0000-000000000002'
  )),
  true,
  'another user can like a comment'
);

select is(
  (select viewer_has_liked from public.toggle_community_comment_like_v1(
    'a4000000-0000-0000-0000-000000000001',
    'b1000000-0000-0000-0000-000000000002'
  )),
  true,
  'replaying the same like request is idempotent'
);

select is(
  (select like_count from public.comments where id = 'a4000000-0000-0000-0000-000000000001'),
  1,
  'comment like count is synchronized'
);

select is(
  (select count(*)::integer from public.community_notifications
   where recipient_id = 'a2000000-0000-0000-0000-000000000001'
     and actor_id = 'a2000000-0000-0000-0000-000000000002'
     and comment_id = 'a4000000-0000-0000-0000-000000000001'
     and type = 'like'),
  1,
  'a successful comment like notifies the comment author once'
);

select is(
  (select viewer_has_liked from public.toggle_community_comment_like_v1(
    'a4000000-0000-0000-0000-000000000001',
    'b1000000-0000-0000-0000-000000000003'
  )),
  false,
  'toggling again removes the like'
);

select is(
  (select count(*)::integer from public.community_notifications
   where recipient_id = 'a2000000-0000-0000-0000-000000000001'
     and actor_id = 'a2000000-0000-0000-0000-000000000002'
     and comment_id = 'a4000000-0000-0000-0000-000000000001'
     and type = 'like'),
  1,
  'removing a like does not create another notification'
);

set local request.jwt.claim.sub = 'a1000000-0000-0000-0000-000000000001';
select lives_ok(
  $$select public.soft_delete_own_comment(
    'a4000000-0000-0000-0000-000000000001'
  )$$,
  'a root comment with replies can be soft-deleted'
);

select is(
  (
    public.list_community_comment_threads_v1(
      'a3000000-0000-0000-0000-000000000001',
      null,
      null,
      20
    ) #>> '{comments,0,is_deleted_placeholder}'
  )::boolean,
  true,
  'a deleted root remains as a placeholder'
);

select is(
  jsonb_array_length(
    public.list_community_comment_threads_v1(
      'a3000000-0000-0000-0000-000000000001',
      null,
      null,
      20
    ) -> 'comments'
  ),
  3,
  'a thread page returns the root and all of its replies'
);

select is(
  (public.create_community_post_v4(
    'a3000000-0000-0000-0000-000000000002',
    '附件原子发布',
    '等待附件',
    '测试',
    false,
    0,
    1
  )).status,
  'pending_review',
  'an attachment post starts in the private upload state'
);

select is(
  (select status from public.posts where id = 'a3000000-0000-0000-0000-000000000002'),
  'pending_review',
  'a post remains private before every expected attachment is registered'
);

insert into private.community_attachment_upload_receipts (
  id, auth_user_id, profile_id, post_id, object_path, display_name,
  content_type, file_extension, byte_size, sha256
) values (
  'a5000000-0000-0000-0000-000000000001',
  'a1000000-0000-0000-0000-000000000001',
  'a2000000-0000-0000-0000-000000000001',
  'a3000000-0000-0000-0000-000000000002',
  'posts/a2000000-0000-0000-0000-000000000001/a3000000-0000-0000-0000-000000000002/a6000000-0000-0000-0000-000000000001.pdf',
  '测试资料.pdf',
  'application/pdf',
  'pdf',
  2048,
  repeat('a', 64)
);

select lives_ok(
  $$select public.attach_community_post_attachment_v1(
    'a5000000-0000-0000-0000-000000000001',
    'a6000000-0000-0000-0000-000000000001',
    0
  )$$,
  'a validated attachment can be attached'
);

select throws_ok(
  $$select public.attach_community_post_attachment_v1(
    'a5000000-0000-0000-0000-000000000001',
    gen_random_uuid(),
    0
  )$$,
  'P0001',
  'COMMUNITY_UPLOAD_RECEIPT_INVALID',
  'a consumed attachment validation receipt cannot be reused'
);

select is(
  (select status from public.posts where id = 'a3000000-0000-0000-0000-000000000002'),
  'published',
  'the last expected attachment atomically publishes the post'
);

select throws_ok(
  $$select public.create_community_comment_v2(
    gen_random_uuid(),
    'a3000000-0000-0000-0000-000000000002',
    '跨帖回复',
    'a4000000-0000-0000-0000-000000000001',
    'a4000000-0000-0000-0000-000000000002',
    false
  )$$,
  '22023',
  'COMMUNITY_REPLY_TARGET_INVALID',
  'a reply target cannot cross posts'
);

set local request.jwt.claim.sub = 'a1000000-0000-0000-0000-000000000001';

select is(
  (public.create_community_post_v4(
    'a3000000-0000-0000-0000-000000000003',
    '幂等发帖',
    '只应创建一次',
    '测试',
    false,
    0,
    0,
    'b3000000-0000-0000-0000-000000000001'
  )).id,
  'a3000000-0000-0000-0000-000000000003'::uuid,
  'an idempotent post request returns its created post'
);

select is(
  (public.create_community_post_v4(
    'a3000000-0000-0000-0000-000000000003',
    '幂等发帖',
    '只应创建一次',
    '测试',
    false,
    0,
    0,
    'b3000000-0000-0000-0000-000000000001'
  )).id,
  'a3000000-0000-0000-0000-000000000003'::uuid,
  'replaying a post request returns the first result'
);

select is(
  (select count(*)::integer from public.posts
   where id = 'a3000000-0000-0000-0000-000000000003'),
  1,
  'replaying a post request creates one post'
);

select throws_ok(
  $$select public.create_community_post_v4(
    'a3000000-0000-0000-0000-000000000003',
    '更换标题',
    '只应创建一次',
    '测试',
    false,
    0,
    0,
    'b3000000-0000-0000-0000-000000000001'
  )$$,
  '22023',
  'COMMUNITY_CREATE_REQUEST_REUSED',
  'a post request id cannot be replayed with different parameters'
);

select is(
  (public.create_community_post_v4(
    'a3000000-0000-0000-0000-000000000003',
    '幂等发帖',
    '只应创建一次',
    '测试',
    false,
    0,
    0
  )).id,
  'a3000000-0000-0000-0000-000000000003'::uuid,
  'the shipped v4 signature treats a repeated post UUID as success'
);

set local request.jwt.claim.sub = 'a1000000-0000-0000-0000-000000000002';

select is(
  (public.create_community_comment_v2(
    'a4000000-0000-0000-0000-000000000004',
    'a3000000-0000-0000-0000-000000000003',
    '网络超时重试',
    false,
    'b4000000-0000-0000-0000-000000000001'
  )).id,
  'a4000000-0000-0000-0000-000000000004'::uuid,
  'the five-argument top-level comment overload returns its created comment'
);

select is(
  (public.create_community_comment_v2(
    'a4000000-0000-0000-0000-000000000005',
    'a3000000-0000-0000-0000-000000000003',
    '网络超时重试',
    null,
    null,
    false,
    'b4000000-0000-0000-0000-000000000001'
  )).id,
  'a4000000-0000-0000-0000-000000000004'::uuid,
  'replaying a comment request returns the first result'
);

select is(
  (select count(*)::integer from public.comments
   where post_id = 'a3000000-0000-0000-0000-000000000003'
     and body = '网络超时重试'),
  1,
  'a timed-out comment replay creates one comment'
);

select is(
  (select count(*)::integer from public.community_notifications
   where recipient_id = 'a2000000-0000-0000-0000-000000000001'
     and actor_id = 'a2000000-0000-0000-0000-000000000002'
     and comment_id = 'a4000000-0000-0000-0000-000000000004'
     and type = 'comment'),
  1,
  'a timed-out comment replay notifies once'
);

select throws_ok(
  $$select public.create_community_comment_v2(
    'a4000000-0000-0000-0000-000000000006',
    'a3000000-0000-0000-0000-000000000003',
    '更换评论正文',
    null,
    null,
    false,
    'b4000000-0000-0000-0000-000000000001'
  )$$,
  '22023',
  'COMMUNITY_CREATE_REQUEST_REUSED',
  'a comment request id cannot be replayed with different parameters'
);

set local request.jwt.claim.sub = 'a1000000-0000-0000-0000-000000000001';

update public.posts
set status = 'deleted'
where id = 'a3000000-0000-0000-0000-000000000001';

select ok(
  (select media_purge_after >= now() + interval '29 days'
   from public.posts where id = 'a3000000-0000-0000-0000-000000000001'),
  'ordinary post deletion retains media for approximately 30 days'
);

set local request.jwt.claim.role = 'service_role';
update public.posts
set status = 'hidden'
where id = 'a3000000-0000-0000-0000-000000000002';

select is(
  (select media_cleanup_hold from public.posts where id = 'a3000000-0000-0000-0000-000000000002'),
  true,
  'a post hidden by administration pauses media cleanup'
);

update public.posts
set status = 'deleted'
where id = 'a3000000-0000-0000-0000-000000000002';
set local request.jwt.claim.role = 'authenticated';

select is(
  (select media_cleanup_hold from public.posts where id = 'a3000000-0000-0000-0000-000000000002'),
  false,
  'leaving the hidden state releases the explicit hold while report checks remain authoritative'
);

select * from finish();
rollback;
