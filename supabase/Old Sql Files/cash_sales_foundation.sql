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
