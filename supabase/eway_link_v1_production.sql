-- EWAY LINK ERP - VERSION 1 PRODUCTION DATABASE
-- Canonical installer generated from the verified production SQL history.
-- Run this COMPLETE file in Supabase SQL Editor using the postgres role.
-- Safe to rerun: definitions are idempotent and preserve operational data.
-- This file does NOT reset or delete production records.


-- ============================================================================
-- MODULE 1: attendance_foundation.sql
-- ============================================================================

-- EWAY LINK Attendance Foundation
-- Run once in the Supabase SQL Editor.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  role text not null default 'employee'
    check (role in ('owner', 'coordinator', 'employee')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

create or replace function public.is_owner()
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'owner' and is_active = true
  );
$$;

alter table public.profiles enable row level security;

drop policy if exists "profiles_read_own_or_owner" on public.profiles;
create policy "profiles_read_own_or_owner"
on public.profiles for select
to authenticated
using (id = auth.uid() or public.is_owner());

drop policy if exists "owners_update_profiles" on public.profiles;
create policy "owners_update_profiles"
on public.profiles for update
to authenticated
using (public.is_owner())
with check (public.is_owner());

-- After creating your own user in Supabase Authentication, promote it once:
-- update public.profiles
-- set role = 'owner', full_name = 'Jahanzeb Khan'
-- where id = (select id from auth.users where email = 'YOUR_EMAIL');

-- ============================================================================
-- MODULE 2: core_foundation.sql
-- ============================================================================

-- EWAY LINK ERP - Version 1 core business schema.
-- Idempotent: safe to run against an existing Version 1 project.

create extension if not exists pgcrypto;

create table if not exists public.units (
  id uuid primary key default gen_random_uuid(),
  unit_name text not null unique,
  symbol text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.units (unit_name, symbol)
values
  ('PCS','PCS'), ('KG','KG'), ('GRAM','GM'), ('LITER','LTR'),
  ('ML','ML'), ('METER','M'), ('FEET','FT'), ('BOX','BOX'),
  ('ROLL','ROLL'), ('SET','SET'), ('PAIR','PAIR'), ('BAG','BAG'),
  ('DRUM','DRUM'), ('TON','TON')
on conflict (unit_name) do nothing;

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  customer_name text not null unique,
  search_name text,
  address text,
  phone text,
  email text,
  ntn text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.vendors (
  id uuid primary key default gen_random_uuid(),
  vendor_name text not null unique,
  search_name text,
  address text,
  phone text,
  email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.items (
  id uuid primary key default gen_random_uuid(),
  item_name text not null unique,
  search_name text,
  default_unit_id uuid references public.units(id),
  category text,
  remarks text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

update public.customers set search_name = lower(trim(customer_name))
where search_name is null or search_name is distinct from lower(trim(customer_name));
update public.vendors set search_name = lower(trim(vendor_name))
where search_name is null or search_name is distinct from lower(trim(vendor_name));
update public.items set search_name = lower(trim(item_name))
where search_name is null or search_name is distinct from lower(trim(item_name));

drop index if exists public.idx_customer_search;
drop index if exists public.idx_customers_search_name;
drop index if exists public.idx_vendor_search;
drop index if exists public.idx_vendors_search_name;
drop index if exists public.idx_item_search;
drop index if exists public.idx_items_search_name;
create unique index idx_customers_search_name on public.customers(search_name);
create unique index idx_vendors_search_name on public.vendors(search_name);
create unique index idx_items_search_name on public.items(search_name);

create or replace function public.normalize_master_search_name()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_table_name = 'customers' then new.search_name := lower(trim(new.customer_name)); end if;
  if tg_table_name = 'vendors' then new.search_name := lower(trim(new.vendor_name)); end if;
  if tg_table_name = 'items' then new.search_name := lower(trim(new.item_name)); end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists customers_normalize_search on public.customers;
create trigger customers_normalize_search before insert or update on public.customers
for each row execute function public.normalize_master_search_name();
drop trigger if exists vendors_normalize_search on public.vendors;
create trigger vendors_normalize_search before insert or update on public.vendors
for each row execute function public.normalize_master_search_name();
drop trigger if exists items_normalize_search on public.items;
create trigger items_normalize_search before insert or update on public.items
for each row execute function public.normalize_master_search_name();

create table if not exists public.inquiries (
  id uuid primary key default gen_random_uuid(),
  inquiry_no text not null unique,
  customer_id uuid not null references public.customers(id),
  coordinator_id uuid references public.profiles(id) on delete set null,
  coordinator text,
  due_date date,
  status text not null default 'Pending',
  grand_total numeric(18,2) not null default 0,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.inquiries add column if not exists coordinator_id uuid;
alter table public.inquiries drop constraint if exists inquiries_created_by_fkey;
alter table public.inquiries add constraint inquiries_created_by_fkey
  foreign key (created_by) references public.profiles(id) on delete set null;
alter table public.inquiries drop constraint if exists inquiries_coordinator_id_fkey;
alter table public.inquiries add constraint inquiries_coordinator_id_fkey
  foreign key (coordinator_id) references public.profiles(id) on delete set null;

create index if not exists inquiries_customer_idx on public.inquiries(customer_id);
create index if not exists inquiries_created_at_idx on public.inquiries(created_at desc);
create index if not exists inquiries_coordinator_id_idx on public.inquiries(coordinator_id);

create table if not exists public.inquiry_items (
  id uuid primary key default gen_random_uuid(),
  inquiry_id uuid not null references public.inquiries(id) on delete cascade,
  item_id uuid not null references public.items(id),
  qty numeric(18,3) not null default 0,
  unit_id uuid references public.units(id),
  selected_vendor_id uuid references public.vendors(id),
  previous_rate numeric(18,2) not null default 0,
  selected_rate numeric(18,2) not null default 0,
  total numeric(18,2) not null default 0
);

alter table public.inquiry_items alter column selected_vendor_id drop not null;
create index if not exists inquiry_items_inquiry_idx on public.inquiry_items(inquiry_id);
create index if not exists inquiry_items_history_idx on public.inquiry_items(item_id);

create table if not exists public.inquiry_vendor_quotes (
  id uuid primary key default gen_random_uuid(),
  inquiry_item_id uuid not null references public.inquiry_items(id) on delete cascade,
  vendor_id uuid not null references public.vendors(id),
  quoted_rate numeric(18,2),
  remarks text,
  received_at timestamptz not null default now()
);

create table if not exists public.rate_history (
  id uuid primary key default gen_random_uuid(),
  item_id uuid references public.items(id),
  vendor_id uuid references public.vendors(id),
  unit_id uuid references public.units(id),
  rate numeric(18,2),
  entered_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  title text,
  message text,
  type text,
  target_user uuid references public.profiles(id) on delete cascade,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.company_settings (
  id uuid primary key default gen_random_uuid(),
  company_name text,
  address text,
  phone text,
  email text,
  website text,
  currency text not null default 'PKR',
  quotation_validity_days integer not null default 15,
  logo_url text
);

-- ============================================================================
-- MODULE 3: employee_accounts.sql
-- ============================================================================

-- EWAY LINK Employee Accounts
-- Run once in the Supabase SQL Editor.

alter table public.profiles
  add column if not exists username text;

update public.profiles as profile
set username = lower(split_part(auth_user.email, '@', 1))
from auth.users as auth_user
where auth_user.id = profile.id
  and (profile.username is null or btrim(profile.username) = '');

update public.profiles
set username = lower(regexp_replace(full_name, '[^a-zA-Z0-9._-]+', '.', 'g'))
where username is null or btrim(username) = '';

alter table public.profiles
  alter column username set not null;

create unique index if not exists profiles_username_lower_unique
  on public.profiles (lower(username));

alter table public.profiles
  drop constraint if exists profiles_username_format;

alter table public.profiles
  add constraint profiles_username_format
  check (username = lower(username) and username ~ '^[a-z0-9._-]{3,32}$');

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  resolved_username text;
begin
  resolved_username := lower(coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'username'), ''),
    split_part(new.email, '@', 1)
  ));

  insert into public.profiles (id, full_name, username)
  values (
    new.id,
    coalesce(
      nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
      resolved_username
    ),
    resolved_username
  )
  on conflict (id) do update
  set full_name = excluded.full_name,
      username = excluded.username,
      updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Resolves a username to its internal Supabase identity. This keeps existing
-- accounts compatible while all EWAY LINK screens use usernames only.
create or replace function public.resolve_login_email(p_username text)
returns text
language sql
stable
security definer
set search_path = public, auth
as $$
  select auth_user.email
  from public.profiles as profile
  join auth.users as auth_user on auth_user.id = profile.id
  where lower(profile.username) = lower(btrim(p_username))
    and profile.is_active = true
  limit 1;
$$;

revoke all on function public.resolve_login_email(text) from public;
grant execute on function public.resolve_login_email(text) to anon, authenticated;

comment on column public.profiles.username is
  'Lowercase EWAY LINK login username. Employee email identities remain internal.';

-- ============================================================================
-- MODULE 4: attendance_tracking.sql
-- ============================================================================

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

-- ============================================================================
-- MODULE 5: attendance_place_names.sql
-- ============================================================================

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

-- ============================================================================
-- MODULE 6: attendance_notifications.sql
-- ============================================================================

-- EWAY LINK owner attendance notifications.

create table if not exists public.attendance_notifications (
  id bigint generated always as identity primary key,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  employee_id uuid references public.profiles(id) on delete cascade,
  session_id uuid references public.attendance_sessions(id) on delete cascade,
  event_type text not null check (event_type in ('check_in','check_out','system','leave_applied','leave_approved','leave_rejected')),
  title text not null,
  message text not null,
  place_name text,
  occurred_at timestamptz not null default now(),
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists attendance_notifications_recipient_time
  on public.attendance_notifications(recipient_id, occurred_at desc);
create index if not exists attendance_notifications_unread
  on public.attendance_notifications(recipient_id, occurred_at desc) where read_at is null;

alter table public.attendance_notifications enable row level security;

create or replace function public.create_attendance_owner_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  employee_name text;
  event_place text;
  event_time text;
begin
  select coalesce(nullif(trim(full_name), ''), 'Employee') into employee_name
  from public.profiles where id = new.employee_id;

  if tg_op = 'INSERT' then
    event_place := coalesce(nullif(trim(new.check_in_address), ''), 'Location name unavailable');
    event_time := to_char(new.checked_in_at at time zone 'Asia/Karachi', 'DD Mon YYYY, HH12:MI AM');
    insert into public.attendance_notifications
      (recipient_id, employee_id, session_id, event_type, title, message, place_name, occurred_at)
    select id, new.employee_id, new.id, 'check_in', employee_name || ' checked in',
      employee_name || ' checked in at ' || event_time || ' from ' || event_place || '.',
      event_place, new.checked_in_at
    from public.profiles where role = 'owner' and is_active = true;
  elsif old.checked_out_at is null and new.checked_out_at is not null then
    event_place := coalesce(nullif(trim(new.check_out_address), ''), 'Location name unavailable');
    event_time := to_char(new.checked_out_at at time zone 'Asia/Karachi', 'DD Mon YYYY, HH12:MI AM');
    insert into public.attendance_notifications
      (recipient_id, employee_id, session_id, event_type, title, message, place_name, occurred_at)
    select id, new.employee_id, new.id, 'check_out', employee_name || ' checked out',
      employee_name || ' checked out at ' || event_time || ' from ' || event_place || '.',
      event_place, new.checked_out_at
    from public.profiles where role = 'owner' and is_active = true;
  end if;
  return new;
end;
$$;

drop trigger if exists attendance_owner_notification_trigger on public.attendance_sessions;
create trigger attendance_owner_notification_trigger
after insert or update of checked_out_at on public.attendance_sessions
for each row execute function public.create_attendance_owner_notification();

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'attendance_notifications'
  ) then
    alter publication supabase_realtime add table public.attendance_notifications;
  end if;
end;
$$;

-- ============================================================================
-- MODULE 7: push_device_tokens.sql
-- ============================================================================

-- EWAY LINK Firebase Cloud Messaging device registration.
-- Run once in Supabase SQL Editor before launching the updated app.

create table if not exists public.push_device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  token text not null unique,
  platform text not null check (platform in ('android', 'ios', 'web')),
  app_id text not null,
  is_active boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists push_device_tokens_user_active
  on public.push_device_tokens(user_id, is_active);

alter table public.push_device_tokens enable row level security;

drop policy if exists "users_read_own_push_devices"
  on public.push_device_tokens;
create policy "users_read_own_push_devices"
on public.push_device_tokens
for select to authenticated
using (user_id = auth.uid());

create or replace function public.register_push_device(
  p_token text,
  p_platform text,
  p_app_id text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_platform not in ('android', 'ios', 'web') then
    raise exception 'Unsupported push platform';
  end if;

  insert into public.push_device_tokens (
    user_id,
    token,
    platform,
    app_id,
    is_active,
    last_seen_at,
    updated_at
  )
  values (
    auth.uid(),
    p_token,
    p_platform,
    p_app_id,
    true,
    now(),
    now()
  )
  on conflict (token) do update
  set user_id = excluded.user_id,
      platform = excluded.platform,
      app_id = excluded.app_id,
      is_active = true,
      last_seen_at = now(),
      updated_at = now();
end;
$$;

create or replace function public.unregister_push_device(p_token text)
returns void
language sql
security definer
set search_path = public
as $$
  update public.push_device_tokens
  set is_active = false,
      updated_at = now()
  where token = p_token
    and user_id = auth.uid();
$$;

revoke all on function public.register_push_device(text, text, text)
  from public;
grant execute on function public.register_push_device(text, text, text)
  to authenticated;

revoke all on function public.unregister_push_device(text)
  from public;
grant execute on function public.unregister_push_device(text)
  to authenticated;

-- ============================================================================
-- MODULE 8: push_notification_dispatch.sql
-- ============================================================================

-- EWAY LINK production push-notification routing.
-- Run once in Supabase SQL Editor after push_device_tokens.sql.

create extension if not exists pgcrypto;

alter table public.inquiries
  add column if not exists coordinator_id uuid
  references public.profiles(id) on delete set null;

create index if not exists inquiries_coordinator_id_idx
  on public.inquiries(coordinator_id);

update public.inquiries inquiry
set coordinator_id = (
  select profile.id
  from public.profiles profile
  where lower(trim(profile.full_name)) = lower(trim(inquiry.coordinator))
    and profile.is_active = true
  order by
    case profile.role
      when 'coordinator' then 0
      when 'owner' then 1
      else 2
    end,
    profile.created_at
  limit 1
)
where inquiry.coordinator_id is null
  and nullif(trim(inquiry.coordinator), '') is not null;

create or replace function public.list_inquiry_coordinators()
returns table (
  id uuid,
  full_name text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  return query
  select profile.id, profile.full_name
  from public.profiles profile
  where profile.is_active = true
    and nullif(trim(profile.full_name), '') is not null
  order by
    case profile.role
      when 'coordinator' then 0
      when 'owner' then 1
      else 2
    end,
    profile.full_name;
end;
$$;

revoke all on function public.list_inquiry_coordinators() from public;
grant execute on function public.list_inquiry_coordinators() to authenticated;

create table if not exists public.push_outbox (
  id bigint generated always as identity primary key,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  event_type text not null,
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  dedupe_key text not null unique,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'sent', 'failed', 'skipped')),
  attempt_count integer not null default 0,
  delivered_device_count integer not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  processing_started_at timestamptz,
  sent_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists push_outbox_status_created_idx
  on public.push_outbox(status, created_at);

create index if not exists push_outbox_recipient_created_idx
  on public.push_outbox(recipient_id, created_at desc);

alter table public.push_outbox enable row level security;

create or replace function public.enqueue_push_notification(
  p_recipient_id uuid,
  p_event_type text,
  p_title text,
  p_body text,
  p_data jsonb,
  p_dedupe_key text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_recipient_id is null then
    return;
  end if;

  insert into public.push_outbox (
    recipient_id,
    event_type,
    title,
    body,
    data,
    dedupe_key
  )
  values (
    p_recipient_id,
    p_event_type,
    p_title,
    p_body,
    coalesce(p_data, '{}'::jsonb),
    p_dedupe_key
  )
  on conflict (dedupe_key) do nothing;
end;
$$;

revoke all on function public.enqueue_push_notification(
  uuid,
  text,
  text,
  text,
  jsonb,
  text
) from public;

create or replace function public.route_inquiry_push_notifications()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  customer_name text;
  inquiry_number text;
  creator_name text;
  recipient record;
begin
  select coalesce(nullif(trim(customer.customer_name), ''), 'Customer')
    into customer_name
  from public.customers customer
  where customer.id = new.customer_id;

  inquiry_number := coalesce(
    nullif(trim(new.inquiry_no), ''),
    new.id::text
  );

  select coalesce(nullif(trim(profile.full_name), ''), 'A team member')
    into creator_name
  from public.profiles profile
  where profile.id = new.created_by;

  if tg_op = 'INSERT' then
    perform public.enqueue_push_notification(
      new.coordinator_id,
      'inquiry_created',
      customer_name || ' - New inquiry',
      coalesce(creator_name, 'A team member') || ' created ' ||
        customer_name || ' inquiry ' || inquiry_number || '.',
      jsonb_build_object(
        'route', '/inquiries/' || new.id::text,
        'inquiry_id', new.id::text,
        'event_type', 'inquiry_created'
      ),
      'inquiry-created:' || new.id::text || ':' ||
        coalesce(new.coordinator_id::text, 'none')
    );

  elsif old.coordinator_id is distinct from new.coordinator_id
    and lower(coalesce(new.status, '')) not in ('completed', 'rejected') then
    perform public.enqueue_push_notification(
      new.coordinator_id,
      'inquiry_assigned',
      customer_name || ' - Inquiry assigned',
      customer_name || ' inquiry ' || inquiry_number ||
        ' has been assigned to you.',
      jsonb_build_object(
        'route', '/inquiries/' || new.id::text,
        'inquiry_id', new.id::text,
        'event_type', 'inquiry_assigned'
      ),
      'inquiry-assigned:' || new.id::text || ':' ||
        coalesce(new.coordinator_id::text, 'none')
    );
  end if;

  if tg_op = 'UPDATE' then
    if lower(coalesce(old.status, '')) <> 'completed'
      and lower(coalesce(new.status, '')) = 'completed' then
      for recipient in
        select distinct recipient_id
        from (
          select profile.id as recipient_id
          from public.profiles profile
          where profile.role = 'owner'
            and profile.is_active = true
          union all
          select new.created_by
          where new.created_by is not null
        ) recipients
      loop
        perform public.enqueue_push_notification(
          recipient.recipient_id,
          'inquiry_completed',
          customer_name || ' - Inquiry completed',
          customer_name || ' inquiry ' || inquiry_number ||
            ' has been completed.',
          jsonb_build_object(
            'route', '/inquiries/' || new.id::text,
            'inquiry_id', new.id::text,
            'event_type', 'inquiry_completed'
          ),
          'inquiry-completed:' || new.id::text || ':' ||
            recipient.recipient_id::text
        );
      end loop;
    end if;

    if lower(coalesce(old.status, '')) <> 'rejected'
      and lower(coalesce(new.status, '')) = 'rejected' then
      for recipient in
        select distinct recipient_id
        from (
          select profile.id as recipient_id
          from public.profiles profile
          where profile.role = 'owner'
            and profile.is_active = true
          union all
          select new.created_by
          where new.created_by is not null
        ) recipients
      loop
        perform public.enqueue_push_notification(
          recipient.recipient_id,
          'inquiry_rejected',
          customer_name || ' - Inquiry rejected',
          customer_name || ' inquiry ' || inquiry_number ||
            ' has been rejected.',
          jsonb_build_object(
            'route', '/inquiries/' || new.id::text,
            'inquiry_id', new.id::text,
            'event_type', 'inquiry_rejected'
          ),
          'inquiry-rejected:' || new.id::text || ':' ||
            recipient.recipient_id::text
        );
      end loop;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists inquiry_push_notification_trigger
  on public.inquiries;
create trigger inquiry_push_notification_trigger
after insert or update of status, coordinator_id
on public.inquiries
for each row
execute function public.route_inquiry_push_notifications();

create or replace function public.route_attendance_push_notifications()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.event_type not in ('check_in', 'check_out') then
    return new;
  end if;

  perform public.enqueue_push_notification(
    new.recipient_id,
    'attendance_' || new.event_type,
    new.title,
    new.message,
    jsonb_build_object(
      'route', '/attendance',
      'session_id', coalesce(new.session_id::text, ''),
      'employee_id', coalesce(new.employee_id::text, ''),
      'event_type', 'attendance_' || new.event_type
    ),
    'attendance:' || new.id::text || ':' || new.recipient_id::text
  );

  return new;
end;
$$;

drop trigger if exists attendance_push_notification_trigger
  on public.attendance_notifications;
create trigger attendance_push_notification_trigger
after insert
on public.attendance_notifications
for each row
execute function public.route_attendance_push_notifications();

-- ============================================================================
-- MODULE 9: cash_sales_foundation.sql
-- ============================================================================

-- EWAY LINK Cash Sales Foundation
-- Run once in the Supabase SQL Editor.

begin;

create extension if not exists pgcrypto;

create sequence if not exists public.cash_sale_number_sequence;

create table if not exists public.cash_sales (
  id uuid primary key default gen_random_uuid(),
  sale_no text not null unique,
  customer_id uuid not null references public.customers(id),
  sales_person_id uuid not null references public.profiles(id),
  sales_person_name text not null,
  status text not null default 'Completed'
    check (status in ('Completed', 'Entered into ERP')),
  grand_total numeric(18,2) not null default 0 check (grand_total >= 0),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  erp_entered_at timestamptz,
  erp_entered_by uuid references public.profiles(id)
);

create table if not exists public.cash_sale_items (
  id uuid primary key default gen_random_uuid(),
  cash_sale_id uuid not null references public.cash_sales(id) on delete cascade,
  item_id uuid not null references public.items(id),
  unit_id uuid not null references public.units(id),
  qty numeric(18,3) not null check (qty > 0),
  previous_rate numeric(18,2) not null default 0 check (previous_rate >= 0),
  sales_rate numeric(18,2) not null check (sales_rate > 0),
  total numeric(18,2) not null check (total >= 0),
  created_at timestamptz not null default now()
);

create index if not exists cash_sales_created_at_idx
  on public.cash_sales(created_at desc);
create index if not exists cash_sales_customer_idx
  on public.cash_sales(customer_id, created_at desc);
create index if not exists cash_sales_status_idx
  on public.cash_sales(status, created_at desc);
create index if not exists cash_sale_items_sale_idx
  on public.cash_sale_items(cash_sale_id);
create index if not exists cash_sale_items_history_idx
  on public.cash_sale_items(item_id, created_at desc);

create or replace function public.next_cash_sale_number()
returns text
language sql
volatile
security definer
set search_path = public
as $$
  select 'SAL-' ||
    to_char(current_timestamp at time zone 'Asia/Karachi', 'YYMMDD') || '-' ||
    lpad(nextval('public.cash_sale_number_sequence')::text, 4, '0');
$$;

grant execute on function public.next_cash_sale_number() to authenticated;

create or replace function public.current_user_can_manage_cash_sales()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and is_active = true
      and role in ('owner', 'coordinator')
  );
$$;

grant execute on function public.current_user_can_manage_cash_sales()
  to authenticated;

create or replace function public.get_last_customer_item_sale(
  p_customer_id uuid,
  p_item_name text
)
returns table (
  sales_rate numeric,
  unit_name text,
  sold_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    line.sales_rate,
    unit_record.unit_name,
    sale.created_at
  from public.cash_sale_items line
  join public.cash_sales sale on sale.id = line.cash_sale_id
  join public.items item_record on item_record.id = line.item_id
  join public.units unit_record on unit_record.id = line.unit_id
  where sale.customer_id = p_customer_id
    and lower(trim(item_record.item_name)) = lower(trim(p_item_name))
  order by sale.created_at desc, line.created_at desc
  limit 1;
$$;

grant execute on function public.get_last_customer_item_sale(uuid, text)
  to authenticated;

create or replace function public.create_cash_sale(
  p_sale_no text,
  p_customer_id uuid,
  p_sales_person_name text,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  sale_id uuid;
  calculated_total numeric(18,2);
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and is_active = true
  ) then
    raise exception 'The employee profile is not active.';
  end if;
  if p_sale_no is null or trim(p_sale_no) = '' then
    raise exception 'The sales ticket number is required.';
  end if;
  if p_items is null
    or jsonb_typeof(p_items) <> 'array'
    or jsonb_array_length(p_items) = 0 then
    raise exception 'At least one sales item is required.';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_items) line
    where coalesce((line ->> 'quantity')::numeric, 0) <= 0
       or coalesce((line ->> 'sales_rate')::numeric, 0) <= 0
       or nullif(line ->> 'item_id', '') is null
       or nullif(line ->> 'unit_id', '') is null
  ) then
    raise exception 'Every item requires a unit, quantity and sales rate.';
  end if;

  select round(
    sum(
      (line ->> 'quantity')::numeric *
      (line ->> 'sales_rate')::numeric
    ),
    2
  )
  into calculated_total
  from jsonb_array_elements(p_items) line;

  insert into public.cash_sales (
    sale_no,
    customer_id,
    sales_person_id,
    sales_person_name,
    status,
    grand_total,
    created_by
  ) values (
    trim(p_sale_no),
    p_customer_id,
    auth.uid(),
    trim(p_sales_person_name),
    'Completed',
    calculated_total,
    auth.uid()
  )
  returning id into sale_id;

  insert into public.cash_sale_items (
    cash_sale_id,
    item_id,
    unit_id,
    qty,
    previous_rate,
    sales_rate,
    total
  )
  select
    sale_id,
    (line ->> 'item_id')::uuid,
    (line ->> 'unit_id')::uuid,
    (line ->> 'quantity')::numeric,
    greatest(coalesce((line ->> 'previous_rate')::numeric, 0), 0),
    (line ->> 'sales_rate')::numeric,
    round(
      (line ->> 'quantity')::numeric *
      (line ->> 'sales_rate')::numeric,
      2
    )
  from jsonb_array_elements(p_items) line;

  return sale_id;
end;
$$;

revoke all on function public.create_cash_sale(text, uuid, text, jsonb)
  from public;
grant execute on function public.create_cash_sale(text, uuid, text, jsonb)
  to authenticated;

alter table public.cash_sales enable row level security;
alter table public.cash_sale_items enable row level security;

revoke all on public.cash_sales from authenticated;
grant select, insert, delete on public.cash_sales to authenticated;
grant update (status) on public.cash_sales to authenticated;

revoke all on public.cash_sale_items from authenticated;
grant select, insert on public.cash_sale_items to authenticated;

drop policy if exists "cash_sales_read_authenticated" on public.cash_sales;
create policy "cash_sales_read_authenticated"
on public.cash_sales for select
to authenticated
using (true);

drop policy if exists "cash_sales_create_own" on public.cash_sales;
create policy "cash_sales_create_own"
on public.cash_sales for insert
to authenticated
with check (
  created_by = auth.uid()
  and sales_person_id = auth.uid()
  and status = 'Completed'
);

drop policy if exists "cash_sales_mark_erp" on public.cash_sales;
create policy "cash_sales_mark_erp"
on public.cash_sales for update
to authenticated
using (public.current_user_can_manage_cash_sales())
with check (public.current_user_can_manage_cash_sales());

drop policy if exists "cash_sales_delete_failed_own" on public.cash_sales;
create policy "cash_sales_delete_failed_own"
on public.cash_sales for delete
to authenticated
using (created_by = auth.uid() and status = 'Completed');

drop policy if exists "cash_sale_items_read_authenticated"
  on public.cash_sale_items;
create policy "cash_sale_items_read_authenticated"
on public.cash_sale_items for select
to authenticated
using (true);

drop policy if exists "cash_sale_items_create_own"
  on public.cash_sale_items;
create policy "cash_sale_items_create_own"
on public.cash_sale_items for insert
to authenticated
with check (
  exists (
    select 1
    from public.cash_sales sale
    where sale.id = cash_sale_id
      and sale.created_by = auth.uid()
      and sale.status = 'Completed'
  )
);

create or replace function public.route_cash_sale_push_notifications()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  customer_name text;
  recipient record;
begin
  select coalesce(nullif(trim(customer.customer_name), ''), 'Customer')
    into customer_name
  from public.customers customer
  where customer.id = new.customer_id;

  if tg_op = 'INSERT' then
    for recipient in
      select profile.id
      from public.profiles profile
      where profile.is_active = true
        and profile.role in ('owner', 'coordinator')
    loop
      perform public.enqueue_push_notification(
        recipient.id,
        'cash_sale_created',
        customer_name || ' - New cash sale',
        new.sales_person_name || ' completed ' || new.sale_no ||
          ' for PKR ' || to_char(new.grand_total, 'FM999G999G999G990D00') || '.',
        jsonb_build_object(
          'route', '/cash-sales/' || new.id::text,
          'cash_sale_id', new.id::text,
          'event_type', 'cash_sale_created'
        ),
        'cash-sale-created:' || new.id::text || ':' || recipient.id::text
      );
    end loop;
  elsif old.status is distinct from new.status
    and new.status = 'Entered into ERP' then
    perform public.enqueue_push_notification(
      new.created_by,
      'cash_sale_entered_erp',
      customer_name || ' - Entered into ERP',
      new.sale_no || ' has been entered into the ERP.',
      jsonb_build_object(
        'route', '/cash-sales/' || new.id::text,
        'cash_sale_id', new.id::text,
        'event_type', 'cash_sale_entered_erp'
      ),
      'cash-sale-erp:' || new.id::text || ':' || new.created_by::text
    );
  end if;

  return new;
end;
$$;

drop trigger if exists cash_sale_push_notification_trigger
  on public.cash_sales;
create trigger cash_sale_push_notification_trigger
after insert or update of status
on public.cash_sales
for each row
execute function public.route_cash_sale_push_notifications();

create or replace function public.set_cash_sale_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  if new.status = 'Entered into ERP'
    and old.status is distinct from new.status then
    new.erp_entered_at = now();
    new.erp_entered_by = auth.uid();
  end if;
  return new;
end;
$$;

drop trigger if exists cash_sale_updated_at_trigger on public.cash_sales;
create trigger cash_sale_updated_at_trigger
before update on public.cash_sales
for each row execute function public.set_cash_sale_updated_at();

commit;

-- ============================================================================
-- MODULE 10: attendance_leave_management.sql
-- ============================================================================

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

-- ============================================================================
-- MODULE 11: role_workflow_security.sql
-- ============================================================================

-- EWAY LINK role, attendance and workflow security.
-- Run once after employee_accounts.sql, attendance_tracking.sql,
-- push_notification_dispatch.sql and cash_sales_foundation.sql.

begin;

create or replace function public.current_employee_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role
  from public.profiles
  where id = auth.uid() and is_active = true
  limit 1;
$$;

create or replace function public.has_active_attendance()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.attendance_sessions
    where employee_id = auth.uid()
      and checked_out_at is null
  );
$$;

grant execute on function public.current_employee_role() to authenticated;
grant execute on function public.has_active_attendance() to authenticated;

create or replace function public.list_inquiry_purchasers()
returns table (id uuid, full_name text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  return query
  select profile.id, profile.full_name
  from public.profiles profile
  where profile.is_active = true
    and profile.role = 'employee'
    and nullif(trim(profile.full_name), '') is not null
  order by profile.full_name;
end;
$$;

revoke all on function public.list_inquiry_purchasers() from public;
grant execute on function public.list_inquiry_purchasers() to authenticated;

create or replace function public.enforce_inquiry_workflow()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  user_role text;
begin
  user_role := public.current_employee_role();
  if user_role is null then
    raise exception 'The employee account is not active.';
  end if;
  if user_role <> 'owner' and not public.has_active_attendance() then
    raise exception 'Check in to Attendance before working on inquiries.';
  end if;

  if tg_op = 'INSERT' then
    if user_role not in ('owner', 'coordinator') then
      raise exception 'Only the Owner or Coordinator can create inquiries.';
    end if;
    if new.created_by is distinct from auth.uid() then
      raise exception 'The inquiry creator is invalid.';
    end if;
    if not exists (
      select 1 from public.profiles
      where id = new.coordinator_id and role = 'employee' and is_active = true
    ) then
      raise exception 'Select an active Employee as Purchaser.';
    end if;
  elsif tg_op = 'UPDATE' then
    if user_role = 'coordinator' and old.created_by is distinct from auth.uid() then
      raise exception 'A Coordinator can update only inquiries they created.';
    end if;
    if user_role = 'employee' then
      if old.coordinator_id is distinct from auth.uid() then
        raise exception 'You can update only inquiries assigned to you as Purchaser.';
      end if;
      if new.inquiry_no is distinct from old.inquiry_no
        or new.customer_id is distinct from old.customer_id
        or new.coordinator_id is distinct from old.coordinator_id
        or new.created_by is distinct from old.created_by
        or new.due_date is distinct from old.due_date then
        raise exception 'A Purchaser cannot change inquiry ownership or customer information.';
      end if;
    end if;
  elsif tg_op = 'DELETE' then
    if user_role <> 'owner'
      and not (user_role = 'coordinator' and old.created_by = auth.uid()) then
      raise exception 'You cannot delete this inquiry.';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists enforce_inquiry_workflow_trigger on public.inquiries;
create trigger enforce_inquiry_workflow_trigger
before insert or update or delete on public.inquiries
for each row execute function public.enforce_inquiry_workflow();

create or replace function public.enforce_inquiry_item_workflow()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  inquiry_record public.inquiries%rowtype;
  user_role text;
  target_inquiry_id uuid;
begin
  target_inquiry_id := case when tg_op = 'DELETE' then old.inquiry_id else new.inquiry_id end;
  select * into inquiry_record from public.inquiries where id = target_inquiry_id;
  user_role := public.current_employee_role();
  if user_role is null then raise exception 'The employee account is not active.'; end if;
  if user_role <> 'owner' and not public.has_active_attendance() then
    raise exception 'Check in to Attendance before working on inquiry items.';
  end if;
  if user_role = 'coordinator' and inquiry_record.created_by is distinct from auth.uid() then
    raise exception 'You cannot update items for this inquiry.';
  end if;
  if user_role = 'employee' and inquiry_record.coordinator_id is distinct from auth.uid() then
    raise exception 'This inquiry is not assigned to you as Purchaser.';
  end if;
  if user_role not in ('owner', 'coordinator', 'employee') then
    raise exception 'You cannot update inquiry items.';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists enforce_inquiry_item_workflow_trigger on public.inquiry_items;
create trigger enforce_inquiry_item_workflow_trigger
before insert or update or delete on public.inquiry_items
for each row execute function public.enforce_inquiry_item_workflow();

create or replace function public.enforce_cash_sale_workflow()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  user_role text;
begin
  user_role := public.current_employee_role();
  if user_role is null then raise exception 'The employee account is not active.'; end if;
  if user_role <> 'owner' and not public.has_active_attendance() then
    raise exception 'Check in to Attendance before working on Cash Invoices.';
  end if;

  if tg_op = 'INSERT' then
    if user_role not in ('owner', 'employee') then
      raise exception 'Only the Owner or an Employee can create Cash Invoices.';
    end if;
    if new.created_by is distinct from auth.uid()
      or new.sales_person_id is distinct from auth.uid() then
      raise exception 'The Cash Invoice creator is invalid.';
    end if;
  elsif tg_op = 'UPDATE' then
    if user_role not in ('owner', 'coordinator') then
      raise exception 'Only the Owner or Coordinator can enter a Cash Invoice into ERP.';
    end if;
    if old.status = 'Entered into ERP' then
      raise exception 'This Cash Invoice is already entered into ERP.';
    end if;
    if new.status <> 'Entered into ERP' then
      raise exception 'Only the ERP status can be confirmed.';
    end if;
  elsif tg_op = 'DELETE' then
    if user_role <> 'owner'
      and not (user_role = 'employee' and old.created_by = auth.uid()) then
      raise exception 'You cannot delete this Cash Invoice.';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists enforce_cash_sale_workflow_trigger on public.cash_sales;
create trigger enforce_cash_sale_workflow_trigger
before insert or update or delete on public.cash_sales
for each row execute function public.enforce_cash_sale_workflow();

alter table public.inquiries enable row level security;
alter table public.inquiry_items enable row level security;
alter table public.cash_sales enable row level security;
alter table public.cash_sale_items enable row level security;

do $$
declare policy_record record;
begin
  for policy_record in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('inquiries', 'inquiry_items', 'cash_sales', 'cash_sale_items')
  loop
    execute format(
      'drop policy if exists %I on %I.%I',
      policy_record.policyname,
      policy_record.schemaname,
      policy_record.tablename
    );
  end loop;
end;
$$;

create policy inquiries_role_read on public.inquiries
for select to authenticated using (
  public.current_employee_role() = 'owner'
  or (public.current_employee_role() = 'coordinator' and created_by = auth.uid())
  or (public.current_employee_role() = 'employee' and coordinator_id = auth.uid())
);

create policy inquiries_role_insert on public.inquiries
for insert to authenticated with check (
  public.current_employee_role() in ('owner', 'coordinator')
  and created_by = auth.uid()
);

create policy inquiries_role_update on public.inquiries
for update to authenticated using (
  public.current_employee_role() = 'owner'
  or (public.current_employee_role() = 'coordinator' and created_by = auth.uid())
  or (public.current_employee_role() = 'employee' and coordinator_id = auth.uid())
) with check (
  public.current_employee_role() = 'owner'
  or (public.current_employee_role() = 'coordinator' and created_by = auth.uid())
  or (public.current_employee_role() = 'employee' and coordinator_id = auth.uid())
);

create policy inquiries_role_delete on public.inquiries
for delete to authenticated using (
  public.current_employee_role() = 'owner'
  or (public.current_employee_role() = 'coordinator' and created_by = auth.uid())
);

create policy inquiry_items_role_read on public.inquiry_items
for select to authenticated using (exists (
  select 1 from public.inquiries inquiry
  where inquiry.id = inquiry_id
    and (
      public.current_employee_role() = 'owner'
      or (public.current_employee_role() = 'coordinator' and inquiry.created_by = auth.uid())
      or (public.current_employee_role() = 'employee' and inquiry.coordinator_id = auth.uid())
    )
));

create policy inquiry_items_role_insert on public.inquiry_items
for insert to authenticated with check (exists (
  select 1 from public.inquiries inquiry
  where inquiry.id = inquiry_id
    and (
      public.current_employee_role() = 'owner'
      or (public.current_employee_role() = 'coordinator' and inquiry.created_by = auth.uid())
      or (public.current_employee_role() = 'employee' and inquiry.coordinator_id = auth.uid())
    )
));

create policy inquiry_items_role_update on public.inquiry_items
for update to authenticated using (exists (
  select 1 from public.inquiries inquiry
  where inquiry.id = inquiry_id
    and (
      public.current_employee_role() = 'owner'
      or (public.current_employee_role() = 'coordinator' and inquiry.created_by = auth.uid())
      or (public.current_employee_role() = 'employee' and inquiry.coordinator_id = auth.uid())
    )
)) with check (exists (
  select 1 from public.inquiries inquiry
  where inquiry.id = inquiry_id
    and (
      public.current_employee_role() = 'owner'
      or (public.current_employee_role() = 'coordinator' and inquiry.created_by = auth.uid())
      or (public.current_employee_role() = 'employee' and inquiry.coordinator_id = auth.uid())
    )
));

create policy inquiry_items_role_delete on public.inquiry_items
for delete to authenticated using (exists (
  select 1 from public.inquiries inquiry
  where inquiry.id = inquiry_id
    and (
      public.current_employee_role() = 'owner'
      or (public.current_employee_role() = 'coordinator' and inquiry.created_by = auth.uid())
      or (public.current_employee_role() = 'employee' and inquiry.coordinator_id = auth.uid())
    )
));

create policy cash_sales_role_read on public.cash_sales
for select to authenticated using (
  public.current_employee_role() in ('owner', 'coordinator')
  or (public.current_employee_role() = 'employee' and created_by = auth.uid())
);

create policy cash_sales_role_insert on public.cash_sales
for insert to authenticated with check (
  public.current_employee_role() in ('owner', 'employee')
  and created_by = auth.uid()
  and sales_person_id = auth.uid()
);

create policy cash_sales_role_update on public.cash_sales
for update to authenticated using (
  public.current_employee_role() in ('owner', 'coordinator')
) with check (public.current_employee_role() in ('owner', 'coordinator'));

create policy cash_sales_role_delete on public.cash_sales
for delete to authenticated using (
  public.current_employee_role() = 'owner'
  or (public.current_employee_role() = 'employee' and created_by = auth.uid())
);

create policy cash_sale_items_role_read on public.cash_sale_items
for select to authenticated using (exists (
  select 1 from public.cash_sales sale
  where sale.id = cash_sale_id
    and (
      public.current_employee_role() in ('owner', 'coordinator')
      or (public.current_employee_role() = 'employee' and sale.created_by = auth.uid())
    )
));

create policy cash_sale_items_role_insert on public.cash_sale_items
for insert to authenticated with check (exists (
  select 1 from public.cash_sales sale
  where sale.id = cash_sale_id
    and sale.created_by = auth.uid()
    and public.current_employee_role() in ('owner', 'employee')
));

create or replace function public.route_inquiry_push_notifications()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  customer_name text;
  inquiry_number text;
  recipient record;
begin
  select coalesce(nullif(trim(customer.customer_name), ''), 'Customer')
  into customer_name from public.customers customer where customer.id = new.customer_id;
  inquiry_number := coalesce(nullif(trim(new.inquiry_no), ''), new.id::text);

  if tg_op = 'INSERT' then
    for recipient in
      select distinct recipient_id from (
        select new.coordinator_id as recipient_id
        union all
        select id from public.profiles where role = 'owner' and is_active = true
      ) recipients where recipient_id is not null
    loop
      perform public.enqueue_push_notification(
        recipient.recipient_id, 'inquiry_created',
        customer_name || ' - New inquiry',
        customer_name || ' inquiry ' || inquiry_number || ' has been assigned to a Purchaser.',
        jsonb_build_object('route', '/inquiries/' || new.id::text, 'inquiry_id', new.id::text, 'event_type', 'inquiry_created'),
        'inquiry-created-v2:' || new.id::text || ':' || recipient.recipient_id::text
      );
    end loop;
  elsif old.coordinator_id is distinct from new.coordinator_id
    and lower(coalesce(new.status, '')) not in ('completed', 'rejected') then
    perform public.enqueue_push_notification(
      new.coordinator_id, 'inquiry_assigned',
      customer_name || ' - Inquiry assigned',
      customer_name || ' inquiry ' || inquiry_number || ' has been assigned to you as Purchaser.',
      jsonb_build_object('route', '/inquiries/' || new.id::text, 'inquiry_id', new.id::text, 'event_type', 'inquiry_assigned'),
      'inquiry-assigned-v2:' || new.id::text || ':' || new.coordinator_id::text
    );
  end if;

  if tg_op = 'UPDATE' and (
    (lower(coalesce(old.status, '')) <> 'completed' and lower(coalesce(new.status, '')) = 'completed')
    or (lower(coalesce(old.status, '')) <> 'rejected' and lower(coalesce(new.status, '')) = 'rejected')
  ) then
    for recipient in
      select distinct recipient_id from (
        select new.created_by as recipient_id
        union all
        select id from public.profiles where role = 'owner' and is_active = true
      ) recipients where recipient_id is not null
    loop
      perform public.enqueue_push_notification(
        recipient.recipient_id,
        case when lower(new.status) = 'completed' then 'inquiry_completed' else 'inquiry_rejected' end,
        customer_name || case when lower(new.status) = 'completed' then ' - Inquiry completed' else ' - Inquiry rejected' end,
        customer_name || ' inquiry ' || inquiry_number || ' has been ' || lower(new.status) || '.',
        jsonb_build_object('route', '/inquiries/' || new.id::text, 'inquiry_id', new.id::text, 'event_type', lower(new.status)),
        'inquiry-result-v2:' || new.id::text || ':' || lower(new.status) || ':' || recipient.recipient_id::text
      );
    end loop;
  end if;
  return new;
end;
$$;

create or replace function public.route_cash_sale_push_notifications()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  customer_name text;
  recipient record;
begin
  select coalesce(nullif(trim(customer.customer_name), ''), 'Customer')
  into customer_name from public.customers customer where customer.id = new.customer_id;

  if tg_op = 'INSERT' then
    for recipient in
      select id from public.profiles
      where is_active = true and role in ('owner', 'coordinator')
    loop
      perform public.enqueue_push_notification(
        recipient.id, 'cash_sale_created', customer_name || ' - New Cash Invoice',
        new.sales_person_name || ' created ' || new.sale_no || ' for PKR ' || to_char(new.grand_total, 'FM999G999G999G990D00') || '.',
        jsonb_build_object('route', '/cash-sales/' || new.id::text, 'cash_sale_id', new.id::text, 'event_type', 'cash_sale_created'),
        'cash-invoice-created-v2:' || new.id::text || ':' || recipient.id::text
      );
    end loop;
  elsif old.status is distinct from new.status and new.status = 'Entered into ERP' then
    for recipient in
      select id from public.profiles where is_active = true and role = 'owner'
    loop
      perform public.enqueue_push_notification(
        recipient.id, 'cash_sale_entered_erp', customer_name || ' - Entered into ERP',
        new.sale_no || ' has been entered into ERP.',
        jsonb_build_object('route', '/cash-sales/' || new.id::text, 'cash_sale_id', new.id::text, 'event_type', 'cash_sale_entered_erp'),
        'cash-invoice-erp-v2:' || new.id::text || ':' || recipient.id::text
      );
    end loop;
  end if;
  return new;
end;
$$;

commit;

-- ============================================================================
-- MODULE 12: inquiry_employee_pricing_access.sql
-- ============================================================================

-- EWAY LINK shared employee Inquiry pricing queue.
-- Run this COMPLETE file once in Supabase SQL Editor.

begin;

create or replace function public.enforce_inquiry_workflow()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  user_role text;
begin
  user_role := public.current_employee_role();
  if user_role is null then
    raise exception 'The employee account is not active.';
  end if;
  if user_role <> 'owner' and not public.has_active_attendance() then
    raise exception 'Check in to Attendance before working on inquiries.';
  end if;

  if tg_op = 'INSERT' then
    if user_role not in ('owner', 'coordinator') then
      raise exception 'Only the Owner or Coordinator can create inquiries.';
    end if;
    if new.created_by is distinct from auth.uid() then
      raise exception 'The inquiry creator is invalid.';
    end if;
    if not exists (
      select 1 from public.profiles
      where id = new.coordinator_id
        and role = 'employee'
        and is_active = true
    ) then
      raise exception 'Select an active Employee as Purchaser.';
    end if;
  elsif tg_op = 'UPDATE' then
    if user_role = 'coordinator'
      and old.created_by is distinct from auth.uid() then
      raise exception 'A Coordinator can update only inquiries they created.';
    end if;
    if user_role = 'employee' then
      if new.inquiry_no is distinct from old.inquiry_no
        or new.customer_id is distinct from old.customer_id
        or new.coordinator_id is distinct from old.coordinator_id
        or new.coordinator is distinct from old.coordinator
        or new.created_by is distinct from old.created_by
        or new.due_date is distinct from old.due_date then
        raise exception 'Employees can change only vendor pricing and completion status.';
      end if;
      if lower(coalesce(new.status, '')) = 'rejected' then
        raise exception 'Only the Owner or Coordinator can reject an inquiry.';
      end if;
    end if;
  elsif tg_op = 'DELETE' then
    if user_role <> 'owner'
      and not (user_role = 'coordinator' and old.created_by = auth.uid()) then
      raise exception 'You cannot delete this inquiry.';
    end if;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function public.enforce_inquiry_item_workflow()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  inquiry_record public.inquiries%rowtype;
  user_role text;
  target_inquiry_id uuid;
begin
  target_inquiry_id := case
    when tg_op = 'DELETE' then old.inquiry_id
    else new.inquiry_id
  end;
  select * into inquiry_record
  from public.inquiries
  where id = target_inquiry_id;

  user_role := public.current_employee_role();
  if user_role is null then
    raise exception 'The employee account is not active.';
  end if;
  if user_role <> 'owner' and not public.has_active_attendance() then
    raise exception 'Check in to Attendance before working on inquiry items.';
  end if;

  if user_role = 'employee' then
    if tg_op <> 'UPDATE' then
      raise exception 'Employees can update vendor and rate only.';
    end if;
    if new.inquiry_id is distinct from old.inquiry_id
      or new.item_id is distinct from old.item_id
      or new.unit_id is distinct from old.unit_id
      or new.qty is distinct from old.qty
      or new.previous_rate is distinct from old.previous_rate then
      raise exception 'Employees cannot change the item, unit, quantity or previous rate.';
    end if;
  elsif user_role = 'coordinator' then
    if inquiry_record.created_by is distinct from auth.uid() then
      raise exception 'You cannot update items for this inquiry.';
    end if;
  elsif user_role <> 'owner' then
    raise exception 'You cannot update inquiry items.';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop policy if exists inquiries_role_read on public.inquiries;
create policy inquiries_role_read on public.inquiries
for select to authenticated using (
  public.current_employee_role() = 'owner'
  or (public.current_employee_role() = 'coordinator' and created_by = auth.uid())
  or public.current_employee_role() = 'employee'
);

drop policy if exists inquiries_role_insert on public.inquiries;
create policy inquiries_role_insert on public.inquiries
for insert to authenticated with check (
  public.current_employee_role() in ('owner', 'coordinator')
  and created_by = auth.uid()
);

drop policy if exists inquiries_role_update on public.inquiries;
create policy inquiries_role_update on public.inquiries
for update to authenticated using (
  public.current_employee_role() = 'owner'
  or (public.current_employee_role() = 'coordinator' and created_by = auth.uid())
  or public.current_employee_role() = 'employee'
) with check (
  public.current_employee_role() = 'owner'
  or (public.current_employee_role() = 'coordinator' and created_by = auth.uid())
  or public.current_employee_role() = 'employee'
);

drop policy if exists inquiries_role_delete on public.inquiries;
create policy inquiries_role_delete on public.inquiries
for delete to authenticated using (
  public.current_employee_role() = 'owner'
  or (public.current_employee_role() = 'coordinator' and created_by = auth.uid())
);

drop policy if exists inquiry_items_role_read on public.inquiry_items;
create policy inquiry_items_role_read on public.inquiry_items
for select to authenticated using (exists (
  select 1 from public.inquiries inquiry
  where inquiry.id = inquiry_id
    and (
      public.current_employee_role() = 'owner'
      or (
        public.current_employee_role() = 'coordinator'
        and inquiry.created_by = auth.uid()
      )
      or public.current_employee_role() = 'employee'
    )
));

drop policy if exists inquiry_items_role_insert on public.inquiry_items;
create policy inquiry_items_role_insert on public.inquiry_items
for insert to authenticated with check (exists (
  select 1 from public.inquiries inquiry
  where inquiry.id = inquiry_id
    and (
      public.current_employee_role() = 'owner'
      or (
        public.current_employee_role() = 'coordinator'
        and inquiry.created_by = auth.uid()
      )
    )
));

drop policy if exists inquiry_items_role_update on public.inquiry_items;
create policy inquiry_items_role_update on public.inquiry_items
for update to authenticated using (exists (
  select 1 from public.inquiries inquiry
  where inquiry.id = inquiry_id
    and (
      public.current_employee_role() = 'owner'
      or (
        public.current_employee_role() = 'coordinator'
        and inquiry.created_by = auth.uid()
      )
      or public.current_employee_role() = 'employee'
    )
)) with check (exists (
  select 1 from public.inquiries inquiry
  where inquiry.id = inquiry_id
    and (
      public.current_employee_role() = 'owner'
      or (
        public.current_employee_role() = 'coordinator'
        and inquiry.created_by = auth.uid()
      )
      or public.current_employee_role() = 'employee'
    )
));

drop policy if exists inquiry_items_role_delete on public.inquiry_items;
create policy inquiry_items_role_delete on public.inquiry_items
for delete to authenticated using (exists (
  select 1 from public.inquiries inquiry
  where inquiry.id = inquiry_id
    and (
      public.current_employee_role() = 'owner'
      or (
        public.current_employee_role() = 'coordinator'
        and inquiry.created_by = auth.uid()
      )
    )
));

create or replace function public.route_inquiry_push_notifications()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  customer_name text;
  inquiry_number text;
  recipient record;
begin
  select coalesce(nullif(trim(customer.customer_name), ''), 'Customer')
  into customer_name
  from public.customers customer
  where customer.id = new.customer_id;
  inquiry_number := coalesce(nullif(trim(new.inquiry_no), ''), new.id::text);

  if tg_op = 'INSERT' then
    for recipient in
      select distinct recipient_id from (
        select id as recipient_id
        from public.profiles
        where role in ('owner', 'employee') and is_active = true
      ) recipients
      where recipient_id is not null
    loop
      perform public.enqueue_push_notification(
        recipient.recipient_id,
        'inquiry_created',
        customer_name || ' - New inquiry',
        customer_name || ' inquiry ' || inquiry_number ||
          ' is available for vendor pricing.',
        jsonb_build_object(
          'route', '/inquiries/' || new.id::text,
          'inquiry_id', new.id::text,
          'event_type', 'inquiry_created'
        ),
        'inquiry-created-v3:' || new.id::text || ':' || recipient.recipient_id::text
      );
    end loop;
  end if;

  if tg_op = 'UPDATE' and (
    (
      lower(coalesce(old.status, '')) <> 'completed'
      and lower(coalesce(new.status, '')) = 'completed'
    ) or (
      lower(coalesce(old.status, '')) <> 'rejected'
      and lower(coalesce(new.status, '')) = 'rejected'
    )
  ) then
    for recipient in
      select distinct recipient_id from (
        select new.created_by as recipient_id
        union all
        select id from public.profiles
        where role = 'owner' and is_active = true
      ) recipients
      where recipient_id is not null
    loop
      perform public.enqueue_push_notification(
        recipient.recipient_id,
        case
          when lower(new.status) = 'completed'
            then 'inquiry_completed'
          else 'inquiry_rejected'
        end,
        customer_name || case
          when lower(new.status) = 'completed'
            then ' - Inquiry completed'
          else ' - Inquiry rejected'
        end,
        customer_name || ' inquiry ' || inquiry_number ||
          ' has been ' || lower(new.status) || '.',
        jsonb_build_object(
          'route', '/inquiries/' || new.id::text,
          'inquiry_id', new.id::text,
          'event_type', lower(new.status)
        ),
        'inquiry-result-v3:' || new.id::text || ':' || lower(new.status) ||
          ':' || recipient.recipient_id::text
      );
    end loop;
  end if;
  return new;
end;
$$;

commit;

-- ============================================================================
-- MODULE 13: cash_sales_employee_visibility.sql
-- ============================================================================

-- EWAY LINK ERP
-- Cash Sales shared operational visibility
-- Run once in the Supabase SQL Editor.
--
-- Business rule:
--   Owner, Coordinator and Employee accounts can view every Cash Invoice.
--   Existing create, ERP-entry and delete permissions remain unchanged.

begin;

alter table public.cash_sales enable row level security;
alter table public.cash_sale_items enable row level security;

drop policy if exists cash_sales_role_read on public.cash_sales;
create policy cash_sales_role_read
on public.cash_sales
for select
to authenticated
using (
  public.current_employee_role() in ('owner', 'coordinator', 'employee')
);

drop policy if exists cash_sale_items_role_read on public.cash_sale_items;
create policy cash_sale_items_role_read
on public.cash_sale_items
for select
to authenticated
using (
  public.current_employee_role() in ('owner', 'coordinator', 'employee')
  and exists (
    select 1
    from public.cash_sales sale
    where sale.id = cash_sale_id
  )
);

commit;

-- ============================================================================
-- MODULE 14: master_data_security.sql
-- ============================================================================

-- EWAY LINK Version 1 master-data security.
-- Restores RLS after legacy development scripts disabled it.

create or replace function public.is_active_employee()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and is_active = true
      and role in ('owner', 'coordinator', 'employee')
  );
$$;

grant execute on function public.is_active_employee() to authenticated;

alter table public.customers enable row level security;
alter table public.vendors enable row level security;
alter table public.items enable row level security;
alter table public.units enable row level security;
alter table public.company_settings enable row level security;
alter table public.notifications enable row level security;
alter table public.inquiry_vendor_quotes enable row level security;
alter table public.rate_history enable row level security;

do $$
declare policy_record record;
begin
  for policy_record in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('customers','vendors','items','units','company_settings','notifications','inquiry_vendor_quotes','rate_history')
  loop
    execute format('drop policy if exists %I on %I.%I',
      policy_record.policyname, policy_record.schemaname, policy_record.tablename);
  end loop;
end;
$$;

create policy master_customers_access on public.customers
for all to authenticated using (public.is_active_employee()) with check (public.is_active_employee());
create policy master_vendors_access on public.vendors
for all to authenticated using (public.is_active_employee()) with check (public.is_active_employee());
create policy master_items_access on public.items
for all to authenticated using (public.is_active_employee()) with check (public.is_active_employee());
create policy master_units_read on public.units
for select to authenticated using (public.is_active_employee());
create policy master_units_owner_write on public.units
for all to authenticated using (public.is_owner()) with check (public.is_owner());
create policy company_settings_read on public.company_settings
for select to authenticated using (public.is_active_employee());
create policy company_settings_owner_write on public.company_settings
for all to authenticated using (public.is_owner()) with check (public.is_owner());
create policy legacy_notifications_own_read on public.notifications
for select to authenticated using (target_user = auth.uid() or public.is_owner());
create policy inquiry_quotes_access on public.inquiry_vendor_quotes
for all to authenticated
using (
  public.is_owner() or exists (
    select 1
    from public.inquiry_items ii
    join public.inquiries i on i.id = ii.inquiry_id
    where ii.id = inquiry_item_id
      and (
        (public.current_employee_role() = 'coordinator' and i.created_by = auth.uid())
        or (public.current_employee_role() = 'employee' and i.coordinator_id = auth.uid())
      )
  )
)
with check (
  public.is_owner() or exists (
    select 1
    from public.inquiry_items ii
    join public.inquiries i on i.id = ii.inquiry_id
    where ii.id = inquiry_item_id
      and (
        (public.current_employee_role() = 'coordinator' and i.created_by = auth.uid())
        or (public.current_employee_role() = 'employee' and i.coordinator_id = auth.uid())
      )
  )
);
create policy rate_history_read on public.rate_history
for select to authenticated using (public.is_active_employee());
create policy rate_history_write on public.rate_history
for insert to authenticated with check (public.is_active_employee());

revoke all on public.customers, public.vendors, public.items from anon;
revoke all on public.units, public.company_settings from anon;
revoke all on public.notifications, public.inquiry_vendor_quotes, public.rate_history from anon;
grant select, insert, update on public.customers, public.vendors, public.items to authenticated;
grant select on public.units, public.company_settings to authenticated;
grant insert, update, delete on public.units, public.company_settings to authenticated;
grant select on public.notifications to authenticated;
grant select, insert, update, delete on public.inquiry_vendor_quotes to authenticated;
grant select, insert on public.rate_history to authenticated;

-- Secure the unused legacy public.users table when it exists. Authentication
-- is provided by auth.users + public.profiles; clients need no direct access.
do $$
begin
  if to_regclass('public.users') is not null then
    alter table public.users enable row level security;
    revoke all on public.users from anon, authenticated;
  end if;
end;
$$;

-- ============================================================================
-- MODULE 15: attendance_auto_checkout.sql
-- ============================================================================

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
