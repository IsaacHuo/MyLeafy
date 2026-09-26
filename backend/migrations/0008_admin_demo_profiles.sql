-- Align operational user metrics with the current production schema.
ALTER TABLE profiles ADD COLUMN is_demo INTEGER GENERATED ALWAYS AS (
  lower(trim(coalesce(edu_id,'')))='review-demo'
  OR lower(trim(coalesce(edu_id,''))) LIKE 'review-demo-%'
) VIRTUAL;
