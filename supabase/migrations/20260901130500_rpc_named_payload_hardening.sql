-- Close remaining named-argument resolution gaps exposed through PostgREST.

-- Shipped clients may omit a null category while still sending a request ID.
create function public.create_community_post_v4(
  p_id uuid,
  p_title text,
  p_body text,
  p_is_anonymous boolean,
  p_image_count integer,
  p_attachment_count integer,
  p_request_id uuid
)
returns public.posts
language sql
security invoker
set search_path = public, pg_temp
as $$
  select public.create_community_post_v4(
    p_id,
    p_title,
    p_body,
    null,
    p_is_anonymous,
    p_image_count,
    p_attachment_count,
    p_request_id
  );
$$;

revoke all on function public.create_community_post_v4(uuid, text, text, boolean, integer, integer, uuid)
from public, anon;
grant execute on function public.create_community_post_v4(uuid, text, text, boolean, integer, integer, uuid)
to authenticated, service_role;

comment on function public.create_community_post_v4(uuid, text, text, boolean, integer, integer, uuid)
is 'Compatibility overload for idempotent post payloads that omit a null category.';

-- The campus-scoped replacements are the only live admin analytics contract.
-- Keeping both defaulted signatures makes omitted-argument calls ambiguous.
drop function public.admin_daily_counts(integer, text);
drop function public.admin_activity_heatmap(integer, text);
drop function public.admin_category_mix(integer, text);
drop function public.admin_top_content(integer, text, integer);

alter function public.backend_capabilities_v1()
  rename to backend_capabilities_v1_before_rpc_named_payload_hardening;

revoke all on function public.backend_capabilities_v1_before_rpc_named_payload_hardening()
from public, anon, authenticated;
grant execute on function public.backend_capabilities_v1_before_rpc_named_payload_hardening()
to service_role;

create function public.backend_capabilities_v1()
returns jsonb
language sql
stable
security definer
set search_path = public, private, pg_catalog
as $$
  with base as (
    select public.backend_capabilities_v1_before_rpc_named_payload_hardening() as value
  )
  select jsonb_set(
    jsonb_set(
      jsonb_set(value, '{version}', '8'::jsonb),
      '{features,timetable_sharing}',
      to_jsonb(
        (value -> 'features' ->> 'timetable_sharing')::boolean
        and to_regprocedure('public.create_timetable_invite(text)') is not null
        and to_regprocedure('public.accept_timetable_invite(text)') is not null
        and to_regprocedure('public.revoke_timetable_share(uuid,uuid)') is not null
        and to_regprocedure('public.stop_timetable_sharing()') is not null
        and to_regprocedure('public.leave_timetable_share(uuid)') is not null
      )
    ),
    '{rpcs}',
    coalesce(value -> 'rpcs', '{}'::jsonb) || jsonb_build_object(
      'create_community_post_v4_idempotent',
        to_regprocedure('public.create_community_post_v4(uuid,text,text,text,boolean,integer,integer,uuid)') is not null
        and to_regprocedure('public.create_community_post_v4(uuid,text,text,boolean,integer,integer,uuid)') is not null,
      'create_community_comment_v2_idempotent',
        to_regprocedure('public.create_community_comment_v2(uuid,uuid,text,uuid,uuid,boolean,uuid)') is not null
        and to_regprocedure('public.create_community_comment_v2(uuid,uuid,text,boolean,uuid)') is not null
    )
  )
  from base;
$$;

revoke all on function public.backend_capabilities_v1() from public, anon, authenticated;
grant execute on function public.backend_capabilities_v1() to anon, authenticated, service_role;

comment on function public.backend_capabilities_v1()
is 'Returns backend capability manifest version 8 with resolvable named-payload contracts.';

select pg_notify('pgrst', 'reload schema');
