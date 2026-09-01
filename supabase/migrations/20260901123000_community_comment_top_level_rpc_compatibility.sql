-- Accept the five-key payload emitted by shipped clients for top-level comments.
-- Reply payloads continue to use the seven-argument idempotent overload.
create function public.create_community_comment_v2(
  p_id uuid,
  p_post_id uuid,
  p_body text,
  p_is_anonymous boolean,
  p_request_id uuid
)
returns public.comments
language sql
security invoker
set search_path = public, pg_temp
as $$
  select public.create_community_comment_v2(
    p_id,
    p_post_id,
    p_body,
    null,
    null,
    p_is_anonymous,
    p_request_id
  );
$$;

revoke all on function public.create_community_comment_v2(uuid, uuid, text, boolean, uuid)
from public, anon;
grant execute on function public.create_community_comment_v2(uuid, uuid, text, boolean, uuid)
to authenticated, service_role;

comment on function public.create_community_comment_v2(uuid, uuid, text, boolean, uuid)
is 'Compatibility overload for idempotent top-level comments whose null reply targets are omitted by clients.';

select pg_notify('pgrst', 'reload schema');
