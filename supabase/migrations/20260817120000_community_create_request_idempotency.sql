-- Make post and comment creation safely replayable without changing the media
-- receipt lifecycle. Existing RPC signatures remain available to shipped apps.

create table private.community_create_requests (
  actor_id uuid not null references public.profiles (id) on delete cascade,
  request_id uuid not null,
  mutation_kind text not null check (mutation_kind in ('post', 'comment')),
  resource_id uuid not null,
  request_payload jsonb not null,
  created_at timestamptz not null default now(),
  primary key (actor_id, request_id)
);

create unique index community_create_requests_resource_unique
on private.community_create_requests (mutation_kind, resource_id);

revoke all on private.community_create_requests from public, anon, authenticated;
grant select, insert, delete on private.community_create_requests to service_role;

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
  current_profile_id uuid := public.current_community_profile_id();
  created_post public.posts%rowtype;
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;
  if p_id is null then
    raise exception 'COMMUNITY_POST_REQUEST_INVALID' using errcode = '22023';
  end if;
  if p_image_count is null or p_image_count < 0 or p_image_count > 4
     or p_attachment_count is null or p_attachment_count < 0 or p_attachment_count > 2 then
    raise exception 'COMMUNITY_MEDIA_COUNT_INVALID' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(current_profile_id::text || ':post:' || p_id::text, 0));

  select * into created_post
  from public.posts
  where id = p_id;

  if created_post.id is not null then
    if created_post.author_id <> current_profile_id
       or created_post.title <> btrim(coalesce(p_title, ''))
       or created_post.body <> btrim(coalesce(p_body, ''))
       or created_post.category is distinct from nullif(btrim(coalesce(p_category, '')), '')
       or created_post.is_anonymous <> coalesce(p_is_anonymous, false)
       or created_post.expected_image_count is distinct from p_image_count
       or coalesce(created_post.expected_attachment_count, 0) <> p_attachment_count then
      raise exception 'COMMUNITY_POST_REQUEST_REUSED' using errcode = '22023';
    end if;
    return created_post;
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

create function public.create_community_post_v4(
  p_id uuid,
  p_title text,
  p_body text,
  p_category text,
  p_is_anonymous boolean,
  p_image_count integer,
  p_attachment_count integer,
  p_request_id uuid
)
returns public.posts
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  current_profile_id uuid := public.current_community_profile_id();
  request_payload jsonb;
  previous_request private.community_create_requests%rowtype;
  created_post public.posts%rowtype;
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;
  if p_request_id is null then
    raise exception 'COMMUNITY_POST_REQUEST_INVALID' using errcode = '22023';
  end if;

  request_payload := jsonb_build_object(
    'post_id', p_id,
    'title', btrim(coalesce(p_title, '')),
    'body', btrim(coalesce(p_body, '')),
    'category', nullif(btrim(coalesce(p_category, '')), ''),
    'is_anonymous', coalesce(p_is_anonymous, false),
    'image_count', p_image_count,
    'attachment_count', p_attachment_count
  );
  perform pg_advisory_xact_lock(hashtextextended(current_profile_id::text || ':request:' || p_request_id::text, 0));

  select * into previous_request
  from private.community_create_requests
  where actor_id = current_profile_id and request_id = p_request_id;

  if previous_request.request_id is not null then
    if previous_request.mutation_kind <> 'post'
       or previous_request.request_payload <> request_payload then
      raise exception 'COMMUNITY_CREATE_REQUEST_REUSED' using errcode = '22023';
    end if;
    select * into created_post from public.posts where id = previous_request.resource_id;
    if created_post.id is null then
      raise exception 'COMMUNITY_CREATE_REQUEST_RESULT_MISSING';
    end if;
    return created_post;
  end if;

  created_post := public.create_community_post_v4(
    p_id, p_title, p_body, p_category, p_is_anonymous,
    p_image_count, p_attachment_count
  );
  insert into private.community_create_requests (
    actor_id, request_id, mutation_kind, resource_id, request_payload
  ) values (
    current_profile_id, p_request_id, 'post', created_post.id, request_payload
  );
  return created_post;
end;
$$;

create function public.create_community_comment_v2(
  p_id uuid,
  p_post_id uuid,
  p_body text,
  p_parent_comment_id uuid,
  p_reply_to_comment_id uuid,
  p_is_anonymous boolean,
  p_request_id uuid
)
returns public.comments
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  current_profile_id uuid := public.current_community_profile_id();
  request_payload jsonb;
  previous_request private.community_create_requests%rowtype;
  created_comment public.comments%rowtype;
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;
  if p_request_id is null then
    raise exception 'COMMUNITY_COMMENT_REQUEST_INVALID' using errcode = '22023';
  end if;

  request_payload := jsonb_build_object(
    'post_id', p_post_id,
    'body', btrim(coalesce(p_body, '')),
    'parent_comment_id', p_parent_comment_id,
    'reply_to_comment_id', p_reply_to_comment_id,
    'is_anonymous', coalesce(p_is_anonymous, false)
  );
  perform pg_advisory_xact_lock(hashtextextended(current_profile_id::text || ':request:' || p_request_id::text, 0));

  select * into previous_request
  from private.community_create_requests
  where actor_id = current_profile_id and request_id = p_request_id;

  if previous_request.request_id is not null then
    if previous_request.mutation_kind <> 'comment'
       or previous_request.request_payload <> request_payload then
      raise exception 'COMMUNITY_CREATE_REQUEST_REUSED' using errcode = '22023';
    end if;
    select * into created_comment from public.comments where id = previous_request.resource_id;
    if created_comment.id is null then
      raise exception 'COMMUNITY_CREATE_REQUEST_RESULT_MISSING';
    end if;
    return created_comment;
  end if;

  created_comment := public.create_community_comment_v2(
    p_id, p_post_id, p_body, p_parent_comment_id,
    p_reply_to_comment_id, p_is_anonymous
  );
  insert into private.community_create_requests (
    actor_id, request_id, mutation_kind, resource_id, request_payload
  ) values (
    current_profile_id, p_request_id, 'comment', created_comment.id, request_payload
  );
  return created_comment;
end;
$$;

revoke all on function public.create_community_post_v4(uuid, text, text, text, boolean, integer, integer, uuid)
from public, anon;
grant execute on function public.create_community_post_v4(uuid, text, text, text, boolean, integer, integer, uuid)
to authenticated, service_role;

revoke all on function public.create_community_comment_v2(uuid, uuid, text, uuid, uuid, boolean, uuid)
from public, anon;
grant execute on function public.create_community_comment_v2(uuid, uuid, text, uuid, uuid, boolean, uuid)
to authenticated, service_role;

alter function public.backend_capabilities_v1()
  rename to backend_capabilities_v1_before_community_create_idempotency;

revoke all on function public.backend_capabilities_v1_before_community_create_idempotency()
from public, anon, authenticated;
grant execute on function public.backend_capabilities_v1_before_community_create_idempotency()
to service_role;

create function public.backend_capabilities_v1()
returns jsonb
language sql
stable
security definer
set search_path = public, private, pg_catalog
as $$
  with base as (
    select public.backend_capabilities_v1_before_community_create_idempotency() as value
  )
  select jsonb_set(
    jsonb_set(value, '{version}', '7'::jsonb),
    '{rpcs}',
    coalesce(value -> 'rpcs', '{}'::jsonb) || jsonb_build_object(
      'create_community_post_v4_idempotent',
        to_regprocedure('public.create_community_post_v4(uuid,text,text,text,boolean,integer,integer,uuid)') is not null,
      'create_community_comment_v2_idempotent',
        to_regprocedure('public.create_community_comment_v2(uuid,uuid,text,uuid,uuid,boolean,uuid)') is not null
    )
  )
  from base;
$$;

revoke all on function public.backend_capabilities_v1() from public, anon, authenticated;
grant execute on function public.backend_capabilities_v1() to anon, authenticated, service_role;

comment on function public.backend_capabilities_v1()
is 'Returns backend capability manifest version 7, including idempotent community create RPC overloads.';

select pg_notify('pgrst', 'reload schema');
