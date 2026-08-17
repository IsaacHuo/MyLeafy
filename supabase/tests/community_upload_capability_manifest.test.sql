begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(6);

select is(
  (public.backend_capabilities_v1() ->> 'version')::integer,
  7,
  'community capability manifest reports version 7'
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
  'community capability manifest advertises idempotent post creation'
);

select ok(
  (public.backend_capabilities_v1() -> 'rpcs' ->> 'create_community_comment_v2_idempotent')::boolean,
  'community capability manifest advertises idempotent comment creation'
);

select ok(
  not (public.backend_capabilities_v1() -> 'rpcs' ? 'publish_community_post_v1'),
  'community capability manifest omits the obsolete standalone publish RPC'
);

select * from finish();
rollback;
