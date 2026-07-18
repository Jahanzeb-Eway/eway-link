-- EWAY LINK continuous attendance tracking. Run once after attendance_foundation.sql.
create table if not exists public.attendance_sessions (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(id) on delete cascade,
  work_date date not null default ((now() at time zone 'Asia/Karachi')::date),
  checked_in_at timestamptz not null default now(),
  checked_out_at timestamptz,
  check_in_latitude double precision not null,
  check_in_longitude double precision not null,
  check_in_accuracy double precision not null,
  check_out_latitude double precision,
  check_out_longitude double precision,
  check_out_accuracy double precision,
  status text not null default 'checked_in' check (status in ('checked_in','checked_out')),
  created_at timestamptz not null default now(),
  constraint checkout_after_checkin check (checked_out_at is null or checked_out_at >= checked_in_at),
  unique (employee_id, work_date)
);

create unique index if not exists one_open_attendance_per_employee
on public.attendance_sessions(employee_id) where checked_out_at is null;

create table if not exists public.attendance_location_points (
  id bigint generated always as identity primary key,
  session_id uuid not null references public.attendance_sessions(id) on delete cascade,
  employee_id uuid not null references public.profiles(id) on delete cascade,
  recorded_at timestamptz not null default now(),
  latitude double precision not null,
  longitude double precision not null,
  accuracy double precision not null,
  altitude double precision,
  speed double precision,
  heading double precision,
  is_mocked boolean not null default false
);

create index if not exists attendance_points_session_time
on public.attendance_location_points(session_id, recorded_at);

alter table public.attendance_sessions enable row level security;
alter table public.attendance_location_points enable row level security;

drop policy if exists "attendance_read_own_or_owner" on public.attendance_sessions;
create policy "attendance_read_own_or_owner" on public.attendance_sessions
for select to authenticated using (employee_id = auth.uid() or public.is_owner());

drop policy if exists "attendance_insert_own" on public.attendance_sessions;
create policy "attendance_insert_own" on public.attendance_sessions
for insert to authenticated with check (employee_id = auth.uid());

drop policy if exists "attendance_update_own" on public.attendance_sessions;
create policy "attendance_update_own" on public.attendance_sessions
for update to authenticated using (employee_id = auth.uid()) with check (employee_id = auth.uid());

drop policy if exists "points_read_own_or_owner" on public.attendance_location_points;
create policy "points_read_own_or_owner" on public.attendance_location_points
for select to authenticated using (employee_id = auth.uid() or public.is_owner());

drop policy if exists "points_insert_own" on public.attendance_location_points;
create policy "points_insert_own" on public.attendance_location_points
for insert to authenticated with check (
  employee_id = auth.uid() and exists (
    select 1 from public.attendance_sessions s
    where s.id = session_id and s.employee_id = auth.uid() and s.checked_out_at is null
  )
);
