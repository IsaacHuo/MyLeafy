alter table public.posts
  add column if not exists expected_image_count integer,
  add column if not exists image_upload_completed_at timestamptz;

alter table public.posts
  drop constraint if exists posts_expected_image_count_check;

alter table public.posts
  add constraint posts_expected_image_count_check
  check (expected_image_count is null or expected_image_count between 0 and 9);

update public.posts posts
set
  expected_image_count = image_counts.image_count,
  image_upload_completed_at = coalesce(posts.image_upload_completed_at, posts.updated_at)
from (
  select post_id, count(*)::integer as image_count
  from public.post_images
  group by post_id
) image_counts
where posts.id = image_counts.post_id
  and posts.status <> 'pending_review'
  and posts.expected_image_count is null;

update public.posts
set expected_image_count = 0
where expected_image_count is null
  and status <> 'pending_review'
  and not exists (
    select 1 from public.post_images
    where post_images.post_id = posts.id
  );

create index if not exists idx_posts_pending_image_upload
on public.posts (created_at asc)
where status = 'pending_review';

create or replace function public.create_community_post_v3(
  p_id uuid,
  p_title text,
  p_body text,
  p_category text default null,
  p_is_anonymous boolean default false,
  p_image_count integer default 0
)
returns public.posts
language plpgsql
security definer
set search_path = public
as $$
declare
  created_post public.posts%rowtype;
begin
  if p_image_count is null or p_image_count < 0 or p_image_count > 9 then
    raise exception 'COMMUNITY_IMAGE_COUNT_INVALID' using errcode = '22023';
  end if;

  created_post := public.create_community_post_v2(
    p_id,
    p_title,
    p_body,
    p_category,
    p_is_anonymous,
    p_image_count > 0
  );

  update public.posts
  set
    expected_image_count = p_image_count,
    image_upload_completed_at = case when p_image_count = 0 then now() else null end
  where id = created_post.id
  returning * into created_post;

  return created_post;
end;
$$;

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
  from public.posts
  where id = receipt.post_id
  for update;

  if post_record.id is null
     or post_record.author_id <> current_profile_id
     or post_record.status <> 'pending_review' then
    raise exception 'COMMUNITY_POST_NOT_FOUND';
  end if;

  if post_record.expected_image_count is not null
     and (p_sort_order < 0 or p_sort_order >= post_record.expected_image_count) then
    raise exception 'COMMUNITY_IMAGE_COUNT_MISMATCH' using errcode = '22023';
  end if;

  insert into public.post_images (
    id,
    post_id,
    path,
    thumbnail_path,
    sort_order,
    width,
    height,
    thumbnail_width,
    thumbnail_height,
    full_width,
    full_height,
    created_at
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

  update private.community_upload_receipts
  set consumed_at = now()
  where id = receipt.id;

  select count(*)::integer into attached_image_count
  from public.post_images
  where post_id = receipt.post_id;

  if post_record.expected_image_count is not null then
    if attached_image_count > post_record.expected_image_count then
      raise exception 'COMMUNITY_IMAGE_COUNT_MISMATCH' using errcode = '22023';
    end if;

    if attached_image_count = post_record.expected_image_count then
      perform set_config('leafy.community_publish_validated', 'on', true);
      update public.posts
      set
        status = 'published',
        image_upload_completed_at = now(),
        updated_at = now()
      where id = receipt.post_id
        and status = 'pending_review';
    end if;
  end if;

  return image_record;
end;
$$;

create or replace function public.publish_community_post_v1(p_post_id uuid)
returns public.posts
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_profile_id uuid := public.current_community_profile_id();
  current_post public.posts%rowtype;
  published_post public.posts%rowtype;
  attached_image_count integer;
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;

  select * into current_post
  from public.posts
  where id = p_post_id
    and author_id = current_profile_id
  for update;

  if current_post.id is null then
    raise exception 'COMMUNITY_POST_NOT_FOUND';
  end if;

  if current_post.status = 'published' then
    return current_post;
  end if;

  if current_post.status <> 'pending_review' then
    raise exception 'COMMUNITY_POST_NOT_FOUND';
  end if;

  select count(*)::integer into attached_image_count
  from public.post_images
  where post_id = p_post_id;

  if attached_image_count = 0 then
    raise exception 'COMMUNITY_VALIDATED_IMAGE_REQUIRED';
  end if;

  if current_post.expected_image_count is not null
     and attached_image_count <> current_post.expected_image_count then
    raise exception 'COMMUNITY_IMAGE_COUNT_MISMATCH';
  end if;

  perform set_config('leafy.community_publish_validated', 'on', true);
  update public.posts
  set
    status = 'published',
    image_upload_completed_at = now(),
    updated_at = now()
  where id = p_post_id
    and status = 'pending_review'
  returning * into published_post;

  if published_post.id is null then
    raise exception 'COMMUNITY_POST_NOT_FOUND';
  end if;
  return published_post;
end;
$$;

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
  from public.post_images
  where post_id = p_post_id;

  if attached_image_count = 0 then
    raise exception 'ADMIN_POST_IMAGE_UPLOAD_INCOMPLETE' using errcode = '23514';
  end if;
  if post_record.expected_image_count is not null
     and attached_image_count <> post_record.expected_image_count then
    raise exception 'ADMIN_POST_IMAGE_UPLOAD_INCOMPLETE' using errcode = '23514';
  end if;

  update public.posts
  set
    status = 'published',
    image_upload_completed_at = now(),
    moderated_by = p_admin_id,
    moderated_at = now(),
    moderation_reason = null,
    updated_at = now()
  where id = p_post_id
  returning * into post_record;

  return post_record;
end;
$$;

create or replace function public.admin_moderate_posts_v1(
  p_post_ids uuid[],
  p_status text,
  p_reason text,
  p_admin_id uuid
)
returns setof public.posts
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_status not in ('published', 'hidden') then
    raise exception 'ADMIN_INVALID_POST_STATUS' using errcode = '22023';
  end if;
  if cardinality(p_post_ids) = 1 then
    if not exists (select 1 from public.posts where id = p_post_ids[1]) then
      raise exception 'ADMIN_POST_NOT_FOUND' using errcode = 'P0001';
    end if;
    if exists (select 1 from public.posts where id = p_post_ids[1] and status = 'deleted') then
      raise exception 'ADMIN_POST_DELETED' using errcode = 'P0001';
    end if;
  end if;
  if p_status = 'published'
     and exists (
       select 1 from public.posts
       where id = any(p_post_ids) and status = 'pending_review'
     ) then
    raise exception 'ADMIN_PENDING_POST_REQUIRES_RETRY' using errcode = '23514';
  end if;
  if p_status = 'hidden' then
    update public.community_post_pins
    set status = 'inactive'
    where post_id = any(p_post_ids)
      and status = 'active';
  end if;
  return query update public.posts
  set
    status = p_status,
    moderated_by = p_admin_id,
    moderated_at = now(),
    moderation_reason = case
      when p_status = 'hidden' then coalesce(nullif(btrim(p_reason), ''), 'Hidden by admin')
      else null
    end
  where id = any(p_post_ids)
    and status <> 'deleted'
  returning *;
end;
$$;

alter function public.backend_capabilities_v1() set schema private;
alter function private.backend_capabilities_v1() rename to backend_capabilities_base_v1;
revoke all on function private.backend_capabilities_base_v1() from public, anon, authenticated;

create function public.backend_capabilities_v1()
returns jsonb
language sql
stable
security definer
set search_path = public, private, pg_catalog
as $$
  select jsonb_set(
    private.backend_capabilities_base_v1(),
    '{rpcs}',
    coalesce(private.backend_capabilities_base_v1() -> 'rpcs', '{}'::jsonb)
      || jsonb_build_object(
        'create_community_post_v3',
          to_regprocedure('public.create_community_post_v3(uuid,text,text,text,boolean,integer)') is not null,
        'attach_community_post_image_v1',
          to_regprocedure('public.attach_community_post_image_v1(uuid,uuid,integer)') is not null,
        'publish_community_post_v1',
          to_regprocedure('public.publish_community_post_v1(uuid)') is not null
      )
  );
$$;

revoke all on function public.backend_capabilities_v1() from public, anon, authenticated;
grant execute on function public.backend_capabilities_v1() to anon, authenticated, service_role;

revoke all on function public.create_community_post_v3(uuid, text, text, text, boolean, integer)
  from public, anon;
grant execute on function public.create_community_post_v3(uuid, text, text, text, boolean, integer)
  to authenticated;

revoke all on function public.admin_retry_pending_post_publish_v1(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.admin_retry_pending_post_publish_v1(uuid, uuid)
  to service_role;

select pg_notify('pgrst', 'reload schema');
