-- EWAY LINK attendance automatic checkout.
-- Run this complete file once in the Supabase SQL Editor.
-- Open attendance sessions are closed at exactly check-in + 24 hours.

create extension if not exists pg_cron;

alter table public.attendance_sessions
  add column if not exists auto_checked_out boolean not null default false;

comment on column public.attendance_sessions.auto_checked_out is
  'True when EWAY LINK closed the attendance session automatically after 24 hours.';

create or replace function public.auto_checkout_expired_attendance_sessions()
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
  closed_count integer := 0;
begin
  update public.attendance_sessions
  set
    checked_out_at = checked_in_at + interval '24 hours',
    check_out_latitude = check_in_latitude,
    check_out_longitude = check_in_longitude,
    check_out_accuracy = check_in_accuracy,
    check_out_address = 'Automatic checkout after 24 hours',
    status = 'checked_out',
    auto_checked_out = true
  where checked_out_at is null
    and checked_in_at <= now() - interval '24 hours';

  get diagnostics closed_count = row_count;
  return closed_count;
end;
$function$;

revoke all on function public.auto_checkout_expired_attendance_sessions()
  from public, anon, authenticated;
grant execute on function public.auto_checkout_expired_attendance_sessions()
  to service_role;

comment on function public.auto_checkout_expired_attendance_sessions() is
  'Closes open attendance sessions at exactly 24 hours and returns the number closed.';

-- Cross-device access: attendance on Android unlocks the web portal too.
-- A session that overlaps the current Pakistan calendar day counts even when
-- it began the previous evening or was automatically closed today.
create or replace function public.has_attendance_today()
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select exists (
    select 1
    from public.attendance_sessions
    where employee_id = auth.uid()
      and checked_in_at < (
        (((now() at time zone 'Asia/Karachi')::date + 1)::timestamp)
        at time zone 'Asia/Karachi'
      )
      and coalesce(checked_out_at, now()) >= (
        (((now() at time zone 'Asia/Karachi')::date)::timestamp)
        at time zone 'Asia/Karachi'
      )
  );
$function$;

create or replace function public.has_active_attendance()
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select public.has_attendance_today();
$function$;

grant execute on function public.has_attendance_today() to authenticated;
grant execute on function public.has_active_attendance() to authenticated;

-- Replace an earlier copy of this named job, then check every five minutes.
do $block$
declare
  existing_job record;
begin
  for existing_job in
    select jobid
    from cron.job
    where jobname = 'eway-attendance-auto-checkout'
  loop
    perform cron.unschedule(existing_job.jobid);
  end loop;
end;
$block$;

select cron.schedule(
  'eway-attendance-auto-checkout',
  '*/5 * * * *',
  'select public.auto_checkout_expired_attendance_sessions();'
);

-- Close any session that was already older than 24 hours when this file ran.
select public.auto_checkout_expired_attendance_sessions();
