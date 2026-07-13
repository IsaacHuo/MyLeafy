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
  '[]'::jsonb,
  false
)
on conflict (campus_id, semester_id) do update
set
  semester_start_date = excluded.semester_start_date,
  supported_weeks = excluded.supported_weeks,
  graduate_timetable_term_code = excluded.graduate_timetable_term_code,
  updated_at = now();

commit;

select pg_notify('pgrst', 'reload schema');
