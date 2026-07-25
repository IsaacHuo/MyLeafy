-- Close two database lint failures that affect admin/community state transitions.

create or replace function private.create_community_poll_v1_impl(
  p_question text,
  p_detail text default null,
  p_options text[] default array[]::text[],
  p_closes_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_id uuid := public.current_profile_id();
  normalized_question text := nullif(btrim(coalesce(p_question, '')), '');
  normalized_detail text := nullif(btrim(coalesce(p_detail, '')), '');
  normalized_options text[] := array[]::text[];
  option_text text;
  created_poll_id uuid;
  option_index integer := 0;
begin
  if current_profile_id is null then
    raise exception 'COMMUNITY_PROFILE_REQUIRED';
  end if;

  if not exists (
    select 1
    from public.profiles
    where profiles.id = current_profile_id
      and profiles.is_profile_complete = true
      and nullif(btrim(profiles.nickname), '') is not null
  ) then
    raise exception 'PROFILE_COMPLETION_REQUIRED';
  end if;

  if not public.has_accepted_community_terms(public.community_latest_terms_version()) then
    raise exception 'COMMUNITY_TERMS_REQUIRED';
  end if;

  if public.is_profile_muted(current_profile_id) then
    raise exception 'COMMUNITY_USER_MUTED';
  end if;

  if normalized_question is null or char_length(normalized_question) > 120 then
    raise exception 'COMMUNITY_POLL_INVALID';
  end if;

  if normalized_detail is not null and char_length(normalized_detail) > 500 then
    raise exception 'COMMUNITY_POLL_INVALID';
  end if;

  if p_closes_at is not null and p_closes_at <= now() then
    raise exception 'COMMUNITY_POLL_INVALID';
  end if;

  foreach option_text in array coalesce(p_options, array[]::text[]) loop
    option_text := nullif(btrim(coalesce(option_text, '')), '');
    if option_text is not null then
      if char_length(option_text) > 80 then
        raise exception 'COMMUNITY_POLL_INVALID';
      end if;
      normalized_options := array_append(normalized_options, option_text);
    end if;
  end loop;

  if coalesce(array_length(normalized_options, 1), 0) < 2
     or coalesce(array_length(normalized_options, 1), 0) > 6 then
    raise exception 'COMMUNITY_POLL_INVALID';
  end if;

  insert into public.community_polls (author_id, question, detail, closes_at, status)
  values (current_profile_id, normalized_question, normalized_detail, p_closes_at, 'pending_review')
  returning id into created_poll_id;

  foreach option_text in array normalized_options loop
    insert into public.community_poll_options (poll_id, text, sort_order)
    values (created_poll_id, option_text, option_index);
    option_index := option_index + 1;
  end loop;

  return private.community_poll_summary_v1_impl(created_poll_id);
end;
$$;

create or replace function public.admin_approve_campus_request_v1(
  p_request_id uuid,
  p_admin_id uuid,
  p_campus_id text default null,
  p_display_name text default null,
  p_short_name text default null,
  p_new_campus_id text default null,
  p_admin_note text default null
)
returns public.campus_membership_requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  request_row public.campus_membership_requests%rowtype;
  target_campus_id text;
  target_display_name text;
  target_normalized_name text;
begin
  select *
  into request_row
  from public.campus_membership_requests
  where id = p_request_id
  for update;

  if request_row.id is null then
    raise exception 'COMMUNITY_REQUEST_NOT_FOUND' using errcode = 'P0001';
  end if;
  if request_row.status <> 'pending' then
    raise exception 'ADMIN_CAMPUS_REQUEST_ALREADY_REVIEWED' using errcode = 'P0001';
  end if;

  if request_row.request_type = 'school_change' then
    target_campus_id := request_row.requested_campus_id;
  elsif nullif(lower(btrim(coalesce(p_campus_id, ''))), '') is not null
    and lower(btrim(p_campus_id)) <> 'new' then
    target_campus_id := lower(btrim(p_campus_id));
  else
    target_display_name := coalesce(nullif(btrim(p_display_name), ''), request_row.school_name);
    target_normalized_name := public.normalize_school_name(target_display_name);
    if target_normalized_name in (
      public.normalize_school_name('北京林业大学'),
      public.normalize_school_name('北林')
    ) then
      raise exception 'ADMIN_INVALID_CAMPUS_TARGET' using errcode = '22023';
    end if;

    select campuses.id
    into target_campus_id
    from public.campuses
    where campuses.normalized_name = target_normalized_name;

    if target_campus_id is null then
      target_campus_id := lower(btrim(coalesce(
        nullif(p_new_campus_id, ''),
        'campus-' || replace(request_row.id::text, '-', '')
      )));
      insert into public.campuses (
        id,
        display_name,
        short_name,
        connector_kind,
        status,
        normalized_name,
        is_community_enabled,
        is_system
      )
      values (
        target_campus_id,
        target_display_name,
        coalesce(nullif(btrim(p_short_name), ''), left(target_display_name, 6)),
        'custom',
        'active',
        target_normalized_name,
        true,
        false
      );
    end if;
  end if;

  if target_campus_id is null
    or target_campus_id = 'general'
    or (request_row.request_type <> 'school_change' and target_campus_id = 'bjfu') then
    raise exception 'ADMIN_INVALID_CAMPUS_TARGET' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.campuses
    where campuses.id = target_campus_id
      and campuses.status = 'active'
      and campuses.is_community_enabled
  ) then
    raise exception 'COMMUNITY_CAMPUS_NOT_FOUND' using errcode = 'P0001';
  end if;

  return public.approve_campus_membership_request(
    request_row.id,
    target_campus_id,
    p_admin_id,
    p_admin_note
  );
end;
$$;
