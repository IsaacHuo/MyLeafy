begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(12);

insert into auth.users (id)
values
  ('71000000-0000-0000-0000-000000000001'),
  ('71000000-0000-0000-0000-000000000002'),
  ('71000000-0000-0000-0000-000000000003'),
  ('71000000-0000-0000-0000-000000000004');

insert into public.profiles (
  id,
  campus_id,
  edu_id,
  nickname,
  display_name,
  community_campus_id,
  community_access_status,
  is_profile_complete
)
values
  (
    '72000000-0000-0000-0000-000000000001',
    'bjfu',
    'account-delete-owner',
    '待删除',
    '待删除',
    'bjfu',
    'approved',
    true
  ),
  (
    '72000000-0000-0000-0000-000000000002',
    'bjfu',
    'account-delete-other',
    '保留用户',
    '保留用户',
    'bjfu',
    'approved',
    true
  ),
  (
    '72000000-0000-0000-0000-000000000003',
    'bjfu',
    'review-demo-7d9f06b3-f8c0-42e3-9c6f-0b54a0a2d3ca',
    '安装级演示账户',
    '安装级演示账户',
    'bjfu',
    'approved',
    true
  ),
  (
    '72000000-0000-0000-0000-000000000004',
    'bjfu',
    'review-demo',
    '共享演示账户',
    '共享演示账户',
    'bjfu',
    'approved',
    true
  );

insert into public.profile_auth_links (
  auth_user_id,
  profile_id,
  campus_id,
  edu_id
)
values
  (
    '71000000-0000-0000-0000-000000000001',
    '72000000-0000-0000-0000-000000000001',
    'bjfu',
    'account-delete-owner'
  ),
  (
    '71000000-0000-0000-0000-000000000002',
    '72000000-0000-0000-0000-000000000002',
    'bjfu',
    'account-delete-other'
  ),
  (
    '71000000-0000-0000-0000-000000000003',
    '72000000-0000-0000-0000-000000000003',
    'bjfu',
    'review-demo-7d9f06b3-f8c0-42e3-9c6f-0b54a0a2d3ca'
  ),
  (
    '71000000-0000-0000-0000-000000000004',
    '72000000-0000-0000-0000-000000000004',
    'bjfu',
    'review-demo'
  );

insert into public.posts (id, campus_id, author_id, title, body, category, status)
values
  (
    '73000000-0000-0000-0000-000000000001',
    'bjfu',
    '72000000-0000-0000-0000-000000000001',
    '删除账户帖子',
    '应随账户删除',
    '测试',
    'published'
  ),
  (
    '73000000-0000-0000-0000-000000000002',
    'bjfu',
    '72000000-0000-0000-0000-000000000002',
    '保留帖子',
    '用于评论线程',
    '测试',
    'published'
  );

insert into public.comments (
  id,
  post_id,
  author_id,
  body,
  status,
  parent_comment_id,
  reply_to_comment_id
)
values
  (
    '74000000-0000-0000-0000-000000000001',
    '73000000-0000-0000-0000-000000000002',
    '72000000-0000-0000-0000-000000000001',
    '删除根评论',
    'published',
    null,
    null
  ),
  (
    '74000000-0000-0000-0000-000000000002',
    '73000000-0000-0000-0000-000000000002',
    '72000000-0000-0000-0000-000000000002',
    '保留其他用户回复',
    'published',
    '74000000-0000-0000-0000-000000000001',
    '74000000-0000-0000-0000-000000000001'
  );

insert into public.feedback_submissions (user_id, issue_type, body)
values (
  '72000000-0000-0000-0000-000000000001',
  '测试',
  '应随账户删除'
);

insert into public.catalog_suggestions (campus_id, suggestion_type, user_id, name, unit)
values (
  'bjfu',
  'teacher',
  '72000000-0000-0000-0000-000000000001',
  '删除建议',
  '测试单位'
);

select is(
  public.edge_delete_community_account(
    '71000000-0000-0000-0000-000000000001'
  ) ->> 'deleted',
  'true',
  'authenticated account deletion reaches a terminal success'
);

select is(
  (select count(*) from public.profiles where id = '72000000-0000-0000-0000-000000000001'),
  0::bigint,
  'the linked profile is deleted'
);

select is(
  (select count(*) from public.posts where id = '73000000-0000-0000-0000-000000000001'),
  0::bigint,
  'authored posts are deleted'
);

select is(
  (select count(*) from public.comments where id = '74000000-0000-0000-0000-000000000001'),
  0::bigint,
  'authored comments are deleted'
);

select is(
  (select count(*) from public.comments where id = '74000000-0000-0000-0000-000000000002'),
  1::bigint,
  'another user reply is retained'
);

select is(
  (select parent_comment_id from public.comments where id = '74000000-0000-0000-0000-000000000002'),
  null::uuid,
  'a retained reply is detached from the deleted root'
);

select is(
  (select count(*) from public.feedback_submissions where body = '应随账户删除'),
  0::bigint,
  'authored feedback text is deleted'
);

select is(
  (select count(*) from public.catalog_suggestions where name = '删除建议'),
  0::bigint,
  'authored catalog suggestions are deleted'
);

select is(
  public.edge_delete_community_account(
    '71000000-0000-0000-0000-000000000001'
  ) ->> 'deleted',
  'true',
  'repeated profile deletion is idempotent'
);

select is(
  public.edge_delete_community_account(
    '71000000-0000-0000-0000-000000000003'
  ) ->> 'deleted',
  'true',
  'installation-scoped review demo deletion succeeds'
);

select is(
  (select count(*) from public.profiles where id = '72000000-0000-0000-0000-000000000003'),
  0::bigint,
  'installation-scoped review demo profile is deleted'
);

select throws_like(
  $$
    select public.edge_delete_community_account(
      '71000000-0000-0000-0000-000000000004'
    )
  $$,
  '%COMMUNITY_DEMO_ACCOUNT_PROTECTED%',
  'legacy shared review demo remains protected'
);

select * from finish();
rollback;
