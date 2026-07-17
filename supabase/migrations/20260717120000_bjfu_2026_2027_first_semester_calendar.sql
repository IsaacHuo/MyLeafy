begin;

insert into public.semester_runtime_configs (
  campus_id,
  semester_id,
  semester_start_date,
  supported_weeks,
  graduate_timetable_term_code,
  calendar_events,
  is_active
)
values (
  'bjfu',
  '2026-2027-1',
  date '2026-09-07',
  20,
  '47',
  jsonb_build_array(
    jsonb_build_object(
      'id', 'bjfu-anniversary-74-2026',
      'title', '建校74周年校庆日',
      'start_date', '2026-10-16',
      'end_date', '2026-10-16',
      'kind', 'holiday',
      'academic_category', 'important_date'
    ),
    jsonb_build_object(
      'id', 'bjfu-new-year-2027',
      'title', '元旦',
      'start_date', '2027-01-01',
      'end_date', '2027-01-03',
      'kind', 'holiday',
      'academic_category', 'public_holiday'
    ),
    jsonb_build_object(
      'id', 'bjfu-first-semester-end-2027',
      'title', '第一学期结束',
      'start_date', '2027-01-15',
      'end_date', '2027-01-15',
      'kind', 'holiday',
      'academic_category', 'semester_end'
    ),
    jsonb_build_object(
      'id', 'bjfu-winter-break-2027',
      'title', '寒假',
      'start_date', '2027-01-16',
      'end_date', '2027-02-27',
      'kind', 'holiday',
      'academic_category', 'winter_break'
    )
  ),
  false
)
on conflict (campus_id, semester_id) do update
set
  semester_start_date = excluded.semester_start_date,
  supported_weeks = excluded.supported_weeks,
  graduate_timetable_term_code = excluded.graduate_timetable_term_code,
  calendar_events = excluded.calendar_events,
  updated_at = now();

commit;

select pg_notify('pgrst', 'reload schema');
