create schema if not exists private;

create table if not exists private.community_identity_link_conflicts (
  auth_user_id uuid not null,
  profile_id uuid not null,
  campus_id text not null,
  edu_id text not null,
  created_at timestamptz not null,
  last_seen_at timestamptz not null,
  retained_auth_user_id uuid not null,
  resolution_reason text not null,
  archived_at timestamptz not null default now(),
  primary key (auth_user_id, profile_id, archived_at)
);

revoke all on table private.community_identity_link_conflicts from public, anon, authenticated;
grant select, insert on table private.community_identity_link_conflicts to service_role;

-- The profile is the durable owner of community content. Normalize every link
-- to that profile's identity before choosing a single Auth session owner.
update public.profile_auth_links links
set
  campus_id = profiles.campus_id,
  edu_id = profiles.edu_id
from public.profiles profiles
where profiles.id = links.profile_id
  and (links.campus_id, links.edu_id) is distinct from (profiles.campus_id, profiles.edu_id);

with ranked_links as (
  select
    links.*,
    first_value(links.auth_user_id) over (
      partition by links.profile_id
      order by
        (links.auth_user_id = links.profile_id) desc,
        (
          users.email_confirmed_at is not null
          and profiles.bound_email is not null
          and lower(users.email) = lower(profiles.bound_email)
        ) desc,
        links.created_at asc,
        links.auth_user_id asc
    ) as retained_auth_user_id,
    row_number() over (
      partition by links.profile_id
      order by
        (links.auth_user_id = links.profile_id) desc,
        (
          users.email_confirmed_at is not null
          and profiles.bound_email is not null
          and lower(users.email) = lower(profiles.bound_email)
        ) desc,
        links.created_at asc,
        links.auth_user_id asc
    ) as ownership_rank
  from public.profile_auth_links links
  join public.profiles profiles on profiles.id = links.profile_id
  left join auth.users users on users.id = links.auth_user_id
), archived as (
  insert into private.community_identity_link_conflicts (
    auth_user_id,
    profile_id,
    campus_id,
    edu_id,
    created_at,
    last_seen_at,
    retained_auth_user_id,
    resolution_reason
  )
  select
    auth_user_id,
    profile_id,
    campus_id,
    edu_id,
    created_at,
    last_seen_at,
    retained_auth_user_id,
    'duplicate_profile_link'
  from ranked_links
  where ownership_rank > 1
  returning auth_user_id, profile_id
)
delete from public.profile_auth_links links
using archived
where links.auth_user_id = archived.auth_user_id
  and links.profile_id = archived.profile_id;

create unique index if not exists idx_profile_auth_links_profile_id_unique
on public.profile_auth_links (profile_id);

create unique index if not exists idx_profile_auth_links_campus_edu_id_unique
on public.profile_auth_links (campus_id, edu_id);

create or replace function public.edge_claim_community_identity(
  p_auth_user_id uuid,
  p_campus_id text,
  p_edu_id text,
  p_display_name text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_campus_id text := lower(nullif(btrim(coalesce(p_campus_id, '')), ''));
  normalized_edu_id text := nullif(btrim(coalesce(p_edu_id, '')), '');
  normalized_display_name text := nullif(btrim(coalesce(p_display_name, '')), '');
  current_link public.profile_auth_links%rowtype;
  target_profile public.profiles%rowtype;
  target_link public.profile_auth_links%rowtype;
  is_new_user boolean := false;
begin
  if p_auth_user_id is null or not exists (select 1 from auth.users where id = p_auth_user_id) then
    raise exception 'COMMUNITY_AUTH_SESSION_REQUIRED';
  end if;

  if normalized_campus_id not in ('bjfu', 'general') then
    normalized_campus_id := 'general';
  end if;

  if normalized_edu_id is null then
    raise exception 'COMMUNITY_EDU_ID_REQUIRED';
  end if;

  normalized_display_name := coalesce(normalized_display_name, normalized_edu_id);

  -- Serialize first-use claims for the same campus identity.
  perform pg_advisory_xact_lock(hashtextextended(normalized_campus_id || ':' || normalized_edu_id, 0));

  select * into current_link
  from public.profile_auth_links
  where auth_user_id = p_auth_user_id;

  if found then
    if current_link.campus_id <> normalized_campus_id or current_link.edu_id <> normalized_edu_id then
      raise exception 'COMMUNITY_AUTH_IDENTITY_MISMATCH';
    end if;

    update public.profile_auth_links
    set last_seen_at = now()
    where auth_user_id = p_auth_user_id;

    update public.profiles
    set display_name = normalized_display_name, updated_at = now()
    where id = current_link.profile_id;

    select * into target_profile from public.profiles where id = current_link.profile_id;
    return jsonb_build_object('profile_id', target_profile.id, 'is_new_user', false);
  end if;

  select * into target_profile
  from public.profiles
  where campus_id = normalized_campus_id
    and edu_id = normalized_edu_id;

  if found then
    select * into target_link
    from public.profile_auth_links
    where profile_id = target_profile.id;

    -- Existing profiles are never adopted by a new anonymous session. Recovery
    -- must prove control of the already verified notification email instead.
    if not found or target_link.auth_user_id <> p_auth_user_id then
      raise exception 'COMMUNITY_ACCOUNT_RECOVERY_REQUIRED';
    end if;
  else
    if exists (select 1 from public.profiles where id = p_auth_user_id) then
      raise exception 'COMMUNITY_AUTH_IDENTITY_MISMATCH';
    end if;

    insert into public.profiles (
      id,
      campus_id,
      edu_id,
      nickname,
      display_name,
      community_campus_id,
      community_access_status,
      community_school_name,
      community_rejection_reason,
      is_profile_complete
    )
    values (
      p_auth_user_id,
      normalized_campus_id,
      normalized_edu_id,
      '',
      normalized_display_name,
      case when normalized_campus_id = 'bjfu' then 'bjfu' else null end,
      case when normalized_campus_id = 'bjfu' then 'approved' else 'general' end,
      case when normalized_campus_id = 'bjfu' then '北京林业大学' else null end,
      null,
      false
    )
    returning * into target_profile;

    insert into public.profile_auth_links (
      auth_user_id,
      profile_id,
      campus_id,
      edu_id,
      last_seen_at
    ) values (
      p_auth_user_id,
      target_profile.id,
      normalized_campus_id,
      normalized_edu_id,
      now()
    );

    is_new_user := true;
  end if;

  return jsonb_build_object('profile_id', target_profile.id, 'is_new_user', is_new_user);
exception
  when unique_violation then
    raise exception 'COMMUNITY_ACCOUNT_RECOVERY_REQUIRED';
end;
$$;

revoke all on function public.edge_claim_community_identity(uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.edge_claim_community_identity(uuid, text, text, text)
  to service_role;

select pg_notify('pgrst', 'reload schema');
