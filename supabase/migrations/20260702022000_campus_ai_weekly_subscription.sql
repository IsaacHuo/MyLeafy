create or replace function private.campus_ai_quota_snapshot(
  p_auth_user_id uuid,
  p_app_transaction_id text,
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = private, public
as $$
declare
  normalized_app_transaction_id text := nullif(btrim(p_app_transaction_id), '');
  active_entitlement private.campus_ai_entitlements%rowtype;
  plan_source text := 'free';
  quota_limit integer := 10;
  period_start timestamptz := private.campus_ai_beijing_month_start(p_now);
  period_end timestamptz := period_start + interval '1 month';
  used_count integer := 0;
begin
  if normalized_app_transaction_id is not null then
    select *
      into active_entitlement
      from private.campus_ai_entitlements
     where app_transaction_id = normalized_app_transaction_id
       and status = 'active'
       and product_id = 'com.isaachuo.leafy.ai.weekly'
       and current_period_end > p_now
     order by updated_at desc
     limit 1;
  elsif p_auth_user_id is not null then
    select *
      into active_entitlement
      from private.campus_ai_entitlements
     where auth_user_id = p_auth_user_id
       and status = 'active'
       and product_id = 'com.isaachuo.leafy.ai.weekly'
       and current_period_end > p_now
     order by updated_at desc
     limit 1;
  end if;

  if active_entitlement.app_transaction_id is not null then
    plan_source := 'subscription';
    quota_limit := 50;
    period_start := coalesce(active_entitlement.current_period_start, p_now);
    period_end := active_entitlement.current_period_end;
  end if;

  select count(*)::integer
    into used_count
    from private.campus_ai_usage_events usage
   where usage.plan_source = plan_source
     and usage.status in ('reserved', 'success')
     and usage.quota_units > 0
     and usage.created_at >= period_start
     and usage.created_at < period_end
     and (
       (normalized_app_transaction_id is not null and usage.app_transaction_id = normalized_app_transaction_id)
       or (normalized_app_transaction_id is null and usage.auth_user_id = p_auth_user_id)
     );

  return jsonb_build_object(
    'plan_source', plan_source,
    'limit', quota_limit,
    'used', used_count,
    'remaining', greatest(quota_limit - used_count, 0),
    'reset_at', to_char(period_end at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'status', case when plan_source = 'subscription' then 'active' else 'free' end
  );
end;
$$;

revoke all on function private.campus_ai_quota_snapshot(uuid, text, timestamptz) from public, anon, authenticated;
grant execute on function private.campus_ai_quota_snapshot(uuid, text, timestamptz) to service_role;
