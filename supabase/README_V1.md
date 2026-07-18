# EWAY LINK Version 1 Supabase package

The Supabase SQL Editor needs only the canonical production installer for the
current Version 1 application. Historical SQL snippets may be deleted from the
Dashboard only after this package has been run and verified.

## Required installation

1. Open the Supabase project.
2. Open **SQL Editor** and create a new query.
3. Paste the complete contents of `eway_link_v1_production.sql`.
4. Select the `postgres` role and run it once.
5. Run `eway_link_v1_anon_lockdown.sql` once.
6. Create another query and run `eway_link_v1_audit.sql`.
7. Confirm every audit row is `OK`. Do not ignore `MISSING` or `WARNING` rows.

The production installer is idempotent. It creates or reconciles the Version 1
schema, functions, triggers, RLS policies, notification routing and the 24-hour
automatic attendance checkout without deleting operational records.

## Destructive utility

`production_data_reset.sql` permanently removes operational records. It is not
an installation or upgrade script. Keep it in source control for controlled
administrative use and never run it during normal production operation.

## Edge Functions

SQL does not deploy Supabase Edge Functions. The following functions remain in
`supabase/functions` and must stay deployed separately:

- `manage-employee`
- `send-push`

The `send-push` database webhook must continue to target the deployed
`send-push` Edge Function.

## Removing old Dashboard snippets

After the installer and audit both succeed, old saved SQL Editor snippets may
be deleted. Deleting a saved snippet removes only its text; it does not remove
database objects that were previously created by that snippet.
