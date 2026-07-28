begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = '91000000-0000-0000-0000-000000000001';

select plan(15);

insert into auth.users (id)
values ('91000000-0000-0000-0000-000000000001');

insert into public.profiles (
  id, campus_id, edu_id, nickname, display_name,
  community_campus_id, community_access_status, is_profile_complete
) values (
  '92000000-0000-0000-0000-000000000001', 'bjfu', 'upload-closure-user',
  '上传闭环测试', '上传闭环测试', 'bjfu', 'approved', true
);

insert into public.profile_auth_links (auth_user_id, profile_id, campus_id, edu_id)
values (
  '91000000-0000-0000-0000-000000000001',
  '92000000-0000-0000-0000-000000000001',
  'bjfu',
  'upload-closure-user'
);

insert into public.community_terms_acceptances (user_id, terms_version)
values (
  '92000000-0000-0000-0000-000000000001',
  public.community_latest_terms_version()
);

insert into public.admin_accounts (id, username, password_hash, display_name, role, active)
values (
  '93000000-0000-0000-0000-000000000001',
  'upload-closure-admin',
  crypt('test-password', gen_salt('bf', 4)),
  '上传闭环管理员',
  'operator',
  true
);

select is(
  (public.create_community_post_v3(
    '94000000-0000-0000-0000-000000000001',
    '纯文字',
    '应立即发布',
    '测试',
    false,
    0
  )).status,
  'published',
  'zero-image posts publish immediately'
);

select is(
  (select expected_image_count from public.posts where id = '94000000-0000-0000-0000-000000000001'),
  0,
  'zero-image posts record an exact expected count'
);

select is(
  (public.create_community_post_v3(
    '94000000-0000-0000-0000-000000000002',
    '双图帖子',
    '最后一张图才发布',
    '测试',
    false,
    2
  )).status,
  'pending_review',
  'image posts start in the internal upload state'
);

select is(
  (select expected_image_count from public.posts where id = '94000000-0000-0000-0000-000000000002'),
  2,
  'image posts persist the exact expected image count'
);

insert into private.community_upload_receipts (
  id, auth_user_id, profile_id, post_id,
  full_path, thumbnail_path, full_sha256, thumbnail_sha256,
  full_size, thumbnail_size, full_width, full_height,
  thumbnail_width, thumbnail_height
) values
(
  '95000000-0000-0000-0000-000000000001',
  '91000000-0000-0000-0000-000000000001',
  '92000000-0000-0000-0000-000000000001',
  '94000000-0000-0000-0000-000000000002',
  'posts/92000000-0000-0000-0000-000000000001/94000000-0000-0000-0000-000000000002/full/one.jpg',
  'posts/92000000-0000-0000-0000-000000000001/94000000-0000-0000-0000-000000000002/thumb/one.jpg',
  repeat('a', 64), repeat('b', 64), 1000, 500, 1000, 800, 400, 320
),
(
  '95000000-0000-0000-0000-000000000002',
  '91000000-0000-0000-0000-000000000001',
  '92000000-0000-0000-0000-000000000001',
  '94000000-0000-0000-0000-000000000002',
  'posts/92000000-0000-0000-0000-000000000001/94000000-0000-0000-0000-000000000002/full/two.jpg',
  'posts/92000000-0000-0000-0000-000000000001/94000000-0000-0000-0000-000000000002/thumb/two.jpg',
  repeat('c', 64), repeat('d', 64), 1000, 500, 1000, 800, 400, 320
);

select lives_ok(
  $$select public.attach_community_post_image_v1(
    '95000000-0000-0000-0000-000000000001',
    '96000000-0000-0000-0000-000000000001',
    0
  )$$,
  'the first validated image attaches successfully'
);

select is(
  (select status from public.posts where id = '94000000-0000-0000-0000-000000000002'),
  'pending_review',
  'a partial multi-image upload remains private'
);

select lives_ok(
  $$select public.attach_community_post_image_v1(
    '95000000-0000-0000-0000-000000000002',
    '96000000-0000-0000-0000-000000000002',
    1
  )$$,
  'the final validated image attaches successfully'
);

select is(
  (select status from public.posts where id = '94000000-0000-0000-0000-000000000002'),
  'published',
  'the final image atomically publishes the post'
);

select ok(
  (select image_upload_completed_at is not null from public.posts where id = '94000000-0000-0000-0000-000000000002'),
  'automatic publication records upload completion'
);

select throws_ok(
  $$select public.attach_community_post_image_v1(
    '95000000-0000-0000-0000-000000000002',
    '96000000-0000-0000-0000-000000000003',
    1
  )$$,
  'P0001',
  'COMMUNITY_UPLOAD_RECEIPT_INVALID',
  'a consumed receipt cannot be reused'
);

update public.posts
set created_at = now() - interval '2 hours',
    updated_at = now() - interval '2 hours'
where id in (
  '94000000-0000-0000-0000-000000000001',
  '94000000-0000-0000-0000-000000000002'
);

insert into public.posts (
  id, campus_id, author_id, title, body, category, status, expected_image_count
) values (
  '94000000-0000-0000-0000-000000000003',
  'bjfu',
  '92000000-0000-0000-0000-000000000001',
  '不完整上传',
  '不能被后台发布',
  '测试',
  'pending_review',
  2
);

insert into public.post_images (
  id, post_id, path, thumbnail_path, sort_order, width, height
) values (
  '96000000-0000-0000-0000-000000000003',
  '94000000-0000-0000-0000-000000000003',
  'posts/incomplete/full/one.jpg',
  'posts/incomplete/thumb/one.jpg',
  0,
  100,
  100
);

select throws_ok(
  $$select public.admin_retry_pending_post_publish_v1(
    '94000000-0000-0000-0000-000000000003',
    '93000000-0000-0000-0000-000000000001'
  )$$,
  '23514',
  'ADMIN_POST_MEDIA_UPLOAD_INCOMPLETE',
  'admin retry refuses an incomplete upload'
);

select throws_ok(
  $$select public.admin_moderate_posts_v1(
    array['94000000-0000-0000-0000-000000000003'::uuid],
    'published',
    null,
    '93000000-0000-0000-0000-000000000001'
  )$$,
  '23514',
  'ADMIN_PENDING_POST_REQUIRES_RETRY',
  'generic restore cannot publish pending posts'
);

update public.posts
set expected_image_count = 1
where id = '94000000-0000-0000-0000-000000000003';

select is(
  (public.admin_retry_pending_post_publish_v1(
    '94000000-0000-0000-0000-000000000003',
    '93000000-0000-0000-0000-000000000001'
  )).status,
  'published',
  'admin retry publishes a complete failed upload'
);

insert into public.posts (
  id, campus_id, author_id, title, body, category, status, expected_image_count
) values (
  '94000000-0000-0000-0000-000000000004',
  'bjfu',
  '92000000-0000-0000-0000-000000000001',
  '旧版上传',
  '旧客户端仍可完成发布',
  '测试',
  'pending_review',
  null
);

insert into public.post_images (
  id, post_id, path, thumbnail_path, sort_order, width, height
) values (
  '96000000-0000-0000-0000-000000000004',
  '94000000-0000-0000-0000-000000000004',
  'posts/legacy/full/one.jpg',
  'posts/legacy/thumb/one.jpg',
  0,
  100,
  100
);

select is(
  (public.publish_community_post_v1('94000000-0000-0000-0000-000000000004')).status,
  'published',
  'legacy clients retain the validated publish RPC'
);

select ok(
  (public.backend_capabilities_v1() -> 'rpcs' ->> 'create_community_post_v3')::boolean,
  'the capability manifest advertises the new post RPC'
);

select * from finish();
rollback;
