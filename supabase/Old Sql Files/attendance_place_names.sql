-- EWAY LINK readable attendance place names.
-- Run once in the Supabase SQL Editor before using the updated app.

alter table public.attendance_sessions
  add column if not exists check_in_address text,
  add column if not exists check_out_address text;

alter table public.attendance_location_points
  add column if not exists place_name text;

comment on column public.attendance_sessions.check_in_address is
  'Human-readable place name resolved from the check-in GPS coordinates.';

comment on column public.attendance_sessions.check_out_address is
  'Human-readable place name resolved from the checkout GPS coordinates.';

comment on column public.attendance_location_points.place_name is
  'Human-readable place name resolved for the recorded tracking point.';
