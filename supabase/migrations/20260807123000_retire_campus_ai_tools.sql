-- MyLeafy no longer exposes model or research-tool capabilities.
-- Keep earlier migrations immutable and retire the deployed objects forward.

drop function if exists public.reserve_campus_ai_tool_call(uuid, uuid, text, timestamptz);
drop function if exists public.complete_campus_ai_tool_call(uuid, text, integer, integer, text);

drop function if exists private.reserve_campus_ai_tool_call(uuid, uuid, text, timestamptz);
drop function if exists private.complete_campus_ai_tool_call(uuid, text, integer, integer, text);

drop table if exists private.campus_ai_tool_events;

create or replace function public.backend_capabilities_v1()
returns jsonb
language sql
stable
security definer
set search_path = public, private, pg_catalog
as $$
  with base as (
    select public.backend_capabilities_v1_before_managed_campus_ai_retirement() as value
  ), cleaned as (
    select jsonb_set(
      jsonb_set(
        jsonb_set(
          value,
          '{version}',
          '5'::jsonb
        ),
        '{features}',
        coalesce(value -> 'features', '{}'::jsonb)
          - 'campus_ai'
          - 'campus_ai_managed_entitlements'
      ),
      '{rpcs}',
      coalesce(value -> 'rpcs', '{}'::jsonb)
        - 'edge_campus_ai_quota_snapshot'
        - 'edge_campus_ai_reserve_quota'
        - 'edge_campus_ai_complete_usage'
        - 'edge_campus_ai_sync_entitlement'
        - 'reserve_campus_ai_tool_call'
        - 'complete_campus_ai_tool_call'
    ) as value
    from base
  )
  select jsonb_set(
    value,
    '{edge_functions}',
    (
      select coalesce(jsonb_agg(name order by name), '[]'::jsonb)
      from (
        select distinct name
        from jsonb_array_elements_text(
          coalesce(value -> 'edge_functions', '[]'::jsonb)
        ) as edge(name)
        where name not in (
          'campus-ai-assistant',
          'campus-ai-entitlement',
          'campus-ai-tools',
          'app-store-server-notifications'
        )
      ) retained
    )
  )
  from cleaned;
$$;

revoke all on function public.backend_capabilities_v1() from public, anon, authenticated;
grant execute on function public.backend_capabilities_v1() to anon, authenticated, service_role;

comment on function public.backend_capabilities_v1()
is 'Returns the current MyLeafy backend capability manifest.';

select pg_notify('pgrst', 'reload schema');
