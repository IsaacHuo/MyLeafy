create or replace function public.backend_capabilities_v1()
returns jsonb
language sql
stable
security definer
set search_path = public, private, pg_catalog
as $$
  select jsonb_build_object(
    'version', 1,
    'generated_at', now(),
    'features', jsonb_build_object(
      'community_feed',
        to_regprocedure('public.community_feed_v1(text,text,integer,text)') is not null
        or to_regprocedure('public.community_feed_v1(text,text,integer)') is not null,
      'community_hot_posts',
        to_regprocedure('public.community_hot_posts_v1(integer,integer,text)') is not null
        or to_regprocedure('public.community_hot_posts_v1(integer,integer)') is not null,
      'community_polls',
        to_regclass('public.community_polls') is not null
        and to_regclass('public.community_poll_options') is not null
        and to_regclass('public.community_poll_votes') is not null,
      'community_notifications',
        to_regclass('public.community_notifications') is not null,
      'post_favorites',
        to_regclass('public.post_favorites') is not null,
      'catalog_ratings',
        to_regclass('public.teachers') is not null
        and to_regclass('public.teacher_ratings') is not null
        and to_regclass('public.course_catalog') is not null
        and to_regclass('public.course_ratings') is not null
        and to_regclass('public.dish_catalog') is not null
        and to_regclass('public.dish_ratings') is not null,
      'postgraduate_sources',
        to_regclass('public.postgraduate_sources') is not null
        and to_regclass('public.postgraduate_source_suggestions') is not null,
      'timetable_sharing',
        to_regclass('public.timetable_snapshots') is not null
        and to_regclass('public.timetable_invites') is not null
        and to_regclass('public.timetable_share_members') is not null
        and to_regprocedure('public.create_timetable_invite(text)') is not null
        and to_regprocedure('public.accept_timetable_invite(text)') is not null,
      'campus_runtime',
        to_regclass('public.semester_runtime_configs') is not null
        and to_regclass('public.national_calendar_runtime_configs') is not null,
      'campus_weather',
        to_regclass('public.campus_weather_cache') is not null,
      'school_community_access',
        to_regclass('public.campuses') is not null
        and to_regclass('public.campus_membership_requests') is not null
        and to_regprocedure('public.current_profile_campus_id()') is not null,
      'campus_ai',
        to_regclass('private.campus_ai_usage_events') is not null,
      'campus_ai_managed_entitlements',
        to_regclass('private.campus_ai_entitlements') is not null,
      'admin_console',
        to_regclass('public.admin_accounts') is not null
        and to_regclass('public.admin_audit_logs') is not null
    ),
    'rpcs', jsonb_build_object(
      'community_feed_v1',
        to_regprocedure('public.community_feed_v1(text,text,integer,text)') is not null
        or to_regprocedure('public.community_feed_v1(text,text,integer)') is not null,
      'community_hot_posts_v1',
        to_regprocedure('public.community_hot_posts_v1(integer,integer,text)') is not null
        or to_regprocedure('public.community_hot_posts_v1(integer,integer)') is not null,
      'my_authored_community_polls_v1',
        to_regprocedure('public.my_authored_community_polls_v1(integer)') is not null,
      'my_voted_community_polls_v1',
        to_regprocedure('public.my_voted_community_polls_v1(integer)') is not null,
      'request_delete_community_poll_v1',
        to_regprocedure('public.request_delete_community_poll_v1(uuid,text)') is not null,
      'community_profile_stats_v1',
        to_regprocedure('public.community_profile_stats_v1(uuid[])') is not null,
      'community_post_summary_v1',
        to_regprocedure('public.community_post_summary_v1(uuid)') is not null,
      'toggle_post_like_v1',
        to_regprocedure('public.toggle_post_like_v1(uuid)') is not null,
      'toggle_post_favorite_v1',
        to_regprocedure('public.toggle_post_favorite_v1(uuid)') is not null,
      'create_timetable_invite',
        to_regprocedure('public.create_timetable_invite(text)') is not null,
      'accept_timetable_invite',
        to_regprocedure('public.accept_timetable_invite(text)') is not null,
      'stop_timetable_sharing',
        to_regprocedure('public.stop_timetable_sharing()') is not null,
      'leave_timetable_share',
        to_regprocedure('public.leave_timetable_share(uuid)') is not null,
      'revoke_timetable_share',
        to_regprocedure('public.revoke_timetable_share(uuid,uuid)') is not null,
      'admin_daily_counts',
        to_regprocedure('public.admin_daily_counts(integer,text,text)') is not null,
      'admin_activity_heatmap',
        to_regprocedure('public.admin_activity_heatmap(integer,text,text)') is not null,
      'admin_category_mix',
        to_regprocedure('public.admin_category_mix(integer,text,text)') is not null,
      'admin_top_content',
        to_regprocedure('public.admin_top_content(integer,text,integer,text)') is not null
    ),
    'edge_functions', jsonb_build_array(
      'admin-community',
      'admin-login',
      'admin-me',
      'admin-logout',
      'community-bootstrap-user',
      'community-feed',
      'campus-request',
      'campus-weather',
      'campus-ai-assistant',
      'campus-ai-entitlement',
      'app-store-server-notifications'
    )
  );
$$;

revoke all on function public.backend_capabilities_v1() from public, anon, authenticated;
grant execute on function public.backend_capabilities_v1() to anon, authenticated, service_role;

comment on function public.backend_capabilities_v1()
  is 'Stable backend capability manifest for clients. Use this instead of probing missing tables/RPCs by catching errors.';
