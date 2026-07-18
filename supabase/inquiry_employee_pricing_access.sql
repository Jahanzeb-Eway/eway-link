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
