-- EWAY LINK ERP - VERSION 1 READ-ONLY DATABASE AUDIT
-- Run after eway_link_v1_production.sql. This script does not change business data.

with expected_tables(table_name) as (
  values
    ('profiles'), ('customers'), ('vendors'), ('units'), ('items'),
    ('inquiries'), ('inquiry_items'), ('inquiry_vendor_quotes'), ('rate_history'),
    ('cash_sales'), ('cash_sale_items'), ('attendance_sessions'),
    ('attendance_location_points'), ('attendance_notifications'), ('leave_requests'),
    ('push_device_tokens'), ('push_outbox'), ('notifications'), ('company_settings')
), table_checks as (
  select
    'TABLE'::text as object_type,
    expected.table_name as object_name,
    case when tables.tablename is null then 'MISSING' else 'OK' end as status,
    case
      when tables.tablename is null then 'Required public table is missing.'
      when not tables.rowsecurity then 'WARNING: RLS is disabled.'
      else 'Present; RLS enabled.'
    end as details
  from expected_tables expected
  left join pg_tables tables
    on tables.schemaname = 'public' and tables.tablename = expected.table_name
), expected_functions(function_name) as (
  values
    ('is_owner'), ('current_employee_role'), ('has_attendance_today'),
    ('has_active_attendance'), ('resolve_login_email'), ('list_inquiry_purchasers'),
    ('next_cash_sale_number'), ('create_cash_sale'), ('get_last_customer_item_sale'),
    ('count_leave_working_days'), ('get_leave_balance'), ('get_my_leave_balance'),
    ('apply_for_leave'), ('review_leave_request'), ('register_push_device'),
    ('unregister_push_device'), ('enqueue_push_notification'),
    ('auto_checkout_expired_attendance_sessions')
), function_checks as (
  select
    'FUNCTION'::text as object_type,
    expected.function_name as object_name,
    case when routines.routine_name is null then 'MISSING' else 'OK' end as status,
    case when routines.routine_name is null then 'Required function is missing.'
      else 'Present.' end as details
  from expected_functions expected
  left join information_schema.routines routines
    on routines.specific_schema = 'public'
   and routines.routine_name = expected.function_name
), expected_triggers(trigger_name) as (
  values
    ('on_auth_user_created'),
    ('enforce_inquiry_workflow_trigger'),
    ('enforce_inquiry_item_workflow_trigger'),
    ('enforce_cash_sale_workflow_trigger'),
    ('inquiry_push_notification_trigger'),
    ('cash_sale_push_notification_trigger'),
    ('attendance_owner_notification_trigger'),
    ('attendance_push_notification_trigger'),
    ('leave_notification_trigger')
), trigger_checks as (
  select
    'TRIGGER'::text as object_type,
    expected.trigger_name as object_name,
    case when triggers.trigger_name is null then 'MISSING' else 'OK' end as status,
    case when triggers.trigger_name is null then 'Required trigger is missing.'
      else 'Present on ' || triggers.event_object_table || '.' end as details
  from expected_triggers expected
  left join information_schema.triggers triggers
    on triggers.trigger_schema in ('public', 'auth')
   and triggers.trigger_name = expected.trigger_name
), column_checks as (
  select
    'COLUMN'::text as object_type,
    expected.table_name || '.' || expected.column_name as object_name,
    case when columns.column_name is null then 'MISSING' else 'OK' end as status,
    case when columns.column_name is null then 'Required column is missing.'
      else columns.data_type || '; nullable=' || columns.is_nullable end as details
  from (values
    ('profiles','username'),
    ('inquiries','coordinator_id'),
    ('inquiry_items','selected_vendor_id'),
    ('cash_sales','erp_entered_at'),
    ('attendance_sessions','check_in_address'),
    ('attendance_sessions','check_out_address'),
    ('attendance_sessions','auto_checked_out'),
    ('attendance_location_points','place_name'),
    ('leave_requests','working_days')
  ) expected(table_name, column_name)
  left join information_schema.columns columns
    on columns.table_schema = 'public'
   and columns.table_name = expected.table_name
   and columns.column_name = expected.column_name
), policy_summary as (
  select
    'RLS POLICY COUNT'::text as object_type,
    table_name as object_name,
    case
      when table_name = 'push_outbox' and count(policyname) = 0 then 'OK'
      when count(policyname) > 0 then 'OK'
      else 'MISSING'
    end as status,
    case
      when table_name = 'push_outbox' and count(policyname) = 0
        then 'No client policies by design; service delivery only.'
      else count(policyname)::text || ' policy/policies installed.'
    end as details
  from (
    select expected.table_name, policies.policyname
    from expected_tables expected
    left join pg_policies policies
      on policies.schemaname = 'public' and policies.tablename = expected.table_name
  ) policy_rows
  group by table_name
), cron_check as (
  select
    'CRON JOB'::text as object_type,
    'eway-attendance-auto-checkout'::text as object_name,
    case
      when to_regclass('cron.job') is null then 'MISSING'
      when exists (select 1 from cron.job where jobname = 'eway-attendance-auto-checkout') then 'OK'
      else 'MISSING'
    end as status,
    case
      when to_regclass('cron.job') is null then 'pg_cron is unavailable.'
      when exists (select 1 from cron.job where jobname = 'eway-attendance-auto-checkout')
        then 'Automatic checkout schedule is installed.'
      else 'Automatic checkout schedule is missing.'
    end as details
), security_checks as (
  select
    'SECURITY'::text as object_type,
    'anon table privileges'::text as object_name,
    case when count(*) = 0 then 'OK' else 'WARNING' end as status,
    case when count(*) = 0 then 'Anonymous role has no direct business-table privileges.'
      else count(*)::text || ' anonymous privilege record(s) require review.' end as details
  from information_schema.role_table_grants
  where grantee = 'anon' and table_schema = 'public'
    and table_name in (
      'customers','vendors','items','inquiries','inquiry_items','cash_sales',
      'cash_sale_items','attendance_sessions','attendance_location_points','leave_requests'
    )
), all_checks as (
  select * from table_checks
  union all select * from function_checks
  union all select * from trigger_checks
  union all select * from column_checks
  union all select * from policy_summary
  union all select * from cron_check
  union all select * from security_checks
)
select object_type, object_name, status, details
from all_checks
order by
  case status when 'MISSING' then 1 when 'WARNING' then 2 else 3 end,
  object_type,
  object_name;
