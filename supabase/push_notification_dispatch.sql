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
