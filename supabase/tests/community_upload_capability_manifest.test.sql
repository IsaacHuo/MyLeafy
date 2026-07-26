begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(3);

select is(
  (public.backend_capabilities_v1() ->> 'version')::integer,
  3,
  'community capability manifest reports version 3'
);

select ok(
  public.backend_capabilities_v1() -> 'edge_functions' ? 'community-validate-upload',
  'community capability manifest advertises the image upload validator'
);

select ok(
  (public.backend_capabilities_v1() -> 'rpcs' ->> 'create_community_post_v4')::boolean,
  'community capability manifest continues to advertise v4 post creation'
);

select * from finish();
rollback;
