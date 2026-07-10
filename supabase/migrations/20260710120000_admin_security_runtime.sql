create extension if not exists pg_trgm with schema extensions;

create table if not exists public.admin_login_attempts (
  id uuid primary key default gen_random_uuid(),
  username text not null,
  normalized_username text generated always as (lower(btrim(username))) stored,
  ip_address inet not null,
  succeeded boolean not null default false,
  error_code text,
  attempted_at timestamptz not null default now(),
  constraint admin_login_attempts_username_not_blank
    check (nullif(btrim(username), '') is not null),
  constraint admin_login_attempts_error_code_not_blank
    check (error_code is null or nullif(btrim(error_code), '') is not null)
);

create index if not exists idx_admin_login_attempts_username_ip_recent
on public.admin_login_attempts (normalized_username, ip_address, attempted_at desc)
where succeeded = false;

create index if not exists idx_admin_login_attempts_ip_recent
on public.admin_login_attempts (ip_address, attempted_at desc)
where succeeded = false;

create index if not exists idx_admin_login_attempts_retention
on public.admin_login_attempts (attempted_at);

alter table public.admin_login_attempts enable row level security;

revoke all privileges on table public.admin_login_attempts
from public, anon, authenticated, service_role;

grant select, insert, delete on table public.admin_login_attempts
to service_role;

comment on table public.admin_login_attempts is
  'Service-role-only login attempt history used for dual 15-minute admin brute-force limits and 90-day retention.';

alter table public.admin_audit_logs
  add column if not exists request_id uuid,
  add column if not exists outcome text,
  add column if not exists duration_ms integer,
  add column if not exists error_code text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.admin_audit_logs'::regclass
      and conname = 'admin_audit_logs_outcome_check'
  ) then
    alter table public.admin_audit_logs
      add constraint admin_audit_logs_outcome_check
      check (outcome is null or outcome in ('success', 'failure'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.admin_audit_logs'::regclass
      and conname = 'admin_audit_logs_duration_ms_nonnegative'
  ) then
    alter table public.admin_audit_logs
      add constraint admin_audit_logs_duration_ms_nonnegative
      check (duration_ms is null or duration_ms >= 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.admin_audit_logs'::regclass
      and conname = 'admin_audit_logs_error_code_not_blank'
  ) then
    alter table public.admin_audit_logs
      add constraint admin_audit_logs_error_code_not_blank
      check (error_code is null or nullif(btrim(error_code), '') is not null);
  end if;
end
$$;

create index if not exists idx_admin_audit_logs_request_id
on public.admin_audit_logs (request_id)
where request_id is not null;

create index if not exists idx_admin_audit_logs_outcome_created_at
on public.admin_audit_logs (outcome, created_at desc)
where outcome is not null;

create index if not exists idx_profiles_admin_search_trgm
on public.profiles
using gin (
  (lower(
    coalesce(edu_id, '') || ' ' ||
    coalesce(nickname, '') || ' ' ||
    coalesce(display_name, '') || ' ' ||
    coalesce(bound_email, '')
  )) extensions.gin_trgm_ops
);

create index if not exists idx_posts_admin_search_trgm
on public.posts
using gin (
  (lower(
    coalesce(title, '') || ' ' ||
    coalesce(body, '') || ' ' ||
    coalesce(category, '')
  )) extensions.gin_trgm_ops
);

create index if not exists idx_posts_admin_search_fts
on public.posts
using gin (
  to_tsvector(
    'simple',
    coalesce(title, '') || ' ' || coalesce(body, '') || ' ' || coalesce(category, '')
  )
);

create index if not exists idx_teachers_admin_search_trgm
on public.teachers
using gin (search_text extensions.gin_trgm_ops);

create index if not exists idx_course_catalog_admin_search_trgm
on public.course_catalog
using gin (search_text extensions.gin_trgm_ops);

create index if not exists idx_campuses_admin_search_trgm
on public.campuses
using gin (
  (lower(
    coalesce(id, '') || ' ' ||
    coalesce(display_name, '') || ' ' ||
    coalesce(short_name, '')
  )) extensions.gin_trgm_ops
);

create index if not exists idx_site_announcements_admin_search_trgm
on public.site_announcements
using gin (
  (lower(coalesce(title, '') || ' ' || coalesce(body, ''))) extensions.gin_trgm_ops
);

create index if not exists idx_feedback_submissions_admin_search_trgm
on public.feedback_submissions
using gin (
  (lower(
    coalesce(body, '') || ' ' ||
    coalesce(contact, '') || ' ' ||
    coalesce(issue_type, '')
  )) extensions.gin_trgm_ops
);

do $$
begin
  if to_regclass('public.dish_catalog') is not null then
    execute $index$
      create index if not exists idx_dish_catalog_admin_search_trgm
      on public.dish_catalog
      using gin (search_text extensions.gin_trgm_ops)
    $index$;
  end if;
end
$$;

create or replace function public.admin_login_rate_limit_status(
  p_username text,
  p_ip_address inet,
  p_at timestamptz default now()
)
returns table (
  is_rate_limited boolean,
  username_ip_attempt_count bigint,
  ip_attempt_count bigint,
  retry_after timestamptz
)
language sql
security definer
stable
set search_path = public, pg_temp
as $$
  with normalized as (
    select
      lower(btrim(coalesce(p_username, ''))) as username,
      coalesce(p_at, now()) as checked_at
  ),
  recent_failures as (
    select attempts.normalized_username, attempts.attempted_at
    from public.admin_login_attempts as attempts
    cross join normalized
    where attempts.succeeded = false
      and attempts.ip_address = p_ip_address
      and attempts.attempted_at > normalized.checked_at - interval '15 minutes'
      and attempts.attempted_at <= normalized.checked_at
  ),
  totals as (
    select
      count(recent_failures.attempted_at)
        filter (where recent_failures.normalized_username = normalized.username) as username_ip_attempt_count,
      count(recent_failures.attempted_at) as ip_attempt_count
    from normalized
    left join recent_failures on true
    group by normalized.username
  ),
  deadlines as (
    select
      (
        select failures.attempted_at + interval '15 minutes'
        from recent_failures as failures
        cross join normalized
        where failures.normalized_username = normalized.username
        order by failures.attempted_at desc
        offset 4
        limit 1
      ) as username_ip_retry_after,
      (
        select failures.attempted_at + interval '15 minutes'
        from recent_failures as failures
        order by failures.attempted_at desc
        offset 19
        limit 1
      ) as ip_retry_after
  )
  select
    totals.username_ip_attempt_count >= 5 or totals.ip_attempt_count >= 20,
    totals.username_ip_attempt_count,
    totals.ip_attempt_count,
    case
      when totals.username_ip_attempt_count >= 5 or totals.ip_attempt_count >= 20 then
        greatest(
          case when totals.username_ip_attempt_count >= 5 then deadlines.username_ip_retry_after end,
          case when totals.ip_attempt_count >= 20 then deadlines.ip_retry_after end
        )
      else null
    end
  from totals
  cross join deadlines;
$$;

create or replace function public.admin_cleanup_login_attempts(
  p_before timestamptz default now() - interval '90 days'
)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  deleted_count bigint;
begin
  if p_before is null then
    raise exception 'ADMIN_LOGIN_ATTEMPTS_CLEANUP_BOUNDARY_REQUIRED';
  end if;

  delete from public.admin_login_attempts
  where attempted_at < p_before;

  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

create or replace function public.admin_upsert_semester_runtime_config(
  p_id uuid,
  p_campus_id text,
  p_semester_id text,
  p_semester_start_date date,
  p_supported_weeks integer,
  p_graduate_timetable_term_code text,
  p_calendar_events jsonb,
  p_is_active boolean,
  p_actor_id uuid
)
returns public.semester_runtime_configs
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  saved public.semester_runtime_configs%rowtype;
  normalized_campus_id text := nullif(btrim(coalesce(p_campus_id, '')), '');
begin
  if normalized_campus_id is null then
    raise exception 'ADMIN_CAMPUS_ID_REQUIRED';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('leafy.semester-runtime:' || normalized_campus_id, 0)
  );
  perform set_config('leafy.semester_reconcile_running', 'true', true);

  if p_id is null then
    insert into public.semester_runtime_configs (
      campus_id,
      semester_id,
      semester_start_date,
      supported_weeks,
      graduate_timetable_term_code,
      calendar_events,
      is_active,
      created_by,
      updated_by
    )
    values (
      normalized_campus_id,
      p_semester_id,
      p_semester_start_date,
      p_supported_weeks,
      p_graduate_timetable_term_code,
      coalesce(p_calendar_events, '[]'::jsonb),
      false,
      p_actor_id,
      p_actor_id
    )
    on conflict (campus_id, semester_id) do update
    set
      semester_start_date = excluded.semester_start_date,
      supported_weeks = excluded.supported_weeks,
      graduate_timetable_term_code = excluded.graduate_timetable_term_code,
      calendar_events = excluded.calendar_events,
      is_active = false,
      updated_by = excluded.updated_by
    returning * into saved;
  else
    update public.semester_runtime_configs as configs
    set
      semester_id = p_semester_id,
      semester_start_date = p_semester_start_date,
      supported_weeks = p_supported_weeks,
      graduate_timetable_term_code = p_graduate_timetable_term_code,
      calendar_events = coalesce(p_calendar_events, '[]'::jsonb),
      is_active = false,
      updated_by = p_actor_id
    where configs.id = p_id
      and configs.campus_id = normalized_campus_id
    returning configs.* into saved;

    if saved.id is null then
      raise exception 'ADMIN_SEMESTER_RUNTIME_CONFIG_NOT_FOUND';
    end if;
  end if;

  if coalesce(p_is_active, false)
     and saved.semester_start_date <= public.leafy_semester_effective_date() then
    update public.semester_runtime_configs as configs
    set
      is_active = false,
      updated_by = p_actor_id
    where configs.campus_id = normalized_campus_id
      and configs.is_active = true
      and configs.id <> saved.id;

    update public.semester_runtime_configs as configs
    set
      is_active = true,
      updated_by = p_actor_id
    where configs.id = saved.id
    returning configs.* into saved;
  else
    perform public.reconcile_semester_runtime_active_config(normalized_campus_id, null);

    select configs.*
    into saved
    from public.semester_runtime_configs as configs
    where configs.id = saved.id;
  end if;

  perform set_config('leafy.semester_reconcile_running', 'false', true);
  return saved;
exception
  when others then
    perform set_config('leafy.semester_reconcile_running', 'false', true);
    raise;
end;
$$;

create or replace function public.admin_upsert_national_calendar_runtime_config(
  p_id uuid,
  p_year integer,
  p_holidays jsonb,
  p_solar_terms jsonb,
  p_is_active boolean,
  p_actor_id uuid
)
returns public.national_calendar_runtime_configs
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  saved public.national_calendar_runtime_configs%rowtype;
begin
  perform pg_advisory_xact_lock(
    hashtextextended('leafy.national-calendar-runtime', 0)
  );

  if p_id is null then
    insert into public.national_calendar_runtime_configs (
      year,
      holidays,
      solar_terms,
      is_active,
      created_by,
      updated_by
    )
    values (
      p_year,
      coalesce(p_holidays, '[]'::jsonb),
      coalesce(p_solar_terms, '[]'::jsonb),
      false,
      p_actor_id,
      p_actor_id
    )
    on conflict (year) do update
    set
      holidays = excluded.holidays,
      solar_terms = excluded.solar_terms,
      is_active = false,
      updated_by = excluded.updated_by
    returning * into saved;
  else
    update public.national_calendar_runtime_configs as configs
    set
      year = p_year,
      holidays = coalesce(p_holidays, '[]'::jsonb),
      solar_terms = coalesce(p_solar_terms, '[]'::jsonb),
      is_active = false,
      updated_by = p_actor_id
    where configs.id = p_id
    returning configs.* into saved;

    if saved.id is null then
      raise exception 'ADMIN_NATIONAL_CALENDAR_RUNTIME_CONFIG_NOT_FOUND';
    end if;
  end if;

  if coalesce(p_is_active, false) then
    update public.national_calendar_runtime_configs as configs
    set
      is_active = false,
      updated_by = p_actor_id
    where configs.is_active = true
      and configs.id <> saved.id;

    update public.national_calendar_runtime_configs as configs
    set
      is_active = true,
      updated_by = p_actor_id
    where configs.id = saved.id
    returning configs.* into saved;
  end if;

  return saved;
end;
$$;

revoke all on function public.admin_login_rate_limit_status(text, inet, timestamptz)
from public, anon, authenticated, service_role;
revoke all on function public.admin_cleanup_login_attempts(timestamptz)
from public, anon, authenticated, service_role;
revoke all on function public.admin_upsert_semester_runtime_config(uuid, text, text, date, integer, text, jsonb, boolean, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.admin_upsert_national_calendar_runtime_config(uuid, integer, jsonb, jsonb, boolean, uuid)
from public, anon, authenticated, service_role;

grant execute on function public.admin_login_rate_limit_status(text, inet, timestamptz)
to service_role;
grant execute on function public.admin_cleanup_login_attempts(timestamptz)
to service_role;
grant execute on function public.admin_upsert_semester_runtime_config(uuid, text, text, date, integer, text, jsonb, boolean, uuid)
to service_role;
grant execute on function public.admin_upsert_national_calendar_runtime_config(uuid, integer, jsonb, jsonb, boolean, uuid)
to service_role;

do $$
begin
  if exists (
    select 1
    from cron.job
    where jobname = 'leafy-admin-login-attempts-retention'
  ) then
    perform cron.unschedule('leafy-admin-login-attempts-retention');
  end if;
end
$$;

select cron.schedule(
  'leafy-admin-login-attempts-retention',
  '20 17 * * *',
  $$select public.admin_cleanup_login_attempts();$$
);

select pg_notify('pgrst', 'reload schema');
