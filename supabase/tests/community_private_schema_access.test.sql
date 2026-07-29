begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(4);

select ok(
  has_schema_privilege('authenticated', 'private', 'USAGE'),
  'authenticated users can reach private community implementation functions'
);

select ok(
  has_schema_privilege('service_role', 'private', 'USAGE'),
  'service role can reach private implementation functions'
);

select ok(
  not has_schema_privilege('anon', 'private', 'USAGE'),
  'anonymous role cannot use the private schema'
);

select ok(
  has_function_privilege(
    'authenticated',
    'private.community_feed_v1_impl(text,text,integer,text)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.community_feed_v1(text,text,integer,text)',
    'EXECUTE'
  ),
  'authenticated users can execute the community feed wrapper and implementation'
);

select * from finish();
rollback;
