-- Current clients publish atomically when the final validated media item is attached.
-- Retire the standalone publish RPC and stop advertising it as a capability.

drop function if exists public.publish_community_post_v1(uuid);

alter function public.backend_capabilities_v1()
  rename to backend_capabilities_v1_before_publish_rpc_cleanup;

revoke all on function public.backend_capabilities_v1_before_publish_rpc_cleanup()
  from public, anon, authenticated;
grant execute on function public.backend_capabilities_v1_before_publish_rpc_cleanup()
  to service_role;

create function public.backend_capabilities_v1()
returns jsonb
language sql
stable
security definer
set search_path = public, private, pg_catalog
as $$
  with base as (
    select public.backend_capabilities_v1_before_publish_rpc_cleanup() as value
  )
  select jsonb_set(
    jsonb_set(value, '{version}', '6'::jsonb),
    '{rpcs}',
    coalesce(value -> 'rpcs', '{}'::jsonb) - 'publish_community_post_v1'
  )
  from base;
$$;

revoke all on function public.backend_capabilities_v1() from public, anon, authenticated;
grant execute on function public.backend_capabilities_v1() to anon, authenticated, service_role;

comment on function public.backend_capabilities_v1()
is 'Returns the current MyLeafy backend capability manifest without obsolete publish compatibility.';

select pg_notify('pgrst', 'reload schema');
