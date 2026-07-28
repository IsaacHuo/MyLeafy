begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(15);

select ok(to_regclass('public.community_banners') is not null, 'community_banners exists');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.community_banners'::regclass),
  'community_banners has RLS enabled'
);
select ok(
  to_regprocedure('public.publish_community_banner(uuid,uuid)') is not null,
  'atomic banner publication function exists'
);
select ok(
  has_function_privilege('service_role', 'public.publish_community_banner(uuid,uuid)', 'EXECUTE'),
  'service_role can publish banners'
);
select ok(
  not has_function_privilege('authenticated', 'public.publish_community_banner(uuid,uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.publish_community_banner(uuid,uuid)', 'EXECUTE'),
  'client roles cannot publish banners'
);
select ok(
  has_table_privilege('authenticated', 'public.community_banners', 'SELECT')
    and not has_table_privilege('authenticated', 'public.community_banners', 'INSERT')
    and not has_table_privilege('authenticated', 'public.community_banners', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.community_banners', 'DELETE'),
  'authenticated clients are read only'
);
select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'community_banners'
      and policyname = 'community_banners_select_active_campus'
      and qual like '%current_profile_id%'
      and qual like '%community_campus_id%'
      and qual like '%expires_at%'
  ),
  'banner read policy enforces profile campus and active expiry'
);
select ok(
  exists (
    select 1
    from storage.buckets
    where id = 'community-banner-assets'
      and public = false
      and file_size_limit = 2097152
      and allowed_mime_types = array['image/jpeg', 'image/png']::text[]
  ),
  'banner asset bucket is private and constrained'
);
select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'community_banner_assets_select_authenticated'
      and qual like '%foldername%'
      and qual like '%community_campus_id%'
  ),
  'banner asset reads are isolated by campus folder'
);
select ok(
  exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and tablename = 'community_banners'
      and indexname = 'idx_community_banners_one_published_per_campus'
      and indexdef like '%WHERE (status = ''published''%'
  ),
  'only one published banner is allowed per campus'
);

insert into public.community_banners (
  id, campus_id, title, subtitle, destination_kind, destination_value
)
select
  'c0000000-0000-4000-8000-000000000001',
  id,
  'Banner A',
  'First publication',
  'app_route',
  'community'
from public.campuses
order by id
limit 1;

insert into public.community_banners (
  id, campus_id, title, subtitle, destination_kind, destination_value
)
select
  'c0000000-0000-4000-8000-000000000002',
  id,
  'Banner B',
  'Second publication',
  'https_url',
  'https://example.com/banner'
from public.campuses
order by id
limit 1;

select is(
  (select count(*) from public.community_banners where id in (
    'c0000000-0000-4000-8000-000000000001',
    'c0000000-0000-4000-8000-000000000002'
  )),
  2::bigint,
  'banner test fixtures were created'
);

do $$
begin
  perform public.publish_community_banner('c0000000-0000-4000-8000-000000000001', null);
  perform public.publish_community_banner('c0000000-0000-4000-8000-000000000002', null);
end;
$$;

select is(
  (select status from public.community_banners where id = 'c0000000-0000-4000-8000-000000000001'),
  'archived',
  'publishing a replacement archives the previous banner'
);
select is(
  (select status from public.community_banners where id = 'c0000000-0000-4000-8000-000000000002'),
  'published',
  'replacement banner is published'
);
select is(
  (
    select count(*)
    from public.community_banners
    where status = 'published'
      and campus_id = (
        select campus_id
        from public.community_banners
        where id = 'c0000000-0000-4000-8000-000000000002'
      )
  ),
  1::bigint,
  'publication leaves exactly one published banner for the campus'
);

select throws_ok(
  $$
    insert into public.community_banners (
      campus_id, title, subtitle, destination_kind, destination_value
    )
    select id, 'Bad target', 'Missing value', 'https_url', null
    from public.campuses
    order by id
    limit 1
  $$,
  '23514',
  null,
  'destination value constraint rejects incomplete targets'
);

select * from finish();
rollback;
