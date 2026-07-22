alter table public.posts
  add constraint posts_title_length_v2
  check (char_length(btrim(title)) between 1 and 80) not valid,
  add constraint posts_body_length_v2
  check (char_length(btrim(body)) between 1 and 10000) not valid;

alter table public.comments
  add constraint comments_body_length_v2
  check (char_length(btrim(body)) between 1 and 2000) not valid;

alter table public.community_reports
  add constraint community_reports_detail_length_v2
  check (detail is null or char_length(btrim(detail)) between 1 and 1000) not valid;

with ranked_reports as (
  select
    id,
    row_number() over (
      partition by reporter_id, target_type,
        case when target_type = 'post' then post_id end,
        case when target_type = 'comment' then comment_id end,
        case when target_type = 'user' then reported_user_id end
      order by created_at asc, id asc
    ) as report_rank
  from public.community_reports
  where status = 'open'
)
update public.community_reports reports
set
  status = 'reviewed',
  resolved_at = coalesce(reports.resolved_at, now()),
  resolution_note = coalesce(reports.resolution_note, 'Duplicate open report consolidated during security migration')
from ranked_reports
where reports.id = ranked_reports.id
  and ranked_reports.report_rank > 1;

create unique index if not exists idx_community_reports_open_post_unique
on public.community_reports (reporter_id, post_id)
where status = 'open' and target_type = 'post';

create unique index if not exists idx_community_reports_open_comment_unique
on public.community_reports (reporter_id, comment_id)
where status = 'open' and target_type = 'comment';

create unique index if not exists idx_community_reports_open_user_unique
on public.community_reports (reporter_id, reported_user_id)
where status = 'open' and target_type = 'user';

create or replace function public.create_community_post_v2(
  p_id uuid,
  p_title text,
  p_body text,
  p_category text default null,
  p_is_anonymous boolean default false,
  p_has_images boolean default false
)
returns public.posts
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_id uuid := public.current_community_profile_id();
  current_campus_id text := public.current_profile_campus_id();
  created_post public.posts%rowtype;
begin
  if current_profile_id is null or current_campus_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
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

  insert into public.posts (
    id,
    campus_id,
    author_id,
    title,
    body,
    category,
    is_anonymous,
    comment_count,
    status,
    created_at,
    updated_at
  ) values (
    coalesce(p_id, gen_random_uuid()),
    current_campus_id,
    current_profile_id,
    btrim(coalesce(p_title, '')),
    btrim(coalesce(p_body, '')),
    nullif(btrim(coalesce(p_category, '')), ''),
    coalesce(p_is_anonymous, false),
    0,
    case when coalesce(p_has_images, false) then 'pending_review' else 'published' end,
    now(),
    now()
  )
  returning * into created_post;

  return created_post;
end;
$$;

create or replace function public.create_community_comment_v1(
  p_id uuid,
  p_post_id uuid,
  p_body text,
  p_is_anonymous boolean default false
)
returns public.comments
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_id uuid := public.current_community_profile_id();
  created_comment public.comments%rowtype;
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;

  if not exists (
    select 1 from public.profiles
    where id = current_profile_id
      and community_access_status = 'approved'
      and community_campus_id = public.current_profile_campus_id()
      and is_profile_complete = true
      and nullif(btrim(nickname), '') is not null
  ) then
    raise exception 'PROFILE_COMPLETION_REQUIRED';
  end if;

  if not public.has_accepted_community_terms(public.community_latest_terms_version()) then
    raise exception 'COMMUNITY_TERMS_REQUIRED';
  end if;

  if not exists (
    select 1 from public.posts
    where id = p_post_id
      and campus_id = public.current_profile_campus_id()
      and status = 'published'
  ) then
    raise exception 'COMMUNITY_POST_NOT_FOUND';
  end if;

  insert into public.comments (
    id,
    post_id,
    author_id,
    body,
    is_anonymous,
    status,
    created_at,
    updated_at
  ) values (
    coalesce(p_id, gen_random_uuid()),
    p_post_id,
    current_profile_id,
    btrim(coalesce(p_body, '')),
    coalesce(p_is_anonymous, false),
    'published',
    now(),
    now()
  )
  returning * into created_comment;

  return created_comment;
end;
$$;

create or replace function public.report_community_content(
  p_target_type text,
  p_post_id uuid default null,
  p_comment_id uuid default null,
  p_reported_user_id uuid default null,
  p_reason text default '违规内容',
  p_detail text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_id uuid := public.current_community_profile_id();
  target_author_id uuid;
  target_post_id uuid;
  existing_report_id uuid;
  created_report_id uuid;
  normalized_target_type text := lower(nullif(btrim(coalesce(p_target_type, '')), ''));
  normalized_reason text := coalesce(nullif(btrim(p_reason), ''), '违规内容');
  normalized_detail text := nullif(btrim(coalesce(p_detail, '')), '');
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;

  if (select count(*) from public.community_reports
      where reporter_id = current_profile_id
        and created_at >= now() - interval '24 hours') >= 20 then
    raise exception 'COMMUNITY_REPORT_RATE_LIMIT_EXCEEDED';
  end if;

  if normalized_target_type = 'post' then
    select author_id into target_author_id
    from public.posts
    where id = p_post_id and status <> 'deleted';
    target_post_id := p_post_id;
  elsif normalized_target_type = 'comment' then
    select author_id, post_id into target_author_id, target_post_id
    from public.comments
    where id = p_comment_id and status <> 'deleted';
  elsif normalized_target_type = 'user' then
    target_author_id := p_reported_user_id;
    if target_author_id is not null
       and not exists (select 1 from public.profiles where id = target_author_id) then
      target_author_id := null;
    end if;
  else
    raise exception 'COMMUNITY_INVALID_REPORT_TARGET';
  end if;

  if target_author_id is null then
    raise exception 'COMMUNITY_REPORT_TARGET_NOT_FOUND';
  end if;

  select id into existing_report_id
  from public.community_reports
  where reporter_id = current_profile_id
    and status = 'open'
    and (
      (normalized_target_type = 'post' and target_type = 'post' and post_id = p_post_id)
      or (normalized_target_type = 'comment' and target_type = 'comment' and comment_id = p_comment_id)
      or (normalized_target_type = 'user' and target_type = 'user' and reported_user_id = target_author_id)
    )
  limit 1;

  if existing_report_id is not null then
    return existing_report_id;
  end if;

  insert into public.community_reports (
    reporter_id,
    reported_user_id,
    target_type,
    post_id,
    comment_id,
    reason,
    detail,
    status
  ) values (
    current_profile_id,
    target_author_id,
    normalized_target_type,
    case when normalized_target_type in ('post', 'comment') then target_post_id else null end,
    case when normalized_target_type = 'comment' then p_comment_id else null end,
    normalized_reason,
    normalized_detail,
    'open'
  )
  returning id into created_report_id;

  return created_report_id;
end;
$$;

drop policy if exists "posts_insert_self" on public.posts;
drop policy if exists "comments_insert_self" on public.comments;

revoke insert on public.posts, public.comments, public.community_reports from authenticated;

revoke all on function public.create_community_post_v2(uuid, text, text, text, boolean, boolean) from public, anon;
revoke all on function public.create_community_comment_v1(uuid, uuid, text, boolean) from public, anon;
revoke all on function public.report_community_content(text, uuid, uuid, uuid, text, text) from public, anon;

grant execute on function public.create_community_post_v2(uuid, text, text, text, boolean, boolean) to authenticated;
grant execute on function public.create_community_comment_v1(uuid, uuid, text, boolean) to authenticated;
grant execute on function public.report_community_content(text, uuid, uuid, uuid, text, text) to authenticated;

update storage.buckets
set
  file_size_limit = 1048576,
  allowed_mime_types = array['image/jpeg']::text[]
where id = 'community-images';

select pg_notify('pgrst', 'reload schema');
