-- A generated value keeps historical and future identities under one server-owned rule.
alter table public.profiles add column is_demo boolean generated always as (
  lower(btrim(coalesce(edu_id, ''))) = 'review-demo'
  or lower(btrim(coalesce(edu_id, ''))) like 'review-demo-%'
) stored;
comment on column public.profiles.is_demo is
  'Installation and legacy review demos remain usable but are excluded from operational user metrics.';

create or replace function public.admin_daily_counts(
  p_days integer default 30,
  p_timezone text default 'UTC',
  p_campus_id text default null
)
returns table (
  bucket_date date,
  profiles integer,
  posts integer,
  comments integer,
  feedback integer,
  ratings integer
)
language sql
security definer
stable
set search_path = public
as $$
  with bounds as (
    select
      least(greatest(coalesce(p_days, 30), 1), 90)::integer as days,
      coalesce(nullif(btrim(p_timezone), ''), 'UTC') as zone,
      lower(nullif(btrim(p_campus_id), '')) as campus_id
  ),
  buckets as (
    select generate_series(
      ((now() at time zone bounds.zone)::date - (bounds.days - 1)),
      (now() at time zone bounds.zone)::date,
      interval '1 day'
    )::date as bucket_date
    from bounds
  ),
  profile_counts as (
    select (profiles.created_at at time zone bounds.zone)::date as bucket_date, count(*)::integer as total
    from public.profiles, bounds
    where not profiles.is_demo and (profiles.created_at at time zone bounds.zone)::date >= ((now() at time zone bounds.zone)::date - (bounds.days - 1))
      and (bounds.campus_id is null or profiles.community_campus_id = bounds.campus_id)
    group by 1
  ),
  post_counts as (
    select (posts.created_at at time zone bounds.zone)::date as bucket_date, count(*)::integer as total
    from public.posts, bounds
    where (posts.created_at at time zone bounds.zone)::date >= ((now() at time zone bounds.zone)::date - (bounds.days - 1))
      and (bounds.campus_id is null or posts.campus_id = bounds.campus_id)
    group by 1
  ),
  comment_counts as (
    select (comments.created_at at time zone bounds.zone)::date as bucket_date, count(*)::integer as total
    from public.comments
    join public.posts on posts.id = comments.post_id,
    bounds
    where (comments.created_at at time zone bounds.zone)::date >= ((now() at time zone bounds.zone)::date - (bounds.days - 1))
      and (bounds.campus_id is null or posts.campus_id = bounds.campus_id)
    group by 1
  ),
  feedback_counts as (
    select (feedback_submissions.created_at at time zone bounds.zone)::date as bucket_date, count(*)::integer as total
    from public.feedback_submissions, bounds
    where (feedback_submissions.created_at at time zone bounds.zone)::date >= ((now() at time zone bounds.zone)::date - (bounds.days - 1))
      and (bounds.campus_id is null or feedback_submissions.campus_id = bounds.campus_id)
    group by 1
  ),
  rating_counts as (
    select (teacher_ratings.created_at at time zone bounds.zone)::date as bucket_date, count(*)::integer as total
    from public.teacher_ratings
    join public.teachers on teachers.id = teacher_ratings.teacher_id,
    bounds
    where (teacher_ratings.created_at at time zone bounds.zone)::date >= ((now() at time zone bounds.zone)::date - (bounds.days - 1))
      and (bounds.campus_id is null or teachers.campus_id = bounds.campus_id)
    group by 1
  )
  select
    buckets.bucket_date,
    coalesce(profile_counts.total, 0),
    coalesce(post_counts.total, 0),
    coalesce(comment_counts.total, 0),
    coalesce(feedback_counts.total, 0),
    coalesce(rating_counts.total, 0)
  from buckets
  left join profile_counts using (bucket_date)
  left join post_counts using (bucket_date)
  left join comment_counts using (bucket_date)
  left join feedback_counts using (bucket_date)
  left join rating_counts using (bucket_date)
  order by buckets.bucket_date asc;
$$;

revoke all on function public.admin_daily_counts(integer, text, text) from public, authenticated;
grant execute on function public.admin_daily_counts(integer, text, text) to service_role;
