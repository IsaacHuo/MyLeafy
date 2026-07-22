create table if not exists private.campus_ai_storekit_notification_ledger (
  notification_uuid text primary key,
  app_transaction_id text not null,
  status text not null,
  signed_at timestamptz,
  received_at timestamptz not null default now()
);

revoke all on table private.campus_ai_storekit_notification_ledger from public, anon, authenticated;
grant select, insert on table private.campus_ai_storekit_notification_ledger to service_role;

create or replace function private.campus_ai_entitlement_status_rank(p_status text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case p_status
    when 'revoked' then 5
    when 'refunded' then 4
    when 'expired' then 3
    when 'active' then 2
    else 1
  end;
$$;

create or replace function private.sync_campus_ai_entitlement(
  p_auth_user_id uuid,
  p_app_transaction_id text,
  p_product_id text default null,
  p_original_transaction_id text default null,
  p_transaction_id text default null,
  p_environment text default null,
  p_status text default 'free',
  p_current_period_start timestamptz default null,
  p_current_period_end timestamptz default null,
  p_notification_uuid text default null,
  p_signed_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = private, public
as $$
declare
  normalized_app_transaction_id text := nullif(btrim(p_app_transaction_id), '');
  normalized_notification_uuid text := nullif(btrim(p_notification_uuid), '');
  normalized_status text := coalesce(nullif(btrim(p_status), ''), 'free');
  current_entitlement private.campus_ai_entitlements%rowtype;
  should_apply boolean := false;
  inserted_notification_count integer := 0;
begin
  if normalized_app_transaction_id is null then
    return jsonb_build_object(
      'applied', false,
      'duplicate', false,
      'quota', private.campus_ai_quota_snapshot(p_auth_user_id, normalized_app_transaction_id)
    );
  end if;

  if normalized_status not in ('free', 'active', 'expired', 'refunded', 'revoked') then
    normalized_status := 'free';
  end if;

  if normalized_notification_uuid is not null then
    insert into private.campus_ai_storekit_notification_ledger (
      notification_uuid,
      app_transaction_id,
      status,
      signed_at
    ) values (
      normalized_notification_uuid,
      normalized_app_transaction_id,
      normalized_status,
      p_signed_at
    )
    on conflict (notification_uuid) do nothing;

    get diagnostics inserted_notification_count = row_count;
    if inserted_notification_count = 0 then
      return jsonb_build_object(
        'applied', false,
        'duplicate', true,
        'quota', private.campus_ai_quota_snapshot(p_auth_user_id, normalized_app_transaction_id)
      );
    end if;
  end if;

  select * into current_entitlement
  from private.campus_ai_entitlements
  where app_transaction_id = normalized_app_transaction_id
  for update;

  if found
     and p_auth_user_id is not null
     and current_entitlement.auth_user_id is not null
     and current_entitlement.auth_user_id <> p_auth_user_id then
    raise exception 'CAMPUS_AI_ENTITLEMENT_OWNERSHIP_MISMATCH';
  end if;

  if not found then
    should_apply := true;
  elsif p_signed_at is null and current_entitlement.last_signed_at is not null then
    should_apply := false;
  elsif p_signed_at is not null and current_entitlement.last_signed_at is null then
    should_apply := true;
  elsif p_signed_at is not null and p_signed_at > current_entitlement.last_signed_at then
    should_apply := true;
  elsif p_signed_at is not null and p_signed_at < current_entitlement.last_signed_at then
    should_apply := false;
  else
    should_apply := private.campus_ai_entitlement_status_rank(normalized_status)
      > private.campus_ai_entitlement_status_rank(current_entitlement.status);
  end if;

  if not found then
    insert into private.campus_ai_entitlements (
      app_transaction_id,
      auth_user_id,
      product_id,
      original_transaction_id,
      transaction_id,
      environment,
      status,
      current_period_start,
      current_period_end,
      last_notification_uuid,
      last_signed_at
    ) values (
      normalized_app_transaction_id,
      p_auth_user_id,
      p_product_id,
      p_original_transaction_id,
      p_transaction_id,
      p_environment,
      normalized_status,
      p_current_period_start,
      p_current_period_end,
      normalized_notification_uuid,
      p_signed_at
    );
  elsif should_apply then
    update private.campus_ai_entitlements
    set
      auth_user_id = coalesce(auth_user_id, p_auth_user_id),
      product_id = coalesce(p_product_id, product_id),
      original_transaction_id = coalesce(p_original_transaction_id, original_transaction_id),
      transaction_id = coalesce(p_transaction_id, transaction_id),
      environment = coalesce(p_environment, environment),
      status = normalized_status,
      current_period_start = coalesce(p_current_period_start, current_period_start),
      current_period_end = coalesce(p_current_period_end, current_period_end),
      last_notification_uuid = coalesce(normalized_notification_uuid, last_notification_uuid),
      last_signed_at = case
        when last_signed_at is null then p_signed_at
        when p_signed_at is null then last_signed_at
        else greatest(last_signed_at, p_signed_at)
      end,
      updated_at = now()
    where app_transaction_id = normalized_app_transaction_id;
  elsif p_auth_user_id is not null and current_entitlement.auth_user_id is null then
    update private.campus_ai_entitlements
    set auth_user_id = p_auth_user_id, updated_at = now()
    where app_transaction_id = normalized_app_transaction_id;
  end if;

  return jsonb_build_object(
    'applied', should_apply,
    'duplicate', false,
    'quota', private.campus_ai_quota_snapshot(p_auth_user_id, normalized_app_transaction_id)
  );
end;
$$;

revoke all on function private.campus_ai_entitlement_status_rank(text) from public, anon, authenticated;
revoke all on function private.sync_campus_ai_entitlement(uuid, text, text, text, text, text, text, timestamptz, timestamptz, text, timestamptz)
  from public, anon, authenticated;
grant execute on function private.sync_campus_ai_entitlement(uuid, text, text, text, text, text, text, timestamptz, timestamptz, text, timestamptz)
  to service_role;
