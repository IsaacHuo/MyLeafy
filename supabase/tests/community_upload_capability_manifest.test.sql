begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(10);

select is(
  (public.backend_capabilities_v1() ->> 'version')::integer,
  8,
  'community capability manifest reports version 8'
);

select ok(
  public.backend_capabilities_v1() -> 'edge_functions' ? 'community-validate-upload',
  'community capability manifest advertises the image upload validator'
);

select ok(
  (public.backend_capabilities_v1() -> 'rpcs' ->> 'create_community_post_v4')::boolean,
  'community capability manifest continues to advertise v4 post creation'
);

select ok(
  (public.backend_capabilities_v1() -> 'rpcs' ->> 'create_community_post_v4_idempotent')::boolean,
  'community capability manifest advertises all idempotent post payload shapes'
);

select ok(
  (public.backend_capabilities_v1() -> 'rpcs' ->> 'create_community_comment_v2_idempotent')::boolean,
  'community capability manifest advertises all idempotent comment payload shapes'
);

select ok(
  not (public.backend_capabilities_v1() -> 'rpcs' ? 'publish_community_post_v1'),
  'community capability manifest omits the obsolete standalone publish RPC'
);

select ok(
  to_regprocedure('public.create_community_post_v4(uuid,text,text,boolean,integer,integer,uuid)') is not null
    and has_function_privilege(
      'authenticated',
      'public.create_community_post_v4(uuid,text,text,boolean,integer,integer,uuid)',
      'EXECUTE'
    ),
  'authenticated clients can call the category-omitting idempotent post overload'
);

select ok(
  to_regprocedure('public.admin_daily_counts(integer,text)') is null
    and to_regprocedure('public.admin_activity_heatmap(integer,text)') is null
    and to_regprocedure('public.admin_category_mix(integer,text)') is null
    and to_regprocedure('public.admin_top_content(integer,text,integer)') is null,
  'obsolete defaulted admin analytics overloads no longer cause ambiguous calls'
);

select ok(
  (public.backend_capabilities_v1() -> 'features' ->> 'timetable_sharing')::boolean,
  'timetable sharing requires every client mutation RPC'
);

select ok(
  to_regprocedure('public.create_community_comment_v2(uuid,uuid,text,boolean,uuid)') is not null,
  'top-level idempotent comment payloads remain resolvable'
);

select * from finish();
rollback;
