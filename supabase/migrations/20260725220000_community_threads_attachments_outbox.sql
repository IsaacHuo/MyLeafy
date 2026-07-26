-- Community threads, comment likes, private post attachments, and media-complete
-- publication. Older create_community_comment_v1/create_community_post_v3
-- callers remain supported.

alter table public.comments
  add column if not exists parent_comment_id uuid references public.comments (id) on delete restrict,
  add column if not exists reply_to_comment_id uuid references public.comments (id) on delete set null,
  add column if not exists like_count integer not null default 0;

alter table public.comments
  drop constraint if exists comments_like_count_nonnegative;

alter table public.comments
  add constraint comments_like_count_nonnegative check (like_count >= 0);

create index if not exists idx_comments_thread_roots
on public.comments (post_id, created_at asc, id asc)
where parent_comment_id is null;

create index if not exists idx_comments_thread_replies
on public.comments (parent_comment_id, created_at asc, id asc)
where parent_comment_id is not null;

create table if not exists public.comment_likes (
  comment_id uuid not null references public.comments (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);

create index if not exists idx_comment_likes_user_comment
on public.comment_likes (user_id, comment_id);

alter table public.comment_likes enable row level security;

drop policy if exists "comment_likes_select_same_campus" on public.comment_likes;
create policy "comment_likes_select_same_campus"
on public.comment_likes
for select
to authenticated
using (
  exists (
    select 1
    from public.comments
    join public.posts on posts.id = comments.post_id
    where comments.id = comment_likes.comment_id
      and posts.status = 'published'
      and posts.campus_id = public.current_profile_campus_id()
  )
);

revoke insert, update, delete on public.comment_likes from authenticated;
grant select on public.comment_likes to authenticated, service_role;
grant all on public.comment_likes to service_role;

create or replace function private.sync_community_comment_like_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_comment_id uuid := coalesce(new.comment_id, old.comment_id);
begin
  update public.comments
  set like_count = (
    select count(*)::integer
    from public.comment_likes
    where comment_id = target_comment_id
  )
  where id = target_comment_id;
  return coalesce(new, old);
end;
$$;

drop trigger if exists comment_likes_sync_count on public.comment_likes;
create trigger comment_likes_sync_count
after insert or delete on public.comment_likes
for each row execute function private.sync_community_comment_like_count();

create or replace function private.insert_community_interaction_notification_v1(
  p_recipient_id uuid,
  p_actor_id uuid,
  p_post_id uuid,
  p_comment_id uuid,
  p_type text,
  p_title text,
  p_body text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  created_notification_id uuid;
  recipient_muted boolean := false;
  post_campus_id text;
begin
  if p_recipient_id is null or p_recipient_id = p_actor_id then
    return null;
  end if;
  if p_actor_id is distinct from public.current_community_profile_id() then
    raise exception 'COMMUNITY_NOTIFICATION_ACTOR_INVALID';
  end if;
  if p_type not in ('comment', 'like') then
    raise exception 'COMMUNITY_NOTIFICATION_TYPE_INVALID';
  end if;

  select campus_id into post_campus_id
  from public.posts
  where id = p_post_id and status = 'published';

  if post_campus_id is null
     or post_campus_id <> public.current_profile_campus_id()
     or not exists (
       select 1 from public.profiles
       where id = p_recipient_id and community_campus_id = post_campus_id
     ) then
    raise exception 'COMMUNITY_NOTIFICATION_TARGET_INVALID';
  end if;

  select coalesce(muted_all, false) into recipient_muted
  from public.community_notification_settings
  where user_id = p_recipient_id;

  if coalesce(recipient_muted, false) then
    return null;
  end if;

  insert into public.community_notifications (
    recipient_id, actor_id, post_id, comment_id, type, title, body
  ) values (
    p_recipient_id,
    p_actor_id,
    p_post_id,
    p_comment_id,
    p_type,
    left(btrim(p_title), 160),
    nullif(left(btrim(coalesce(p_body, '')), 500), '')
  )
  returning id into created_notification_id;

  return created_notification_id;
end;
$$;

revoke all on function private.insert_community_interaction_notification_v1(uuid, uuid, uuid, uuid, text, text, text)
from public, anon, authenticated;

create or replace function public.create_community_comment_v2(
  p_id uuid,
  p_post_id uuid,
  p_body text,
  p_parent_comment_id uuid default null,
  p_reply_to_comment_id uuid default null,
  p_is_anonymous boolean default false
)
returns public.comments
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  current_profile_id uuid := public.current_community_profile_id();
  current_campus_id text := public.current_profile_campus_id();
  created_comment public.comments%rowtype;
  target_post public.posts%rowtype;
  parent_comment public.comments%rowtype;
  reply_target public.comments%rowtype;
  recipient_id uuid;
  actor_name text;
  normalized_body text := btrim(coalesce(p_body, ''));
begin
  if current_profile_id is null or current_campus_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;
  if char_length(normalized_body) not between 1 and 2000 then
    raise exception 'COMMUNITY_COMMENT_BODY_INVALID' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.profiles
    where id = current_profile_id
      and community_access_status = 'approved'
      and community_campus_id = current_campus_id
      and is_profile_complete = true
      and nullif(btrim(nickname), '') is not null
  ) then
    raise exception 'PROFILE_COMPLETION_REQUIRED';
  end if;
  if not public.has_accepted_community_terms(public.community_latest_terms_version()) then
    raise exception 'COMMUNITY_TERMS_REQUIRED';
  end if;

  select * into target_post
  from public.posts
  where id = p_post_id
    and campus_id = current_campus_id
    and status = 'published';
  if target_post.id is null then
    raise exception 'COMMUNITY_POST_NOT_FOUND';
  end if;

  if (p_parent_comment_id is null) <> (p_reply_to_comment_id is null) then
    raise exception 'COMMUNITY_REPLY_TARGET_INVALID' using errcode = '22023';
  end if;

  if p_parent_comment_id is not null then
    select * into parent_comment
    from public.comments
    where id = p_parent_comment_id
      and post_id = p_post_id
      and parent_comment_id is null
      and status = 'published';

    select * into reply_target
    from public.comments
    where id = p_reply_to_comment_id
      and post_id = p_post_id
      and status = 'published';

    if parent_comment.id is null
       or reply_target.id is null
       or (reply_target.id <> parent_comment.id
           and reply_target.parent_comment_id is distinct from parent_comment.id) then
      raise exception 'COMMUNITY_REPLY_TARGET_INVALID' using errcode = '22023';
    end if;
    recipient_id := reply_target.author_id;
  else
    recipient_id := target_post.author_id;
  end if;

  insert into public.comments (
    id, post_id, author_id, body, is_anonymous, status,
    parent_comment_id, reply_to_comment_id, like_count, created_at, updated_at
  ) values (
    coalesce(p_id, gen_random_uuid()),
    p_post_id,
    current_profile_id,
    normalized_body,
    coalesce(p_is_anonymous, false),
    'published',
    p_parent_comment_id,
    p_reply_to_comment_id,
    0,
    now(),
    now()
  )
  returning * into created_comment;

  select coalesce(nullif(btrim(display_name), ''), nullif(btrim(nickname), ''), '同学')
  into actor_name
  from public.profiles
  where id = current_profile_id;

  perform private.insert_community_interaction_notification_v1(
    recipient_id,
    current_profile_id,
    p_post_id,
    created_comment.id,
    'comment',
    case
      when p_parent_comment_id is null then actor_name || ' 回复了你的帖子'
      else actor_name || ' 回复了你的评论'
    end,
    left(normalized_body, 120)
  );

  return created_comment;
end;
$$;

revoke all on function public.create_community_comment_v2(uuid, uuid, text, uuid, uuid, boolean)
from public, anon;
grant execute on function public.create_community_comment_v2(uuid, uuid, text, uuid, uuid, boolean)
to authenticated, service_role;

create table if not exists private.community_comment_like_requests (
  request_id uuid not null,
  user_id uuid not null references public.profiles (id) on delete cascade,
  comment_id uuid not null references public.comments (id) on delete cascade,
  like_count integer not null check (like_count >= 0),
  viewer_has_liked boolean not null,
  created_at timestamptz not null default now(),
  primary key (request_id, user_id)
);

revoke all on private.community_comment_like_requests from public, anon, authenticated;
grant select, insert, delete on private.community_comment_like_requests to service_role;

create or replace function public.toggle_community_comment_like_v1(
  p_comment_id uuid,
  p_request_id uuid
)
returns table (
  comment_id uuid,
  like_count integer,
  viewer_has_liked boolean
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  current_profile_id uuid := public.current_community_profile_id();
  target_comment public.comments%rowtype;
  target_post public.posts%rowtype;
  did_like boolean;
  actor_name text;
  previous_request private.community_comment_like_requests%rowtype;
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;
  if p_request_id is null then
    raise exception 'COMMUNITY_LIKE_REQUEST_INVALID' using errcode = '22023';
  end if;
  if not public.has_accepted_community_terms(public.community_latest_terms_version()) then
    raise exception 'COMMUNITY_TERMS_REQUIRED';
  end if;

  select * into target_comment
  from public.comments
  where id = p_comment_id and status = 'published'
  for update;
  if target_comment.id is null then
    raise exception 'COMMUNITY_COMMENT_NOT_FOUND';
  end if;

  select * into previous_request
  from private.community_comment_like_requests
  where request_id = p_request_id and user_id = current_profile_id;
  if previous_request.request_id is not null then
    if previous_request.comment_id <> p_comment_id then
      raise exception 'COMMUNITY_LIKE_REQUEST_REUSED' using errcode = '22023';
    end if;
    return query
    select
      previous_request.comment_id,
      previous_request.like_count,
      previous_request.viewer_has_liked;
    return;
  end if;

  select * into target_post
  from public.posts
  where id = target_comment.post_id
    and status = 'published'
    and campus_id = public.current_profile_campus_id();
  if target_post.id is null then
    raise exception 'COMMUNITY_COMMENT_NOT_FOUND';
  end if;
  if target_comment.author_id = current_profile_id then
    raise exception 'COMMUNITY_COMMENT_SELF_LIKE_FORBIDDEN';
  end if;

  if exists (
    select 1 from public.comment_likes
    where comment_likes.comment_id = p_comment_id
      and user_id = current_profile_id
  ) then
    delete from public.comment_likes
    where comment_likes.comment_id = p_comment_id
      and user_id = current_profile_id;
    did_like := false;
  else
    insert into public.comment_likes (comment_id, user_id)
    values (p_comment_id, current_profile_id);
    did_like := true;
  end if;

  if did_like then
    select coalesce(nullif(btrim(display_name), ''), nullif(btrim(nickname), ''), '同学')
    into actor_name
    from public.profiles
    where id = current_profile_id;
    perform private.insert_community_interaction_notification_v1(
      target_comment.author_id,
      current_profile_id,
      target_comment.post_id,
      target_comment.id,
      'like',
      actor_name || ' 点赞了你的评论',
      left(target_comment.body, 120)
    );
  end if;

  insert into private.community_comment_like_requests (
    request_id, user_id, comment_id, like_count, viewer_has_liked
  )
  select
    p_request_id,
    current_profile_id,
    target_comment.id,
    comments.like_count,
    did_like
  from public.comments
  where comments.id = target_comment.id;

  return query
  select
    target_comment.id,
    comments.like_count,
    did_like
  from public.comments
  where comments.id = target_comment.id;
end;
$$;

revoke all on function public.toggle_community_comment_like_v1(uuid, uuid) from public, anon;
grant execute on function public.toggle_community_comment_like_v1(uuid, uuid) to authenticated, service_role;

create or replace function public.list_community_comment_threads_v1(
  p_post_id uuid,
  p_after_created_at timestamptz default null,
  p_after_id uuid default null,
  p_limit integer default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  current_profile_id uuid := public.current_community_profile_id();
  current_campus_id text := public.current_profile_campus_id();
  normalized_limit integer := greatest(1, least(coalesce(p_limit, 20), 50));
  result jsonb;
begin
  if current_profile_id is null or current_campus_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;
  if (p_after_created_at is null) <> (p_after_id is null) then
    raise exception 'COMMUNITY_COMMENT_CURSOR_INVALID' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.posts
    where id = p_post_id and campus_id = current_campus_id and status = 'published'
  ) then
    raise exception 'COMMUNITY_POST_NOT_FOUND';
  end if;

  with root_candidates as (
    select comments.*
    from public.comments
    where comments.post_id = p_post_id
      and comments.parent_comment_id is null
      and (
        comments.status = 'published'
        or (
          comments.status = 'deleted'
          and exists (
            select 1 from public.comments replies
            where replies.parent_comment_id = comments.id
              and replies.status = 'published'
          )
        )
      )
      and (
        p_after_created_at is null
        or (comments.created_at, comments.id) > (p_after_created_at, p_after_id)
      )
    order by comments.created_at asc, comments.id asc
    limit normalized_limit + 1
  ),
  page_roots as (
    select * from root_candidates
    order by created_at asc, id asc
    limit normalized_limit
  ),
  visible_comments as (
    select
      roots.created_at as root_created_at,
      roots.id as thread_root_id,
      comments.*,
      case when reply_target.is_anonymous then null else reply_target.author_id end
        as reply_to_author_id,
      coalesce(reply_target.status = 'published', comments.reply_to_comment_id is null)
        as reply_target_is_visible,
      exists (
        select 1 from public.comment_likes
        where comment_likes.comment_id = comments.id
          and comment_likes.user_id = current_profile_id
      ) as viewer_has_liked
    from page_roots roots
    join public.comments
      on comments.id = roots.id
      or (
        comments.parent_comment_id = roots.id
        and comments.status = 'published'
      )
    left join public.comments reply_target on reply_target.id = comments.reply_to_comment_id
  ),
  page_meta as (
    select
      exists (select 1 from root_candidates offset normalized_limit) as has_more,
      (select created_at from page_roots order by created_at desc, id desc limit 1) as next_created_at,
      (select id from page_roots order by created_at desc, id desc limit 1) as next_id
  )
  select jsonb_build_object(
    'comments',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'thread_root_id', thread_root_id,
          'id', id,
          'post_id', post_id,
          'author_id', author_id,
          'body', case when status = 'deleted' then '' else body end,
          'is_anonymous', is_anonymous,
          'status', status,
          'created_at', created_at,
          'updated_at', updated_at,
          'parent_comment_id', parent_comment_id,
          'reply_to_comment_id', reply_to_comment_id,
          'reply_to_author_id', case when reply_target_is_visible then reply_to_author_id else null end,
          'reply_target_is_visible', reply_target_is_visible,
          'like_count', like_count,
          'viewer_has_liked', viewer_has_liked,
          'is_deleted_placeholder', status = 'deleted'
        )
        order by root_created_at asc,
          case when id = thread_root_id then 0 else 1 end,
          created_at asc,
          id asc
      )
      from visible_comments
    ), '[]'::jsonb),
    'has_more', page_meta.has_more,
    'next_cursor_created_at', page_meta.next_created_at,
    'next_cursor_id', page_meta.next_id
  )
  into result
  from page_meta;

  return coalesce(result, jsonb_build_object('comments', '[]'::jsonb, 'has_more', false));
end;
$$;

revoke all on function public.list_community_comment_threads_v1(uuid, timestamptz, uuid, integer)
from public, anon;
grant execute on function public.list_community_comment_threads_v1(uuid, timestamptz, uuid, integer)
to authenticated, service_role;

alter table public.posts
  add column if not exists expected_attachment_count integer not null default 0,
  add column if not exists attachment_upload_completed_at timestamptz,
  add column if not exists media_purge_after timestamptz,
  add column if not exists media_purged_at timestamptz,
  add column if not exists media_cleanup_hold boolean not null default false;

alter table public.posts
  drop constraint if exists posts_expected_attachment_count_check;

alter table public.posts
  add constraint posts_expected_attachment_count_check
  check (expected_attachment_count between 0 and 2);

create table if not exists public.post_attachments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts (id) on delete cascade,
  path text not null unique,
  display_name text not null check (char_length(display_name) between 1 and 180),
  content_type text not null,
  file_extension text not null check (file_extension in ('pdf', 'xlsx', 'docx', 'md')),
  byte_size integer not null check (byte_size between 1 and 10485760),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  sort_order integer not null check (sort_order between 0 and 1),
  created_at timestamptz not null default now(),
  unique (post_id, sort_order)
);

create index if not exists idx_post_attachments_post
on public.post_attachments (post_id, sort_order);

alter table public.post_attachments enable row level security;

drop policy if exists "post_attachments_select_same_campus" on public.post_attachments;
create policy "post_attachments_select_same_campus"
on public.post_attachments
for select
to authenticated
using (
  exists (
    select 1 from public.posts
    where posts.id = post_attachments.post_id
      and posts.status = 'published'
      and posts.campus_id = public.current_profile_campus_id()
  )
);

revoke insert, update, delete on public.post_attachments from authenticated;
grant select on public.post_attachments to authenticated, service_role;
grant all on public.post_attachments to service_role;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'community-attachments',
  'community-attachments',
  false,
  10485760,
  array[
    'application/pdf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/markdown',
    'text/plain'
  ]::text[]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "community_attachments_insert_own_namespace" on storage.objects;
create policy "community_attachments_insert_own_namespace"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'community-attachments'
  and (storage.foldername(name))[1] = 'posts'
  and (storage.foldername(name))[2] = public.current_community_profile_id()::text
);

drop policy if exists "community_attachments_delete_own_namespace" on storage.objects;
create policy "community_attachments_delete_own_namespace"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'community-attachments'
  and (storage.foldername(name))[1] = 'posts'
  and (storage.foldername(name))[2] = public.current_community_profile_id()::text
);

create table if not exists private.community_attachment_upload_receipts (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  post_id uuid not null references public.posts (id) on delete cascade,
  object_path text not null unique,
  display_name text not null,
  content_type text not null,
  file_extension text not null,
  byte_size integer not null check (byte_size between 1 and 10485760),
  sha256 text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '10 minutes',
  consumed_at timestamptz
);

revoke all on private.community_attachment_upload_receipts from public, anon, authenticated;
grant select, insert, update on private.community_attachment_upload_receipts to service_role;

create or replace function public.edge_record_community_attachment_validation_v1(
  p_auth_user_id uuid,
  p_post_id uuid,
  p_object_path text,
  p_display_name text,
  p_content_type text,
  p_file_extension text,
  p_byte_size integer,
  p_sha256 text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_profile_id uuid;
  receipt_id uuid;
begin
  select profile_id into target_profile_id
  from public.profile_auth_links
  where auth_user_id = p_auth_user_id;

  if target_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;
  if p_file_extension not in ('pdf', 'xlsx', 'docx', 'md')
     or p_byte_size not between 1 and 10485760
     or p_sha256 !~ '^[0-9a-f]{64}$'
     or char_length(btrim(p_display_name)) not between 1 and 180 then
    raise exception 'COMMUNITY_ATTACHMENT_INVALID';
  end if;
  if not exists (
    select 1 from public.posts
    where id = p_post_id
      and author_id = target_profile_id
      and status = 'pending_review'
      and expected_attachment_count > 0
  ) then
    raise exception 'COMMUNITY_POST_NOT_FOUND';
  end if;
  if p_object_path not like
     'posts/' || target_profile_id::text || '/' || p_post_id::text || '/%' then
    raise exception 'COMMUNITY_UPLOAD_PATH_MISMATCH';
  end if;

  select id into receipt_id
  from private.community_attachment_upload_receipts
  where auth_user_id = p_auth_user_id
    and profile_id = target_profile_id
    and post_id = p_post_id
    and object_path = p_object_path
    and display_name = btrim(p_display_name)
    and content_type = p_content_type
    and file_extension = p_file_extension
    and byte_size = p_byte_size
    and sha256 = p_sha256
    and consumed_at is null
    and expires_at > now()
  limit 1;
  if receipt_id is not null then
    return receipt_id;
  end if;

  insert into private.community_attachment_upload_receipts (
    auth_user_id, profile_id, post_id, object_path, display_name,
    content_type, file_extension, byte_size, sha256
  ) values (
    p_auth_user_id, target_profile_id, p_post_id, p_object_path,
    btrim(p_display_name), p_content_type, p_file_extension, p_byte_size, p_sha256
  )
  returning id into receipt_id;
  return receipt_id;
end;
$$;

revoke all on function public.edge_record_community_attachment_validation_v1(uuid, uuid, text, text, text, text, integer, text)
from public, anon, authenticated;
grant execute on function public.edge_record_community_attachment_validation_v1(uuid, uuid, text, text, text, text, integer, text)
to service_role;

create or replace function private.try_publish_community_post_media_v1(p_post_id uuid)
returns public.posts
language plpgsql
security definer
set search_path = ''
as $$
declare
  post_record public.posts%rowtype;
  image_count integer;
  attachment_count integer;
begin
  select * into post_record
  from public.posts where id = p_post_id
  for update;

  if post_record.id is null or post_record.status <> 'pending_review' then
    return post_record;
  end if;

  select count(*)::integer into image_count
  from public.post_images where post_id = p_post_id;
  select count(*)::integer into attachment_count
  from public.post_attachments where post_id = p_post_id;

  if post_record.expected_image_count is not null
     and image_count = post_record.expected_image_count
     and attachment_count = coalesce(post_record.expected_attachment_count, 0)
     and image_count + attachment_count > 0 then
    perform set_config('leafy.community_publish_validated', 'on', true);
    update public.posts
    set
      status = 'published',
      image_upload_completed_at = case
        when image_count = coalesce(expected_image_count, image_count) then coalesce(image_upload_completed_at, now())
        else image_upload_completed_at
      end,
      attachment_upload_completed_at = case
        when attachment_count = expected_attachment_count then coalesce(attachment_upload_completed_at, now())
        else attachment_upload_completed_at
      end,
      updated_at = now()
    where id = p_post_id and status = 'pending_review'
    returning * into post_record;
  end if;
  return post_record;
end;
$$;

revoke all on function private.try_publish_community_post_media_v1(uuid)
from public, anon, authenticated;

create or replace function public.create_community_post_v4(
  p_id uuid,
  p_title text,
  p_body text,
  p_category text default null,
  p_is_anonymous boolean default false,
  p_image_count integer default 0,
  p_attachment_count integer default 0
)
returns public.posts
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  created_post public.posts%rowtype;
begin
  if p_image_count is null or p_image_count < 0 or p_image_count > 4
     or p_attachment_count is null or p_attachment_count < 0 or p_attachment_count > 2 then
    raise exception 'COMMUNITY_MEDIA_COUNT_INVALID' using errcode = '22023';
  end if;

  created_post := public.create_community_post_v2(
    p_id,
    p_title,
    p_body,
    p_category,
    p_is_anonymous,
    p_image_count + p_attachment_count > 0
  );

  update public.posts
  set
    expected_image_count = p_image_count,
    expected_attachment_count = p_attachment_count,
    image_upload_completed_at = case when p_image_count = 0 then now() else null end,
    attachment_upload_completed_at = case when p_attachment_count = 0 then now() else null end
  where id = created_post.id
  returning * into created_post;
  return created_post;
end;
$$;

revoke all on function public.create_community_post_v4(uuid, text, text, text, boolean, integer, integer)
from public, anon;
grant execute on function public.create_community_post_v4(uuid, text, text, text, boolean, integer, integer)
to authenticated, service_role;

create or replace function public.attach_community_post_attachment_v1(
  p_receipt_id uuid,
  p_attachment_id uuid,
  p_sort_order integer
)
returns public.post_attachments
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_profile_id uuid := public.current_community_profile_id();
  receipt private.community_attachment_upload_receipts%rowtype;
  post_record public.posts%rowtype;
  attachment_record public.post_attachments%rowtype;
  attached_count integer;
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;

  select * into receipt
  from private.community_attachment_upload_receipts
  where id = p_receipt_id
  for update;

  if not found
     or receipt.profile_id <> current_profile_id
     or receipt.auth_user_id <> auth.uid()
     or receipt.consumed_at is not null
     or receipt.expires_at <= now() then
    raise exception 'COMMUNITY_UPLOAD_RECEIPT_INVALID';
  end if;

  select * into post_record
  from public.posts
  where id = receipt.post_id
  for update;

  if post_record.id is null
     or post_record.author_id <> current_profile_id
     or post_record.status <> 'pending_review'
     or p_sort_order < 0
     or p_sort_order >= post_record.expected_attachment_count then
    raise exception 'COMMUNITY_ATTACHMENT_COUNT_MISMATCH';
  end if;

  insert into public.post_attachments (
    id, post_id, path, display_name, content_type, file_extension,
    byte_size, sha256, sort_order
  ) values (
    coalesce(p_attachment_id, gen_random_uuid()),
    receipt.post_id,
    receipt.object_path,
    receipt.display_name,
    receipt.content_type,
    receipt.file_extension,
    receipt.byte_size,
    receipt.sha256,
    p_sort_order
  )
  returning * into attachment_record;

  update private.community_attachment_upload_receipts
  set consumed_at = now()
  where id = receipt.id;

  select count(*)::integer into attached_count
  from public.post_attachments where post_id = receipt.post_id;
  if attached_count > post_record.expected_attachment_count then
    raise exception 'COMMUNITY_ATTACHMENT_COUNT_MISMATCH';
  end if;

  perform private.try_publish_community_post_media_v1(receipt.post_id);
  return attachment_record;
end;
$$;

revoke all on function public.attach_community_post_attachment_v1(uuid, uuid, integer)
from public, anon;
grant execute on function public.attach_community_post_attachment_v1(uuid, uuid, integer)
to authenticated, service_role;

-- Recreate the existing image attach RPC so a post with attachments cannot
-- publish as soon as its last image arrives.
create or replace function public.attach_community_post_image_v1(
  p_receipt_id uuid,
  p_image_id uuid,
  p_sort_order integer
)
returns public.post_images
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_profile_id uuid := public.current_community_profile_id();
  receipt private.community_upload_receipts%rowtype;
  post_record public.posts%rowtype;
  image_record public.post_images%rowtype;
  attached_image_count integer;
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;
  select * into receipt
  from private.community_upload_receipts
  where id = p_receipt_id
  for update;
  if not found
     or receipt.profile_id <> current_profile_id
     or receipt.auth_user_id <> auth.uid()
     or receipt.consumed_at is not null
     or receipt.expires_at <= now() then
    raise exception 'COMMUNITY_UPLOAD_RECEIPT_INVALID';
  end if;
  select * into post_record
  from public.posts where id = receipt.post_id
  for update;
  if post_record.id is null
     or post_record.author_id <> current_profile_id
     or post_record.status <> 'pending_review'
     or p_sort_order < 0
     or p_sort_order >= coalesce(post_record.expected_image_count, 0) then
    raise exception 'COMMUNITY_IMAGE_COUNT_MISMATCH';
  end if;

  insert into public.post_images (
    id, post_id, path, thumbnail_path, sort_order, width, height,
    thumbnail_width, thumbnail_height, full_width, full_height, created_at
  ) values (
    coalesce(p_image_id, gen_random_uuid()),
    receipt.post_id,
    receipt.full_path,
    receipt.thumbnail_path,
    p_sort_order,
    receipt.full_width,
    receipt.full_height,
    receipt.thumbnail_width,
    receipt.thumbnail_height,
    receipt.full_width,
    receipt.full_height,
    now()
  )
  returning * into image_record;

  update private.community_upload_receipts set consumed_at = now() where id = receipt.id;
  select count(*)::integer into attached_image_count
  from public.post_images where post_id = receipt.post_id;
  if attached_image_count > coalesce(post_record.expected_image_count, 0) then
    raise exception 'COMMUNITY_IMAGE_COUNT_MISMATCH';
  end if;
  perform private.try_publish_community_post_media_v1(receipt.post_id);
  return image_record;
end;
$$;

revoke all on function public.attach_community_post_image_v1(uuid, uuid, integer)
from public, anon;
grant execute on function public.attach_community_post_image_v1(uuid, uuid, integer)
to authenticated, service_role;

create or replace function public.publish_community_post_v1(p_post_id uuid)
returns public.posts
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_profile_id uuid := public.current_community_profile_id();
  post_record public.posts%rowtype;
  attached_image_count integer;
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;
  select * into post_record
  from public.posts
  where id = p_post_id and author_id = current_profile_id
  for update;
  if post_record.id is null then
    raise exception 'COMMUNITY_POST_NOT_FOUND';
  end if;
  if post_record.status = 'published' then
    return post_record;
  end if;
  if post_record.status <> 'pending_review' then
    raise exception 'COMMUNITY_POST_NOT_FOUND';
  end if;

  post_record := private.try_publish_community_post_media_v1(p_post_id);
  if post_record.status = 'pending_review'
     and post_record.expected_image_count is null
     and coalesce(post_record.expected_attachment_count, 0) = 0 then
    select count(*)::integer into attached_image_count
    from public.post_images
    where post_id = p_post_id;
    if attached_image_count = 0 then
      raise exception 'COMMUNITY_VALIDATED_IMAGE_REQUIRED';
    end if;
    perform set_config('leafy.community_publish_validated', 'on', true);
    update public.posts
    set
      status = 'published',
      image_upload_completed_at = now(),
      updated_at = now()
    where id = p_post_id and status = 'pending_review'
    returning * into post_record;
  end if;
  if post_record.status <> 'published' then
    raise exception 'COMMUNITY_MEDIA_COUNT_MISMATCH';
  end if;
  return post_record;
end;
$$;

revoke all on function public.publish_community_post_v1(uuid) from public, anon;
grant execute on function public.publish_community_post_v1(uuid) to authenticated, service_role;

create or replace function public.admin_retry_pending_post_publish_v1(
  p_post_id uuid,
  p_admin_id uuid
)
returns public.posts
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  post_record public.posts%rowtype;
  attached_image_count integer;
  attached_attachment_count integer;
begin
  select * into post_record
  from public.posts
  where id = p_post_id
  for update;

  if post_record.id is null then
    raise exception 'ADMIN_POST_NOT_FOUND' using errcode = 'P0001';
  end if;
  if post_record.status = 'deleted' then
    raise exception 'ADMIN_POST_DELETED' using errcode = 'P0001';
  end if;
  if post_record.status <> 'pending_review' then
    raise exception 'ADMIN_POST_NOT_PENDING' using errcode = 'P0001';
  end if;

  select count(*)::integer into attached_image_count
  from public.post_images where post_id = p_post_id;
  select count(*)::integer into attached_attachment_count
  from public.post_attachments where post_id = p_post_id;

  if attached_image_count <> coalesce(post_record.expected_image_count, attached_image_count)
     or attached_attachment_count <> post_record.expected_attachment_count
     or attached_image_count + attached_attachment_count = 0 then
    raise exception 'ADMIN_POST_MEDIA_UPLOAD_INCOMPLETE' using errcode = '23514';
  end if;

  perform set_config('leafy.community_publish_validated', 'on', true);
  update public.posts
  set
    status = 'published',
    image_upload_completed_at = coalesce(image_upload_completed_at, now()),
    attachment_upload_completed_at = coalesce(attachment_upload_completed_at, now()),
    moderated_by = p_admin_id,
    moderated_at = now(),
    moderation_reason = null,
    updated_at = now()
  where id = p_post_id
  returning * into post_record;
  return post_record;
end;
$$;

create or replace function public.abort_community_post_upload_v1(p_post_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.posts
  set status = 'deleted', media_purge_after = now(), updated_at = now()
  where id = p_post_id
    and author_id = public.current_community_profile_id()
    and status = 'pending_review';
  if not found then
    raise exception 'COMMUNITY_PENDING_POST_NOT_FOUND';
  end if;
end;
$$;

revoke all on function public.abort_community_post_upload_v1(uuid) from public, anon;
grant execute on function public.abort_community_post_upload_v1(uuid) to authenticated, service_role;

create or replace function private.set_community_media_retention()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'hidden' then
    new.media_cleanup_hold := true;
  elsif old.status = 'hidden' and new.status in ('published', 'deleted') then
    new.media_cleanup_hold := false;
  end if;

  if new.status = 'deleted' and old.status is distinct from 'deleted' then
    new.media_purge_after := coalesce(new.media_purge_after, now() + interval '30 days');
  elsif new.status = 'published' then
    new.media_purge_after := null;
  end if;
  return new;
end;
$$;

drop trigger if exists posts_set_media_retention on public.posts;
create trigger posts_set_media_retention
before update of status on public.posts
for each row execute function private.set_community_media_retention();

create extension if not exists pg_net with schema extensions;

create or replace function private.invoke_community_media_cleanup_v1()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  project_url text;
  cleanup_secret text;
  request_id bigint;
begin
  delete from private.community_comment_like_requests
  where created_at < now() - interval '7 days';

  select decrypted_secret into project_url
  from vault.decrypted_secrets
  where name = 'community_cleanup_project_url'
  limit 1;

  select decrypted_secret into cleanup_secret
  from vault.decrypted_secrets
  where name = 'community_media_cleanup_secret'
  limit 1;

  if nullif(btrim(project_url), '') is null
     or nullif(btrim(cleanup_secret), '') is null then
    raise exception 'COMMUNITY_MEDIA_CLEANUP_VAULT_SECRETS_REQUIRED';
  end if;

  select net.http_post(
    url := rtrim(project_url, '/') || '/functions/v1/community-media-cleanup',
    headers := jsonb_build_object(
      'x-cleanup-secret', cleanup_secret,
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  ) into request_id;
  return request_id;
end;
$$;

revoke all on function private.invoke_community_media_cleanup_v1()
from public, anon, authenticated;
grant execute on function private.invoke_community_media_cleanup_v1() to service_role;

do $$
begin
  if exists (
    select 1 from cron.job
    where jobname = 'leafy-community-media-cleanup'
  ) then
    perform cron.unschedule('leafy-community-media-cleanup');
  end if;
end
$$;

select cron.schedule(
  'leafy-community-media-cleanup',
  '35 18 * * *',
  $$select private.invoke_community_media_cleanup_v1();$$
);

alter function public.backend_capabilities_v1()
rename to backend_capabilities_v1_before_community_interactions;

revoke all on function public.backend_capabilities_v1_before_community_interactions()
from public, anon, authenticated;
grant execute on function public.backend_capabilities_v1_before_community_interactions()
to service_role;

create or replace function public.backend_capabilities_v1()
returns jsonb
language sql
stable
security definer
set search_path = public, private, pg_catalog
as $$
  with base as (
    select public.backend_capabilities_v1_before_community_interactions() as value
  )
  select jsonb_set(
    jsonb_set(
      jsonb_set(
        value,
        '{version}',
        '2'::jsonb
      ),
      '{features}',
      coalesce(value -> 'features', '{}'::jsonb) || jsonb_build_object(
        'community_comment_threads',
          to_regprocedure('public.list_community_comment_threads_v1(uuid,timestamptz,uuid,integer)') is not null
          and to_regprocedure('public.toggle_community_comment_like_v1(uuid,uuid)') is not null,
        'community_post_attachments',
          to_regclass('public.post_attachments') is not null
          and to_regprocedure('public.create_community_post_v4(uuid,text,text,text,boolean,integer,integer)') is not null
      )
    ),
    '{rpcs}',
    coalesce(value -> 'rpcs', '{}'::jsonb) || jsonb_build_object(
      'create_community_post_v4',
        to_regprocedure('public.create_community_post_v4(uuid,text,text,text,boolean,integer,integer)') is not null,
      'create_community_comment_v2',
        to_regprocedure('public.create_community_comment_v2(uuid,uuid,text,uuid,uuid,boolean)') is not null,
      'list_community_comment_threads_v1',
        to_regprocedure('public.list_community_comment_threads_v1(uuid,timestamptz,uuid,integer)') is not null,
      'toggle_community_comment_like_v1',
        to_regprocedure('public.toggle_community_comment_like_v1(uuid,uuid)') is not null,
      'attach_community_post_attachment_v1',
        to_regprocedure('public.attach_community_post_attachment_v1(uuid,uuid,integer)') is not null,
      'abort_community_post_upload_v1',
        to_regprocedure('public.abort_community_post_upload_v1(uuid)') is not null
    )
  )
  || jsonb_build_object(
    'edge_functions',
    coalesce(value -> 'edge_functions', '[]'::jsonb)
      || '["community-validate-attachment","community-attachment-download","community-media-cleanup"]'::jsonb
  )
  from base;
$$;

revoke all on function public.backend_capabilities_v1() from public, anon, authenticated;
grant execute on function public.backend_capabilities_v1() to anon, authenticated, service_role;

select pg_notify('pgrst', 'reload schema');
