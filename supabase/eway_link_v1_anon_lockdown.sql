-- EWAY LINK ERP - VERSION 1 ANONYMOUS ACCESS LOCKDOWN
-- Run once after eway_link_v1_production.sql.
-- This changes privileges only; it does not delete or modify business data.

begin;

revoke all privileges on table
  public.profiles,
  public.customers,
  public.vendors,
  public.units,
  public.items,
  public.inquiries,
  public.inquiry_items,
  public.inquiry_vendor_quotes,
  public.rate_history,
  public.cash_sales,
  public.cash_sale_items,
  public.attendance_sessions,
  public.attendance_location_points,
  public.attendance_notifications,
  public.leave_requests,
  public.push_device_tokens,
  public.push_outbox,
  public.notifications,
  public.company_settings
from anon;

do $$
begin
  if to_regclass('public.users') is not null then
    revoke all privileges on table public.users from anon;
  end if;
end;
$$;

revoke all privileges on all sequences in schema public from anon;

-- New tables and sequences created by the postgres migration role must not
-- become anonymously accessible by default.
alter default privileges for role postgres in schema public
  revoke all privileges on tables from anon;
alter default privileges for role postgres in schema public
  revoke all privileges on sequences from anon;

-- Username resolution is the only Version 1 public-schema RPC required before
-- login. It returns only the internal email for an active matching username.
revoke all on function public.resolve_login_email(text) from anon;
grant execute on function public.resolve_login_email(text) to anon;

commit;

select
  grantee,
  table_schema,
  table_name,
  privilege_type
from information_schema.role_table_grants
where grantee = 'anon'
  and table_schema = 'public'
order by table_name, privilege_type;
