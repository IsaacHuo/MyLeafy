begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(20);

select ok(to_regclass('private.community_identity_link_conflicts') is not null, 'identity conflicts are auditable');
select ok(
  to_regclass('public.idx_profile_auth_links_profile_id_unique') is null
    and to_regclass('public.idx_profile_auth_links_profile_id') is not null,
  'a profile can retain multiple indexed device Auth links'
);
select ok(
  to_regclass('public.idx_profile_auth_links_campus_edu_id_unique') is null
    and to_regclass('public.idx_profile_auth_links_campus_edu_id') is not null,
  'a school identity can retain multiple indexed device Auth links'
);
select ok(
  has_function_privilege('service_role', 'public.edge_claim_community_identity(uuid,text,text,text)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.edge_claim_community_identity(uuid,text,text,text)', 'EXECUTE'),
  'only the bootstrap service can claim an identity'
);

select ok(
  has_function_privilege('authenticated', 'public.create_community_post_v2(uuid,text,text,text,boolean,boolean)', 'EXECUTE')
    and has_function_privilege('authenticated', 'public.create_community_comment_v1(uuid,uuid,text,boolean)', 'EXECUTE'),
  'authenticated clients can use the bounded mutation RPCs'
);
select ok(
  not has_table_privilege('authenticated', 'public.posts', 'INSERT')
    and not has_table_privilege('authenticated', 'public.comments', 'INSERT')
    and not has_table_privilege('authenticated', 'public.post_images', 'INSERT'),
  'direct community inserts are revoked'
);
select ok(to_regclass('public.idx_community_reports_open_post_unique') is not null, 'duplicate open post reports are prevented');
select unalike(
  pg_get_functiondef('public.report_community_content(text,uuid,uuid,uuid,text,text)'::regprocedure),
  '%update public.posts%',
  'reporting does not hide posts'
);
select unalike(
  pg_get_functiondef('public.report_community_content(text,uuid,uuid,uuid,text,text)'::regprocedure),
  '%update public.comments%',
  'reporting does not hide comments'
);

select ok(to_regclass('private.community_upload_receipts') is not null, 'validated upload receipts exist');
select ok(
  has_function_privilege('authenticated', 'public.attach_community_post_image_v1(uuid,uuid,integer)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.edge_record_community_upload_validation(uuid,uuid,text,text,text,text,integer,integer,integer,integer,integer,integer)', 'EXECUTE'),
  'clients can consume but cannot mint upload receipts'
);
select ok(
  to_regprocedure('public.publish_community_post_v1(uuid)') is null,
  'the obsolete standalone publish RPC is removed'
);
select ok(
  exists (select 1 from pg_trigger where tgname = 'community_posts_guard_status_transition' and not tgisinternal),
  'direct post status transitions are guarded'
);

select ok(to_regclass('private.campus_ai_usage_events') is null, 'managed AI usage events are retired');
select ok(to_regclass('private.campus_ai_entitlements') is null, 'managed AI entitlements are retired');
select ok(to_regclass('private.campus_ai_storekit_notification_ledger') is null, 'StoreKit notification ledger is retired');
select ok(to_regprocedure('public.edge_campus_ai_quota_snapshot(uuid,text,timestamptz)') is null, 'quota snapshot wrapper is retired');
select ok(to_regprocedure('public.edge_campus_ai_reserve_quota(uuid,uuid,text,text,timestamptz)') is null, 'quota reservation wrapper is retired');
select ok(to_regprocedure('public.edge_campus_ai_complete_usage(uuid,text,boolean,integer,integer,integer,integer,integer,integer,integer,integer,numeric,text)') is null, 'usage completion wrapper is retired');
select ok(to_regprocedure('public.edge_campus_ai_sync_entitlement(uuid,text,text,text,text,text,text,timestamptz,timestamptz,text,timestamptz)') is null, 'entitlement wrapper is retired');

select * from finish();
rollback;
