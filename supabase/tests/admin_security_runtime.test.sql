begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(52);

select ok(
  to_regclass('public.admin_login_attempts') is not null,
  'admin_login_attempts exists'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.admin_login_attempts'::regclass),
  'admin_login_attempts has RLS enabled'
);

select ok(
  has_table_privilege('service_role', 'public.admin_login_attempts', 'SELECT')
    and has_table_privilege('service_role', 'public.admin_login_attempts', 'INSERT')
    and has_table_privilege('service_role', 'public.admin_login_attempts', 'UPDATE')
    and has_table_privilege('service_role', 'public.admin_login_attempts', 'DELETE'),
  'service_role can query, record, and clean login attempts'
);

select ok(
  not has_table_privilege('anon', 'public.admin_login_attempts', 'SELECT')
    and not has_table_privilege('anon', 'public.admin_login_attempts', 'INSERT')
    and not has_table_privilege('anon', 'public.admin_login_attempts', 'UPDATE')
    and not has_table_privilege('anon', 'public.admin_login_attempts', 'DELETE'),
  'anon has no login-attempt table privileges'
);

select ok(
  not has_table_privilege('authenticated', 'public.admin_login_attempts', 'SELECT')
    and not has_table_privilege('authenticated', 'public.admin_login_attempts', 'INSERT')
    and not has_table_privilege('authenticated', 'public.admin_login_attempts', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.admin_login_attempts', 'DELETE'),
  'authenticated has no login-attempt table privileges'
);

select ok(
  not exists (
    select 1
    from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name = 'admin_login_attempts'
      and grantee = 'PUBLIC'
  ),
  'PUBLIC has no login-attempt table privileges'
);

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'admin_audit_logs' and column_name = 'request_id'
  ),
  'admin_audit_logs has request_id'
);

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'admin_audit_logs' and column_name = 'outcome'
  ),
  'admin_audit_logs has outcome'
);

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'admin_audit_logs' and column_name = 'duration_ms'
  ),
  'admin_audit_logs has duration_ms'
);

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'admin_audit_logs' and column_name = 'error_code'
  ),
  'admin_audit_logs has error_code'
);

select ok(
  to_regprocedure('public.admin_login_rate_limit_status(text,inet,timestamp with time zone)') is not null,
  'login rate-limit status function exists'
);

select ok(
  to_regprocedure('public.admin_cleanup_login_attempts(timestamp with time zone)') is not null,
  'login-attempt cleanup function exists'
);

select ok(
  to_regprocedure('public.admin_begin_login_attempt(text,inet,timestamp with time zone)') is not null,
  'atomic login-attempt begin function exists'
);

select ok(
  to_regprocedure('public.admin_finish_login_attempt(uuid,boolean,text)') is not null,
  'login-attempt finish function exists'
);

select ok(
  to_regprocedure('public.admin_upsert_semester_runtime_config(uuid,text,text,date,integer,text,jsonb,boolean,uuid)') is not null,
  'semester runtime upsert function exists'
);

select ok(
  to_regprocedure('public.admin_upsert_national_calendar_runtime_config(uuid,integer,jsonb,jsonb,boolean,uuid)') is not null,
  'national-calendar runtime upsert function exists'
);

select ok(
  has_function_privilege('service_role', 'public.admin_login_rate_limit_status(text,inet,timestamp with time zone)', 'EXECUTE')
    and has_function_privilege('service_role', 'public.admin_cleanup_login_attempts(timestamp with time zone)', 'EXECUTE')
    and has_function_privilege('service_role', 'public.admin_begin_login_attempt(text,inet,timestamp with time zone)', 'EXECUTE')
    and has_function_privilege('service_role', 'public.admin_finish_login_attempt(uuid,boolean,text)', 'EXECUTE')
    and has_function_privilege('service_role', 'public.admin_upsert_semester_runtime_config(uuid,text,text,date,integer,text,jsonb,boolean,uuid)', 'EXECUTE')
    and has_function_privilege('service_role', 'public.admin_upsert_national_calendar_runtime_config(uuid,integer,jsonb,jsonb,boolean,uuid)', 'EXECUTE'),
  'service_role can execute every new admin RPC'
);

select ok(
  not has_function_privilege('anon', 'public.admin_login_rate_limit_status(text,inet,timestamp with time zone)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.admin_login_rate_limit_status(text,inet,timestamp with time zone)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.admin_cleanup_login_attempts(timestamp with time zone)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.admin_cleanup_login_attempts(timestamp with time zone)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.admin_begin_login_attempt(text,inet,timestamp with time zone)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.admin_begin_login_attempt(text,inet,timestamp with time zone)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.admin_finish_login_attempt(uuid,boolean,text)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.admin_finish_login_attempt(uuid,boolean,text)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.admin_upsert_semester_runtime_config(uuid,text,text,date,integer,text,jsonb,boolean,uuid)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.admin_upsert_semester_runtime_config(uuid,text,text,date,integer,text,jsonb,boolean,uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.admin_upsert_national_calendar_runtime_config(uuid,integer,jsonb,jsonb,boolean,uuid)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.admin_upsert_national_calendar_runtime_config(uuid,integer,jsonb,jsonb,boolean,uuid)', 'EXECUTE'),
  'anon and authenticated cannot execute the new admin RPCs'
);

select ok(
  not exists (
    select 1
    from information_schema.routine_privileges
    where routine_schema = 'public'
      and routine_name in (
        'admin_login_rate_limit_status',
        'admin_cleanup_login_attempts',
        'admin_begin_login_attempt',
        'admin_finish_login_attempt',
        'admin_upsert_semester_runtime_config',
        'admin_upsert_national_calendar_runtime_config'
      )
      and grantee = 'PUBLIC'
      and privilege_type = 'EXECUTE'
  ),
  'PUBLIC cannot execute the new admin RPCs'
);

select ok(
  exists (select 1 from pg_extension where extname = 'pg_trgm'),
  'pg_trgm is installed'
);

select ok(to_regclass('public.idx_profiles_admin_search_trgm') is not null, 'profile admin-search trigram index exists');
select ok(to_regclass('public.idx_posts_admin_search_trgm') is not null, 'post admin-search trigram index exists');
select ok(to_regclass('public.idx_posts_admin_search_fts') is not null, 'post admin-search full-text index exists');
select ok(to_regclass('public.idx_comments_admin_search_trgm') is not null, 'comment admin-search trigram index exists');
select ok(to_regclass('public.idx_teachers_admin_search_trgm') is not null, 'teacher admin-search trigram index exists');
select ok(to_regclass('public.idx_course_catalog_admin_search_trgm') is not null, 'course admin-search trigram index exists');
select ok(to_regclass('public.idx_postgraduate_sources_admin_search_trgm') is not null, 'postgraduate source admin-search trigram index exists');

delete from public.admin_login_attempts
where ip_address in ('203.0.113.10'::inet, '203.0.113.20'::inet, '203.0.113.30'::inet);

insert into public.admin_login_attempts (username, ip_address, succeeded, attempted_at)
values ('task2-user', '203.0.113.10', true, timestamptz '2026-07-10 00:10:00+00');

select is(
  (select username_ip_attempt_count from public.admin_login_rate_limit_status('TASK2-USER', '203.0.113.10', timestamptz '2026-07-10 00:15:00+00')),
  0::bigint,
  'successful logins do not consume the failure budget'
);

select is(
  (select ip_attempt_count from public.admin_login_rate_limit_status('TASK2-USER', '203.0.113.10', timestamptz '2026-07-10 00:15:00+00')),
  0::bigint,
  'an IP with no failures starts with an empty failure budget'
);

insert into public.admin_login_attempts (username, ip_address, succeeded, attempted_at)
select
  case when value = 1 then 'TASK2-USER' else 'task2-user' end,
  '203.0.113.10',
  false,
  timestamptz '2026-07-10 00:15:00+00' - make_interval(mins => value)
from generate_series(1, 4) as value;

select is(
  (select username_ip_attempt_count from public.admin_login_rate_limit_status(' task2-user ', '203.0.113.10', timestamptz '2026-07-10 00:15:00+00')),
  4::bigint,
  'same username and IP failures are counted case-insensitively'
);

select ok(
  not (select is_rate_limited from public.admin_login_rate_limit_status('task2-user', '203.0.113.10', timestamptz '2026-07-10 00:15:00+00')),
  'four same-account and IP failures remain below the limit'
);

insert into public.admin_login_attempts (username, ip_address, succeeded, attempted_at)
values ('task2-user', '203.0.113.10', false, timestamptz '2026-07-10 00:14:30+00');

select ok(
  (select is_rate_limited from public.admin_login_rate_limit_status('task2-user', '203.0.113.10', timestamptz '2026-07-10 00:15:00+00')),
  'five same-account and IP failures trigger the limit'
);

select ok(
  (select retry_after is not null from public.admin_login_rate_limit_status('task2-user', '203.0.113.10', timestamptz '2026-07-10 00:15:00+00')),
  'a limited login receives a retry time'
);

select ok(
  (select attempt_id is not null and not is_rate_limited
   from public.admin_begin_login_attempt('task2-atomic', '203.0.113.30', timestamptz '2026-07-10 00:20:00+00')),
  'atomic begin registers one permitted attempt'
);

select ok(
  public.admin_finish_login_attempt(
    (select id from public.admin_login_attempts where username = 'task2-atomic' order by attempted_at desc limit 1),
    true,
    null
  ),
  'finish updates the registered attempt result'
);

select ok(
  not (select is_rate_limited from public.admin_login_rate_limit_status('task2-user', '203.0.113.10', timestamptz '2026-07-10 00:31:00+00')),
  'the username and IP failure budget expires after 15 minutes'
);

delete from public.admin_login_attempts where ip_address = '203.0.113.20'::inet;

insert into public.admin_login_attempts (username, ip_address, succeeded, attempted_at)
select 'task2-ip-user-' || value::text, '203.0.113.20', false, timestamptz '2026-07-10 00:10:00+00'
from generate_series(1, 19) as value;

select is(
  (select ip_attempt_count from public.admin_login_rate_limit_status('new-task2-user', '203.0.113.20', timestamptz '2026-07-10 00:15:00+00')),
  19::bigint,
  'failures from different usernames share the IP budget'
);

select ok(
  not (select is_rate_limited from public.admin_login_rate_limit_status('new-task2-user', '203.0.113.20', timestamptz '2026-07-10 00:15:00+00')),
  'nineteen failures remain below the IP limit'
);

insert into public.admin_login_attempts (username, ip_address, succeeded, attempted_at)
values ('task2-ip-user-20', '203.0.113.20', false, timestamptz '2026-07-10 00:14:00+00');

select ok(
  (select is_rate_limited from public.admin_login_rate_limit_status('new-task2-user', '203.0.113.20', timestamptz '2026-07-10 00:15:00+00')),
  'twenty failures from one IP trigger the limit'
);

insert into public.admin_login_attempts (username, ip_address, succeeded, attempted_at)
values
  ('task2-cleanup-old', '203.0.113.30', false, timestamptz '2026-01-01 00:00:00+00'),
  ('task2-cleanup-new', '203.0.113.30', false, timestamptz '2026-07-01 00:00:00+00');

do $$
begin
  perform public.admin_cleanup_login_attempts(timestamptz '2026-04-01 00:00:00+00');
end
$$;

select ok(
  not exists (select 1 from public.admin_login_attempts where username = 'task2-cleanup-old'),
  'cleanup removes attempts older than the retention boundary'
);

select ok(
  exists (select 1 from public.admin_login_attempts where username = 'task2-cleanup-new'),
  'cleanup retains attempts inside the retention boundary'
);

select is(
  (select count(*) from cron.job where jobname = 'leafy-admin-login-attempts-retention'),
  1::bigint,
  'exactly one daily login-attempt retention job is scheduled'
);

select ok(
  (public.admin_upsert_semester_runtime_config(
    null, 'bjfu', 'task2-semester-a', date '2020-01-01', 20, 'task2-a', '[]'::jsonb, true, null
  )).is_active,
  'semester RPC can activate an eligible configuration'
);

do $$
begin
  perform public.admin_upsert_semester_runtime_config(
    null, 'bjfu', 'task2-semester-b', date '2020-02-01', 20, 'task2-b', '[]'::jsonb, true, null
  );
end
$$;

select is(
  (select count(*) from public.semester_runtime_configs where campus_id = 'bjfu' and is_active),
  1::bigint,
  'semester RPC keeps one active row per campus'
);

select ok(
  (select is_active from public.semester_runtime_configs where campus_id = 'bjfu' and semester_id = 'task2-semester-b'),
  'semester RPC activates the requested eligible row'
);

select ok(
  not (public.admin_upsert_semester_runtime_config(
    null, 'bjfu', 'task2-semester-future', date '2099-01-01', 20, 'task2-future', '[]'::jsonb, true, null
  )).is_active,
  'semester RPC preserves the existing future-activation guard'
);

select is(
  (select count(*) from public.semester_runtime_configs where campus_id = 'bjfu' and is_active),
  1::bigint,
  'future semester writes preserve the per-campus active-row invariant'
);

select ok(
  (public.admin_upsert_national_calendar_runtime_config(
    null, 2098, '[]'::jsonb, '[]'::jsonb, true, null
  )).is_active,
  'national-calendar RPC can activate a configuration'
);

do $$
begin
  perform public.admin_upsert_national_calendar_runtime_config(
    null, 2099, '[]'::jsonb, '[]'::jsonb, true, null
  );
end
$$;

select is(
  (select count(*) from public.national_calendar_runtime_configs where is_active),
  1::bigint,
  'national-calendar RPC keeps one globally active row'
);

select ok(
  (select is_active from public.national_calendar_runtime_configs where year = 2099),
  'national-calendar RPC activates the requested row'
);

do $$
begin
  perform public.admin_upsert_national_calendar_runtime_config(
    null, 2100, '[]'::jsonb, '[]'::jsonb, false, null
  );
end
$$;

select is(
  (select count(*) from public.national_calendar_runtime_configs where is_active),
  1::bigint,
  'an inactive national-calendar save preserves exactly one active row'
);

select ok(
  not (select is_active from public.national_calendar_runtime_configs where year = 2100),
  'an inactive national-calendar save does not replace the active row'
);

select * from finish();
rollback;
