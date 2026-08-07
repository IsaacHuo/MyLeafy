begin;

-- Semester calendar metadata is public runtime configuration. The calendar-year
-- timetable needs the previous, active, and next rows, while school timetable
-- requests continue to use only the row marked is_active.
drop policy if exists "semester_runtime_configs_select_active"
on public.semester_runtime_configs;

drop policy if exists "semester_runtime_configs_select_timeline"
on public.semester_runtime_configs;

create policy "semester_runtime_configs_select_timeline"
on public.semester_runtime_configs
for select
to anon, authenticated
using (campus_id = 'bjfu');

update public.semester_runtime_configs as configs
set
  calendar_events = configs.calendar_events || jsonb_build_array(
    jsonb_build_object(
      'id', 'bjfu-second-semester-end-2026',
      'title', '第二学期结束',
      'start_date', '2026-07-26',
      'end_date', '2026-07-26',
      'kind', 'holiday',
      'academic_category', 'semester_end'
    ),
    jsonb_build_object(
      'id', 'bjfu-summer-break-2026',
      'title', '暑假',
      'start_date', '2026-07-27',
      'end_date', '2026-09-06',
      'kind', 'holiday',
      'academic_category', 'summer_break'
    )
  ),
  updated_at = now()
where configs.campus_id = 'bjfu'
  and configs.semester_id = '2025-2026-2'
  and not exists (
    select 1
    from jsonb_array_elements(configs.calendar_events) as event
    where coalesce(event->>'id', '') = 'bjfu-summer-break-2026'
  );

commit;

select pg_notify('pgrst', 'reload schema');
