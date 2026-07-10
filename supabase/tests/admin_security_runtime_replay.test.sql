\o /dev/null
\ir ../migrations/20260710120000_admin_security_runtime.sql
\o

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(5);

select pass('the forward migration can be replayed without an SQL error');

select is(
  (select count(*) from pg_class where oid = 'public.admin_login_attempts'::regclass),
  1::bigint,
  'migration replay leaves one login-attempt table'
);

select is(
  (select count(*) from pg_proc where oid = 'public.admin_login_rate_limit_status(text,inet,timestamp with time zone)'::regprocedure),
  1::bigint,
  'migration replay leaves one rate-limit function'
);

select is(
  (select count(*) from cron.job where jobname = 'leafy-admin-login-attempts-retention'),
  1::bigint,
  'migration replay leaves one retention job'
);

select is(
  (select count(*) from pg_indexes where schemaname = 'public' and indexname = 'idx_posts_admin_search_fts'),
  1::bigint,
  'migration replay leaves one copy of each named search index'
);

select * from finish();
rollback;
