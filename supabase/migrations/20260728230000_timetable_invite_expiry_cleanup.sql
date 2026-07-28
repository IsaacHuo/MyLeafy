create extension if not exists pg_cron;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create or replace function private.cleanup_expired_timetable_invites_v1()
returns bigint
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  deleted_count bigint;
begin
  delete from public.timetable_invites
  where expires_at <= now();

  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

revoke all on function private.cleanup_expired_timetable_invites_v1()
from public, anon, authenticated, service_role;

do $$
begin
  if exists (
    select 1
    from cron.job
    where jobname = 'leafy-timetable-invite-expiry-cleanup'
  ) then
    perform cron.unschedule('leafy-timetable-invite-expiry-cleanup');
  end if;
end
$$;

select cron.schedule(
  'leafy-timetable-invite-expiry-cleanup',
  '17 * * * *',
  $$select private.cleanup_expired_timetable_invites_v1();$$
);

select pg_notify('pgrst', 'reload schema');
