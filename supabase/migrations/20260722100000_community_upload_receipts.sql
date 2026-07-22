create table if not exists private.community_upload_receipts (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  post_id uuid not null references public.posts (id) on delete cascade,
  full_path text not null unique,
  thumbnail_path text not null unique,
  full_sha256 text not null,
  thumbnail_sha256 text not null,
  full_size integer not null check (full_size between 1 and 1048576),
  thumbnail_size integer not null check (thumbnail_size between 1 and 1048576),
  full_width integer not null check (full_width between 1 and 1600),
  full_height integer not null check (full_height between 1 and 1600),
  thumbnail_width integer not null check (thumbnail_width between 1 and 480),
  thumbnail_height integer not null check (thumbnail_height between 1 and 480),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '10 minutes',
  consumed_at timestamptz
);

revoke all on table private.community_upload_receipts from public, anon, authenticated;
grant select, insert, update on table private.community_upload_receipts to service_role;

create or replace function public.edge_record_community_upload_validation(
  p_auth_user_id uuid,
  p_post_id uuid,
  p_full_path text,
  p_thumbnail_path text,
  p_full_sha256 text,
  p_thumbnail_sha256 text,
  p_full_size integer,
  p_thumbnail_size integer,
  p_full_width integer,
  p_full_height integer,
  p_thumbnail_width integer,
  p_thumbnail_height integer
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

  if not exists (
    select 1 from public.posts
    where id = p_post_id
      and author_id = target_profile_id
      and status = 'pending_review'
  ) then
    raise exception 'COMMUNITY_POST_NOT_FOUND';
  end if;

  if p_full_path not like 'posts/' || target_profile_id::text || '/' || p_post_id::text || '/full/%'
     or p_thumbnail_path not like 'posts/' || target_profile_id::text || '/' || p_post_id::text || '/thumb/%' then
    raise exception 'COMMUNITY_UPLOAD_PATH_MISMATCH';
  end if;

  insert into private.community_upload_receipts (
    auth_user_id,
    profile_id,
    post_id,
    full_path,
    thumbnail_path,
    full_sha256,
    thumbnail_sha256,
    full_size,
    thumbnail_size,
    full_width,
    full_height,
    thumbnail_width,
    thumbnail_height
  ) values (
    p_auth_user_id,
    target_profile_id,
    p_post_id,
    p_full_path,
    p_thumbnail_path,
    p_full_sha256,
    p_thumbnail_sha256,
    p_full_size,
    p_thumbnail_size,
    p_full_width,
    p_full_height,
    p_thumbnail_width,
    p_thumbnail_height
  )
  returning id into receipt_id;

  return receipt_id;
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
  image_record public.post_images%rowtype;
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
  published_post public.posts%rowtype;
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;

  if not exists (
    select 1 from public.post_images
    where post_id = p_post_id
  ) then
    raise exception 'COMMUNITY_VALIDATED_IMAGE_REQUIRED';
  end if;

  perform set_config('leafy.community_publish_validated', 'on', true);
  update public.posts
  set status = 'published', updated_at = now()
  where id = p_post_id
    and author_id = current_profile_id
    and status = 'pending_review'
  returning * into published_post;

  if published_post.id is null then
    raise exception 'COMMUNITY_POST_NOT_FOUND';
  end if;
  return published_post;
end;
$$;

create or replace function private.guard_community_post_status_transition()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  if auth.role() = 'service_role' then
    return new;
  end if;

  if new.status = 'deleted' then
    return new;
  end if;

  if old.status = 'pending_review'
     and new.status = 'published'
     and current_setting('leafy.community_publish_validated', true) = 'on' then
    return new;
  end if;

  raise exception 'COMMUNITY_POST_STATUS_TRANSITION_FORBIDDEN';
end;
$$;

drop trigger if exists community_posts_guard_status_transition on public.posts;
create trigger community_posts_guard_status_transition
before update of status on public.posts
for each row
execute function private.guard_community_post_status_transition();

drop trigger if exists post_images_publish_post_after_insert on public.post_images;

revoke insert on public.post_images from authenticated;
revoke all on function public.edge_record_community_upload_validation(uuid, uuid, text, text, text, text, integer, integer, integer, integer, integer, integer)
  from public, anon, authenticated;
grant execute on function public.edge_record_community_upload_validation(uuid, uuid, text, text, text, text, integer, integer, integer, integer, integer, integer)
  to service_role;

revoke all on function public.attach_community_post_image_v1(uuid, uuid, integer) from public, anon;
grant execute on function public.attach_community_post_image_v1(uuid, uuid, integer) to authenticated;
revoke all on function public.publish_community_post_v1(uuid) from public, anon;
grant execute on function public.publish_community_post_v1(uuid) to authenticated;

select pg_notify('pgrst', 'reload schema');
