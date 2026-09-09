begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(6);

create temporary table before_demo_counts as
select coalesce(sum(profiles), 0)::bigint as n from public.admin_daily_counts(1, 'UTC', 'bjfu');

insert into public.profiles (id, campus_id, edu_id, nickname, display_name, community_campus_id, community_access_status, is_profile_complete)
values
('e9090000-0000-0000-0000-000000000001', 'bjfu', 'review-demo-e9090000-0000-0000-0000-000000000001', 'Demo', 'Demo', 'bjfu', 'approved', true),
('e9090000-0000-0000-0000-000000000002', 'bjfu', ' REVIEW-DEMO ', 'Demo', 'Demo', 'bjfu', 'approved', true),
('e9090000-0000-0000-0000-000000000003', 'bjfu', 'demo-stat-real-student', 'Student', 'Student', 'bjfu', 'approved', true);

select is((select count(*)::integer from public.profiles where id::text like 'e9090000-%' and is_demo), 2, 'existing identity rule identifies both demo variants');
select is((select count(*)::integer from public.profiles where id::text like 'e9090000-%' and not is_demo), 1, 'real users remain in list/export/count scope');
select is((select coalesce(sum(profiles), 0)::bigint from public.admin_daily_counts(1, 'UTC', 'bjfu')),
          (select n + 1 from before_demo_counts), 'daily new users increase only for the real profile');
select is((select count(*)::integer from public.profiles where id::text like 'e9090000-%'), 3, 'demo profiles remain intact');
update public.profiles set edu_id = 'review-demo-e9090000-0000-0000-0000-000000000003' where id = 'e9090000-0000-0000-0000-000000000003';
select ok((select is_demo from public.profiles where id = 'e9090000-0000-0000-0000-000000000003'), 'identity changes recompute the server-owned classification');
select ok(not has_function_privilege('authenticated', 'public.admin_daily_counts(integer,text,text)', 'EXECUTE'), 'statistics remain service-role only');
select * from finish();
rollback;
