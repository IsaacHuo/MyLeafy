create table if not exists public.community_banners (
  id uuid primary key default gen_random_uuid(),
  campus_id text not null references public.campuses (id) on delete cascade on update cascade,
  revision integer not null default 1 check (revision > 0),
  title text not null check (char_length(btrim(title)) between 1 and 60),
  subtitle text not null check (char_length(btrim(subtitle)) between 1 and 180),
  image_path text,
  destination_kind text not null default 'none'
    check (destination_kind in ('none', 'community_post', 'app_route', 'https_url')),
  destination_value text,
  status text not null default 'draft'
    check (status in ('draft', 'published', 'archived')),
  published_at timestamptz,
  expires_at timestamptz,
  created_by uuid references public.admin_accounts (id) on delete set null on update cascade,
  updated_by uuid references public.admin_accounts (id) on delete set null on update cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint community_banners_destination_value
    check (
      (destination_kind = 'none' and destination_value is null)
      or (destination_kind <> 'none' and nullif(btrim(destination_value), '') is not null)
    ),
  constraint community_banners_published_at_required
    check (status <> 'published' or published_at is not null),
  constraint community_banners_expiry_after_publish
    check (expires_at is null or published_at is null or expires_at > published_at)
);

create unique index if not exists idx_community_banners_one_published_per_campus
on public.community_banners (campus_id)
where status = 'published';

create index if not exists idx_community_banners_active
on public.community_banners (campus_id, published_at desc)
where status = 'published';

drop trigger if exists community_banners_set_updated_at on public.community_banners;
create trigger community_banners_set_updated_at
before update on public.community_banners
for each row
execute function public.set_updated_at();

alter table public.community_banners enable row level security;

drop policy if exists "community_banners_select_active_campus" on public.community_banners;
create policy "community_banners_select_active_campus"
on public.community_banners
for select
to authenticated
using (
  status = 'published'
  and published_at <= now()
  and (expires_at is null or expires_at > now())
  and campus_id = (
    select profiles.community_campus_id
    from public.profiles
    where profiles.id = public.current_profile_id()
  )
);

create or replace function public.publish_community_banner(
  p_banner_id uuid,
  p_admin_id uuid
)
returns public.community_banners
language plpgsql
security definer
set search_path = public
as $$
declare
  target public.community_banners;
begin
  select *
  into target
  from public.community_banners
  where id = p_banner_id
  for update;

  if target.id is null then
    raise exception 'COMMUNITY_BANNER_NOT_FOUND';
  end if;

  if target.expires_at is not null and target.expires_at <= now() then
    raise exception 'COMMUNITY_BANNER_EXPIRED';
  end if;

  perform pg_advisory_xact_lock(hashtext('community_banner:' || target.campus_id));

  update public.community_banners
  set
    status = 'archived',
    updated_by = p_admin_id,
    updated_at = now()
  where campus_id = target.campus_id
    and status = 'published'
    and id <> target.id;

  update public.community_banners
  set
    status = 'published',
    published_at = now(),
    updated_by = p_admin_id,
    updated_at = now()
  where id = target.id
  returning * into target;

  return target;
end;
$$;

revoke all on function public.publish_community_banner(uuid, uuid)
from public, anon, authenticated;
grant execute on function public.publish_community_banner(uuid, uuid)
to service_role;

revoke all privileges on table public.community_banners
from public, anon, authenticated, service_role;
grant select on table public.community_banners
to authenticated;
grant select, insert, update, delete on table public.community_banners
to service_role;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'community-banner-assets',
  'community-banner-assets',
  false,
  2097152,
  array['image/jpeg', 'image/png']::text[]
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "community_banner_assets_select_authenticated" on storage.objects;
create policy "community_banner_assets_select_authenticated"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'community-banner-assets'
  and (storage.foldername(name))[1] = (
    select profiles.community_campus_id
    from public.profiles
    where profiles.id = public.current_profile_id()
  )
);

comment on table public.community_banners is
  'Campus-scoped editorial banners shown above the community feed. Publishing atomically archives the previous banner.';
comment on function public.publish_community_banner(uuid, uuid) is
  'Atomically publishes one banner and archives any previously published banner for the same campus.';

select pg_notify('pgrst', 'reload schema');
