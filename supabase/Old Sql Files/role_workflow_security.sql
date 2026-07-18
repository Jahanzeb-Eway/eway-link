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
