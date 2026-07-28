begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(4);

select ok(
  to_regprocedure('private.cleanup_expired_timetable_invites_v1()') is not null,
  'expired timetable invite cleanup function exists'
);

select ok(
  pg_get_functiondef('private.cleanup_expired_timetable_invites_v1()'::regprocedure)
    like '%delete from public.timetable_invites%'
  and pg_get_functiondef('private.cleanup_expired_timetable_invites_v1()'::regprocedure)
    like '%expires_at <= now()%',
  'cleanup deletes only expired timetable invites'
);

select is(
  (
    select schedule
    from cron.job
    where jobname = 'leafy-timetable-invite-expiry-cleanup'
  ),
  '17 * * * *',
  'expired timetable invites are cleaned hourly'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'private.cleanup_expired_timetable_invites_v1()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'private.cleanup_expired_timetable_invites_v1()',
    'EXECUTE'
  ),
  'client roles cannot run invite cleanup'
);

select * from finish();
rollback;
