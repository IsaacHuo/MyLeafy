begin;

do $$
begin
  if exists (
    select 1
    from cron.job
    where jobname = 'leafy-semester-runtime-reconcile'
  ) then
    perform cron.unschedule('leafy-semester-runtime-reconcile');
  end if;
end
$$;

drop trigger if exists semester_runtime_configs_prevent_future_active
on public.semester_runtime_configs;

drop trigger if exists semester_runtime_configs_reconcile_active_after_write
on public.semester_runtime_configs;

drop function if exists public.semester_runtime_configs_prevent_future_active();
drop function if exists public.semester_runtime_configs_reconcile_active_after_write();
drop function if exists public.reconcile_semester_runtime_active_config(text, date);
drop function if exists public.leafy_semester_effective_date();

create or replace function public.admin_upsert_semester_runtime_config(
  p_id uuid,
  p_campus_id text,
  p_semester_id text,
  p_semester_start_date date,
  p_supported_weeks integer,
  p_graduate_timetable_term_code text,
  p_calendar_events jsonb,
  p_is_active boolean,
  p_actor_id uuid
)
returns public.semester_runtime_configs
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  saved public.semester_runtime_configs%rowtype;
  normalized_campus_id text := nullif(btrim(coalesce(p_campus_id, '')), '');
  was_active boolean := false;
begin
  if normalized_campus_id is null then
    raise exception 'ADMIN_CAMPUS_ID_REQUIRED';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('leafy.semester-runtime:' || normalized_campus_id, 0)
  );

  if p_id is null then
    select configs.is_active
    into was_active
    from public.semester_runtime_configs as configs
    where configs.campus_id = normalized_campus_id
      and configs.semester_id = p_semester_id
    for update;

    insert into public.semester_runtime_configs (
      campus_id,
      semester_id,
      semester_start_date,
      supported_weeks,
      graduate_timetable_term_code,
      calendar_events,
      is_active,
      created_by,
      updated_by
    )
    values (
      normalized_campus_id,
      p_semester_id,
      p_semester_start_date,
      p_supported_weeks,
      p_graduate_timetable_term_code,
      coalesce(p_calendar_events, '[]'::jsonb),
      false,
      p_actor_id,
      p_actor_id
    )
    on conflict (campus_id, semester_id) do update
    set
      semester_start_date = excluded.semester_start_date,
      supported_weeks = excluded.supported_weeks,
      graduate_timetable_term_code = excluded.graduate_timetable_term_code,
      calendar_events = excluded.calendar_events,
      is_active = false,
      updated_by = excluded.updated_by
    returning * into saved;
  else
    select configs.is_active
    into was_active
    from public.semester_runtime_configs as configs
    where configs.id = p_id
      and configs.campus_id = normalized_campus_id
    for update;

    update public.semester_runtime_configs as configs
    set
      semester_id = p_semester_id,
      semester_start_date = p_semester_start_date,
      supported_weeks = p_supported_weeks,
      graduate_timetable_term_code = p_graduate_timetable_term_code,
      calendar_events = coalesce(p_calendar_events, '[]'::jsonb),
      is_active = false,
      updated_by = p_actor_id
    where configs.id = p_id
      and configs.campus_id = normalized_campus_id
    returning configs.* into saved;

    if saved.id is null then
      raise exception 'ADMIN_SEMESTER_RUNTIME_CONFIG_NOT_FOUND';
    end if;
  end if;

  if coalesce(p_is_active, false) then
    update public.semester_runtime_configs as configs
    set
      is_active = false,
      updated_by = p_actor_id
    where configs.campus_id = normalized_campus_id
      and configs.is_active = true
      and configs.id <> saved.id;

    update public.semester_runtime_configs as configs
    set
      is_active = true,
      updated_by = p_actor_id
    where configs.id = saved.id
    returning configs.* into saved;
  elsif was_active then
    raise exception 'ADMIN_ACTIVE_SEMESTER_REQUIRED';
  end if;

  return saved;
end;
$$;

update public.semester_runtime_configs
set is_active = false
where campus_id = 'bjfu'
  and is_active = true;

update public.semester_runtime_configs
set
  is_active = true,
  updated_at = now()
where campus_id = 'bjfu'
  and semester_id = '2026-2027-1'
  and semester_start_date = date '2026-09-07'
  and supported_weeks = 20
  and graduate_timetable_term_code = '47';

do $$
begin
  if (
    select count(*)
    from public.semester_runtime_configs
    where campus_id = 'bjfu'
      and is_active
  ) <> 1 then
    raise exception 'BJFU_ACTIVE_SEMESTER_INVALID';
  end if;

  if not exists (
    select 1
    from public.semester_runtime_configs
    where campus_id = 'bjfu'
      and semester_id = '2026-2027-1'
      and is_active
  ) then
    raise exception 'BJFU_NEXT_SEMESTER_ACTIVATION_FAILED';
  end if;
end
$$;

commit;

select pg_notify('pgrst', 'reload schema');
