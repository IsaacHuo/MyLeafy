create or replace function public.lookup_verified_edu_id_by_email(
  p_email text,
  p_campus_id text default 'bjfu'
)
returns text
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select profiles.edu_id
  from public.profiles
  where profiles.campus_id = lower(btrim(coalesce(p_campus_id, 'bjfu')))
    and lower(btrim(profiles.bound_email)) = lower(btrim(coalesce(p_email, '')))
    and nullif(btrim(profiles.bound_email), '') is not null
  limit 1;
$$;

revoke all on function public.lookup_verified_edu_id_by_email(text, text) from public, anon, authenticated;
grant execute on function public.lookup_verified_edu_id_by_email(text, text) to service_role;

comment on function public.lookup_verified_edu_id_by_email(text, text)
  is 'Service-role lookup for verified email aliases. Returns edu_id only for bound_email, never pending_bound_email.';
