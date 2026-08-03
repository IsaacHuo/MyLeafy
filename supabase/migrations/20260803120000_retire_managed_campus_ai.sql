-- MyLeafy 3.0 uses user-provided DeepSeek API keys only. The Tool Gateway
-- remains available for authenticated public web research.

drop function if exists public.edge_campus_ai_quota_snapshot(uuid, text, timestamptz);
drop function if exists public.edge_campus_ai_reserve_quota(uuid, uuid, text, text, timestamptz);
drop function if exists public.edge_campus_ai_complete_usage(
  uuid, text, boolean, integer, integer, integer, integer, integer,
  integer, integer, integer, numeric, text
);
drop function if exists public.edge_campus_ai_sync_entitlement(
  uuid, text, text, text, text, text, text, timestamptz, timestamptz, text, timestamptz
);

drop function if exists private.sync_campus_ai_entitlement(
  uuid, text, text, text, text, text, text, timestamptz, timestamptz, text, timestamptz
);
drop function if exists private.complete_campus_ai_usage(
  uuid, text, boolean, integer, integer, integer, integer, integer,
  integer, integer, integer, numeric, text
);
drop function if exists private.reserve_campus_ai_quota(uuid, uuid, text, text, timestamptz);
drop function if exists private.campus_ai_quota_snapshot(uuid, text, timestamptz);
drop function if exists private.expire_stale_campus_ai_reservations(timestamptz);
drop function if exists private.campus_ai_entitlement_status_rank(text);
drop function if exists private.campus_ai_beijing_day_start(timestamptz);
drop function if exists private.campus_ai_beijing_month_start(timestamptz);

drop table if exists private.campus_ai_storekit_notification_ledger;
drop table if exists private.campus_ai_usage_events;
drop table if exists private.campus_ai_entitlements;

alter function public.backend_capabilities_v1()
  rename to backend_capabilities_v1_before_managed_campus_ai_retirement;

create function public.backend_capabilities_v1()
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
          '4'::jsonb
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
          coalesce(value -> 'edge_functions', '[]'::jsonb) || '["campus-ai-tools"]'::jsonb
        ) as edge(name)
        where name not in (
          'campus-ai-assistant',
          'campus-ai-entitlement',
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
is 'Returns backend capability manifest version 4 for BYOK-only MyLeafy AI with campus-ai-tools.';

select pg_notify('pgrst', 'reload schema');
