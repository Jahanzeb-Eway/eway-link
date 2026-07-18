-- EWAY LINK Attendance + Annual Leave Management
-- Run this COMPLETE file once in Supabase SQL Editor.

-- Statements are intentionally not wrapped in one transaction. If an optional
-- notification component needs attention, the core leave tables and RPCs still
-- remain installed and usable.

create table if not exists public.leave_requests (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(id) on delete cascade,
  leave_year integer not null,
  start_date date not null,
  end_date date not null,
  working_days integer not null check (working_days > 0),
  reason text not null check (length(trim(reason)) >= 3),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_date >= start_date),
  check (leave_year = extract(year from start_date)::integer),
  check (extract(year from start_date) = extract(year from end_date))
);

create index if not exists leave_requests_employee_year_idx
  on public.leave_requests(employee_id, leave_year, status);
create index if not exists leave_requests_owner_queue_idx
  on public.leave_requests(status, created_at desc);
create index if not exists leave_requests_date_range_idx
  on public.leave_requests(start_date, end_date)
  where status = 'approved';

alter table public.leave_requests enable row level security;

drop policy if exists "employees_read_own_leave" on public.leave_requests;
create policy "employees_read_own_leave"
on public.leave_requests for select to authenticated
using (employee_id = auth.uid() or public.is_owner());

drop policy if exists "owners_manage_leave" on public.leave_requests;
create policy "owners_manage_leave"
on public.leave_requests for all to authenticated
using (public.is_owner())
with check (public.is_owner());

revoke all on public.leave_requests from anon;
grant select on public.leave_requests to authenticated;

create or replace function public.count_leave_working_days(
  p_start_date date,
  p_end_date date
)
returns integer
language sql
immutable
as $$
  select count(*)::integer
  from generate_series(p_start_date, p_end_date, interval '1 day') day_value
  where extract(isodow from day_value) between 1 and 5;
$$;

create or replace function public.get_leave_balance(
  p_employee_id uuid,
  p_year integer
)
returns table (
  leave_year integer,
  annual_allowance integer,
  approved_days integer,
  pending_days integer,
  remaining_days integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_approved integer;
  v_pending integer;
begin
  if auth.uid() is null then
    raise exception 'Login is required.';
  end if;
  if auth.uid() <> p_employee_id and not public.is_owner() then
    raise exception 'You may only view your own leave balance.';
  end if;

  select
    coalesce(sum(working_days) filter (where status = 'approved'), 0)::integer,
    coalesce(sum(working_days) filter (where status = 'pending'), 0)::integer
  into v_approved, v_pending
  from public.leave_requests
  where employee_id = p_employee_id
    and leave_year = p_year;

  return query select
    p_year,
    21,
    v_approved,
    v_pending,
    greatest(21 - v_approved, 0);
end;
$$;

create or replace function public.get_my_leave_balance(p_year integer)
returns table (
  leave_year integer,
  annual_allowance integer,
  approved_days integer,
  pending_days integer,
  remaining_days integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_approved integer;
  v_pending integer;
begin
  if auth.uid() is null then
    raise exception 'Login is required.';
  end if;
  select
    coalesce(sum(working_days) filter (where status = 'approved'), 0)::integer,
    coalesce(sum(working_days) filter (where status = 'pending'), 0)::integer
  into v_approved, v_pending
  from public.leave_requests
  where employee_id = auth.uid()
    and leave_year = p_year;

  return query select
    p_year,
    21,
    v_approved,
    v_pending,
    greatest(21 - v_approved, 0);
end;
$$;

create or replace function public.apply_for_leave(
  p_start_date date,
  p_end_date date,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user public.profiles%rowtype;
  v_days integer;
  v_used integer;
  v_pending integer;
  v_id uuid;
  v_today date := (now() at time zone 'Asia/Karachi')::date;
begin
  if auth.uid() is null then
    raise exception 'Login is required.';
  end if;

  select * into v_user from public.profiles where id = auth.uid();
  if not found or not v_user.is_active then
    raise exception 'An active employee account is required.';
  end if;
  if v_user.role = 'owner' then
    raise exception 'Owner accounts do not use employee annual leave.';
  end if;
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'Select a valid leave date range.';
  end if;
  if p_start_date < v_today then
    raise exception 'Leave cannot start before today.';
  end if;
  if extract(year from p_start_date) <> extract(year from p_end_date) then
    raise exception 'A leave request must stay within one calendar year.';
  end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then
    raise exception 'Enter a reason for leave.';
  end if;

  v_days := public.count_leave_working_days(p_start_date, p_end_date);
  if v_days < 1 then
    raise exception 'Saturday and Sunday are off and cannot be requested as leave.';
  end if;

  if exists (
    select 1 from public.leave_requests
    where employee_id = auth.uid()
      and status in ('pending', 'approved')
      and daterange(start_date, end_date, '[]') && daterange(p_start_date, p_end_date, '[]')
  ) then
    raise exception 'These dates overlap an existing leave request.';
  end if;

  select
    coalesce(sum(working_days) filter (where status = 'approved'), 0)::integer,
    coalesce(sum(working_days) filter (where status = 'pending'), 0)::integer
  into v_used, v_pending
  from public.leave_requests
  where employee_id = auth.uid()
    and leave_year = extract(year from p_start_date)::integer;

  if v_used + v_pending + v_days > 21 then
    raise exception 'This request exceeds the 21-day annual leave entitlement.';
  end if;

  insert into public.leave_requests (
    employee_id, leave_year, start_date, end_date, working_days, reason
  ) values (
    auth.uid(), extract(year from p_start_date)::integer,
    p_start_date, p_end_date, v_days, trim(p_reason)
  ) returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.review_leave_request(
  p_request_id uuid,
  p_approve boolean,
  p_review_note text default ''
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.leave_requests%rowtype;
  v_approved integer;
begin
  if not public.is_owner() then
    raise exception 'Only the owner can approve or reject leave.';
  end if;

  select * into v_request
  from public.leave_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'Leave request not found.';
  end if;
  if v_request.status <> 'pending' then
    raise exception 'This leave request has already been reviewed.';
  end if;

  if p_approve then
    select coalesce(sum(working_days), 0)::integer into v_approved
    from public.leave_requests
    where employee_id = v_request.employee_id
      and leave_year = v_request.leave_year
      and status = 'approved';
    if v_approved + v_request.working_days > 21 then
      raise exception 'Approval would exceed the employee''s 21-day entitlement.';
    end if;
  end if;

  update public.leave_requests
  set status = case when p_approve then 'approved' else 'rejected' end,
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      review_note = nullif(trim(coalesce(p_review_note, '')), ''),
      updated_at = now()
  where id = p_request_id;
end;
$$;

revoke all on function public.count_leave_working_days(date, date) from public;
revoke all on function public.get_leave_balance(uuid, integer) from public;
revoke all on function public.get_my_leave_balance(integer) from public;
revoke all on function public.apply_for_leave(date, date, text) from public;
revoke all on function public.review_leave_request(uuid, boolean, text) from public;
grant execute on function public.get_my_leave_balance(integer) to authenticated;
grant execute on function public.apply_for_leave(date, date, text) to authenticated;
grant execute on function public.review_leave_request(uuid, boolean, text) to authenticated;

-- A check-in at any time today unlocks operational modules for the whole day.
create or replace function public.has_attendance_today()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.attendance_sessions
    where employee_id = auth.uid()
      and work_date = (now() at time zone 'Asia/Karachi')::date
  );
$$;

create or replace function public.has_active_attendance()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_attendance_today();
$$;

grant execute on function public.has_attendance_today() to authenticated;
grant execute on function public.has_active_attendance() to authenticated;

-- Use the existing notification centre for leave workflow updates.
alter table public.attendance_notifications
  drop constraint if exists attendance_notifications_event_type_check;
alter table public.attendance_notifications
  add constraint attendance_notifications_event_type_check
  check (event_type in (
    'check_in', 'check_out', 'system',
    'leave_request', 'leave_approved', 'leave_rejected'
  ));

drop policy if exists "owners_read_own_attendance_notifications"
  on public.attendance_notifications;
drop policy if exists "owners_update_own_attendance_notifications"
  on public.attendance_notifications;
drop policy if exists "users_read_own_notifications"
  on public.attendance_notifications;
drop policy if exists "users_update_own_notifications"
  on public.attendance_notifications;
create policy "users_read_own_notifications"
on public.attendance_notifications for select to authenticated
using (recipient_id = auth.uid());
create policy "users_update_own_notifications"
on public.attendance_notifications for update to authenticated
using (recipient_id = auth.uid())
with check (recipient_id = auth.uid());

create or replace function public.create_leave_notifications()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_remaining integer;
begin
  select coalesce(nullif(trim(full_name), ''), 'Employee')
  into v_name from public.profiles where id = new.employee_id;

  if tg_op = 'INSERT' then
    insert into public.attendance_notifications (
      recipient_id, employee_id, event_type, title, message, occurred_at
    )
    select owner_profile.id, new.employee_id, 'leave_request',
      v_name || ' applied for leave',
      v_name || ' requested ' || new.working_days || ' working day(s) from ' ||
        to_char(new.start_date, 'DD Mon YYYY') || ' to ' ||
        to_char(new.end_date, 'DD Mon YYYY') || '.',
      now()
    from public.profiles owner_profile
    where owner_profile.role = 'owner' and owner_profile.is_active = true;
  elsif old.status = 'pending' and new.status in ('approved', 'rejected') then
    select greatest(21 - coalesce(sum(working_days), 0), 0)::integer
    into v_remaining
    from public.leave_requests
    where employee_id = new.employee_id
      and leave_year = new.leave_year
      and status = 'approved';

    insert into public.attendance_notifications (
      recipient_id, employee_id, event_type, title, message, occurred_at
    ) values (
      new.employee_id,
      new.employee_id,
      case when new.status = 'approved' then 'leave_approved' else 'leave_rejected' end,
      case when new.status = 'approved' then 'Leave approved' else 'Leave rejected' end,
      case when new.status = 'approved'
        then 'Your leave from ' || to_char(new.start_date, 'DD Mon YYYY') ||
          ' to ' || to_char(new.end_date, 'DD Mon YYYY') ||
          ' was approved. ' || v_remaining || ' annual leave day(s) remain.'
        else 'Your leave from ' || to_char(new.start_date, 'DD Mon YYYY') ||
          ' to ' || to_char(new.end_date, 'DD Mon YYYY') || ' was rejected.'
      end,
      now()
    );
  end if;
  return new;
end;
$$;

drop trigger if exists leave_notification_trigger on public.leave_requests;
create trigger leave_notification_trigger
after insert or update of status on public.leave_requests
for each row execute function public.create_leave_notifications();

create or replace function public.route_attendance_push_notifications()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.event_type not in (
    'check_in', 'check_out', 'leave_request', 'leave_approved', 'leave_rejected'
  ) then
    return new;
  end if;

  perform public.enqueue_push_notification(
    new.recipient_id,
    new.event_type,
    new.title,
    new.message,
    jsonb_build_object(
      'route', '/attendance',
      'session_id', coalesce(new.session_id::text, ''),
      'employee_id', coalesce(new.employee_id::text, ''),
      'event_type', new.event_type
    ),
    'attendance:' || new.id::text || ':' || new.recipient_id::text
  );
  return new;
end;
$$;

-- End of installation.
