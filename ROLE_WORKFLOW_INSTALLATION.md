# EWAY LINK Role Workflow Installation

## 1. Replace Flutter files

Extract the ZIP into the EWAY LINK project root and replace all included files.

## 2. Apply Supabase workflow security

Open Supabase Dashboard > SQL Editor. Copy and run the complete contents of:

`supabase/role_workflow_security.sql`

Run it once after the existing attendance, employee-account, Cash Sales and push-notification SQL foundations.

## 3. Validate and restart

Run:

`flutter analyze`

Stop the running application completely and start it again. Sign out and sign back in on each test account so the current profile role is refreshed.

## 4. Test in this order

1. Coordinator checks in, creates an inquiry and selects an Employee as Purchaser.
2. Confirm the Purchaser and Owner receive the new-inquiry notification.
3. Purchaser checks in, opens the assigned inquiry, enters vendor rates and completes it.
4. Confirm the creating Coordinator and Owner receive the completion notification.
5. Employee creates a Cash Invoice.
6. Confirm the Coordinator and Owner receive the Cash Invoice notification.
7. Coordinator marks it Entered into ERP.
8. Confirm only the Owner receives the ERP-entry notification.

Owner accounts can create both inquiries and Cash Invoices without attendance restrictions. Coordinator and Employee operational changes require an active attendance check-in.
