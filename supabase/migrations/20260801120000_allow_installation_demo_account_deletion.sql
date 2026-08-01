create or replace function public.edge_delete_community_account(
  p_auth_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_profile_id uuid;
  target_edu_id text;
begin
  if p_auth_user_id is null then
    raise exception 'COMMUNITY_AUTH_SESSION_REQUIRED';
  end if;

  select links.profile_id, profiles.edu_id
  into target_profile_id, target_edu_id
  from public.profile_auth_links links
  join public.profiles profiles
    on profiles.id = links.profile_id
  where links.auth_user_id = p_auth_user_id;

  if target_profile_id is null then
    return jsonb_build_object(
      'deleted', true,
      'profile_id', null
    );
  end if;

  if lower(btrim(target_edu_id)) = 'review-demo' then
    raise exception 'COMMUNITY_DEMO_ACCOUNT_PROTECTED';
  end if;

  -- Replies written by other users must survive deletion of a root comment.
  -- Detaching them avoids the parent-comment restrict constraint without
  -- deleting another user's content.
  update public.comments replies
  set
    parent_comment_id = null,
    reply_to_comment_id = null,
    updated_at = now()
  where replies.author_id <> target_profile_id
    and replies.parent_comment_id in (
      select roots.id
      from public.comments roots
      where roots.author_id = target_profile_id
    );

  -- These tables intentionally use ON DELETE SET NULL for administrative
  -- workflows. Account deletion removes submissions authored by the user
  -- instead of retaining their text without an owner.
  delete from public.feedback_submissions
  where user_id = target_profile_id;

  delete from public.catalog_suggestions
  where user_id = target_profile_id;

  delete from public.postgraduate_source_suggestions
  where user_id = target_profile_id;

  delete from private.community_identity_link_conflicts
  where auth_user_id = p_auth_user_id
     or profile_id = target_profile_id;

  delete from public.profiles
  where id = target_profile_id;

  return jsonb_build_object(
    'deleted', true,
    'profile_id', target_profile_id
  );
end;
$$;

revoke all on function public.edge_delete_community_account(uuid)
  from public, anon, authenticated;
grant execute on function public.edge_delete_community_account(uuid)
  to service_role;

comment on function public.edge_delete_community_account(uuid) is
  'Deletes the community profile linked to an authenticated user. Service-role only; installation-scoped review demos are deletable while the legacy shared review-demo identity remains protected.';

select pg_notify('pgrst', 'reload schema');
