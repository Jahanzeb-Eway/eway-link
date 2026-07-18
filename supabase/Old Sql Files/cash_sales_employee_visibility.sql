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

