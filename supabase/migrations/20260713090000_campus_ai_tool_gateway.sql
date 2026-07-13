create schema if not exists private;

create table if not exists private.campus_ai_tool_events (
  id uuid primary key default gen_random_uuid(),
  request_uuid uuid not null unique,
  auth_user_id uuid not null,
  tool_name text not null,
  status text not null default 'running',
  latency_ms integer not null default 0,
  result_count integer not null default 0,
  error_code text,
  created_at timestamptz not null default now(),
  constraint campus_ai_tool_events_tool_check
    check (tool_name in ('official.search', 'web.search', 'web.read', 'document.fetch')),
  constraint campus_ai_tool_events_status_check
    check (status in ('running', 'success', 'error'))
);

create index if not exists campus_ai_tool_events_user_created_idx
  on private.campus_ai_tool_events (auth_user_id, created_at desc);

revoke all on table private.campus_ai_tool_events from public, anon, authenticated;
grant select, insert, update on table private.campus_ai_tool_events to service_role;

create or replace function private.reserve_campus_ai_tool_call(
  p_auth_user_id uuid,
  p_request_uuid uuid,
  p_tool_name text,
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = private, public
as $$
declare
  total_hour integer;
  searches_ten_minutes integer;
begin
  if p_auth_user_id is null or p_request_uuid is null or p_tool_name is null then
    return jsonb_build_object('allowed', false, 'error', 'invalid_request');
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_auth_user_id::text, 0));

  if exists (
    select 1 from private.campus_ai_tool_events
    where request_uuid = p_request_uuid and auth_user_id = p_auth_user_id
  ) then
    return jsonb_build_object('allowed', true, 'replayed', true);
  end if;

  select count(*) into total_hour
  from private.campus_ai_tool_events
  where auth_user_id = p_auth_user_id
    and created_at >= p_now - interval '1 hour';

  if total_hour >= 60 then
    return jsonb_build_object('allowed', false, 'error', 'rate_limited');
  end if;

  if p_tool_name in ('official.search', 'web.search') then
    select count(*) into searches_ten_minutes
    from private.campus_ai_tool_events
    where auth_user_id = p_auth_user_id
      and tool_name in ('official.search', 'web.search')
      and created_at >= p_now - interval '10 minutes';
    if searches_ten_minutes >= 20 then
      return jsonb_build_object('allowed', false, 'error', 'rate_limited');
    end if;
  end if;

  insert into private.campus_ai_tool_events (
    request_uuid, auth_user_id, tool_name, created_at
  ) values (
    p_request_uuid, p_auth_user_id, p_tool_name, p_now
  );

  return jsonb_build_object('allowed', true, 'replayed', false);
end;
$$;

create or replace function private.complete_campus_ai_tool_call(
  p_request_uuid uuid,
  p_status text,
  p_latency_ms integer,
  p_result_count integer,
  p_error_code text default null
)
returns void
language plpgsql
security definer
set search_path = private, public
as $$
begin
  update private.campus_ai_tool_events
  set status = case when p_status in ('success', 'error') then p_status else 'error' end,
      latency_ms = greatest(coalesce(p_latency_ms, 0), 0),
      result_count = greatest(coalesce(p_result_count, 0), 0),
      error_code = nullif(left(coalesce(p_error_code, ''), 120), '')
  where request_uuid = p_request_uuid;
end;
$$;

revoke all on function private.reserve_campus_ai_tool_call(uuid, uuid, text, timestamptz)
  from public, anon, authenticated;
revoke all on function private.complete_campus_ai_tool_call(uuid, text, integer, integer, text)
  from public, anon, authenticated;
grant execute on function private.reserve_campus_ai_tool_call(uuid, uuid, text, timestamptz)
  to service_role;
grant execute on function private.complete_campus_ai_tool_call(uuid, text, integer, integer, text)
  to service_role;
