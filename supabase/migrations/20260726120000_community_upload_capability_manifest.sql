create or replace function public.backend_capabilities_v1()
returns jsonb
language sql
stable
security definer
set search_path = public, private, pg_catalog
as $$
  with base as (
    select public.backend_capabilities_v1_before_community_interactions() as value
  )
  select jsonb_set(
    jsonb_set(
      jsonb_set(
        value,
        '{version}',
        '3'::jsonb
      ),
      '{features}',
      coalesce(value -> 'features', '{}'::jsonb) || jsonb_build_object(
        'community_comment_threads',
          to_regprocedure('public.list_community_comment_threads_v1(uuid,timestamptz,uuid,integer)') is not null
          and to_regprocedure('public.toggle_community_comment_like_v1(uuid,uuid)') is not null,
        'community_post_attachments',
          to_regclass('public.post_attachments') is not null
          and to_regprocedure('public.create_community_post_v4(uuid,text,text,text,boolean,integer,integer)') is not null
      )
    ),
    '{rpcs}',
    coalesce(value -> 'rpcs', '{}'::jsonb) || jsonb_build_object(
      'create_community_post_v4',
        to_regprocedure('public.create_community_post_v4(uuid,text,text,text,boolean,integer,integer)') is not null,
      'create_community_comment_v2',
        to_regprocedure('public.create_community_comment_v2(uuid,uuid,text,uuid,uuid,boolean)') is not null,
      'list_community_comment_threads_v1',
        to_regprocedure('public.list_community_comment_threads_v1(uuid,timestamptz,uuid,integer)') is not null,
      'toggle_community_comment_like_v1',
        to_regprocedure('public.toggle_community_comment_like_v1(uuid,uuid)') is not null,
      'attach_community_post_attachment_v1',
        to_regprocedure('public.attach_community_post_attachment_v1(uuid,uuid,integer)') is not null,
      'abort_community_post_upload_v1',
        to_regprocedure('public.abort_community_post_upload_v1(uuid)') is not null
    )
  )
  || jsonb_build_object(
    'edge_functions',
    coalesce(value -> 'edge_functions', '[]'::jsonb)
      || '["community-validate-upload","community-validate-attachment","community-attachment-download","community-media-cleanup"]'::jsonb
  )
  from base;
$$;

revoke all on function public.backend_capabilities_v1() from public, anon, authenticated;
grant execute on function public.backend_capabilities_v1() to anon, authenticated, service_role;

comment on function public.backend_capabilities_v1()
is 'Returns backend capability manifest version 3, including both image and attachment validators.';

select pg_notify('pgrst', 'reload schema');
