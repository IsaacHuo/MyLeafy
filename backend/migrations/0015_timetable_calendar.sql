-- A shared timetable owns its date anchor and class times independently of viewers.
ALTER TABLE timetable_snapshots ADD COLUMN calendar_config TEXT
  CHECK (calendar_config IS NULL OR json_valid(calendar_config));
