# EWAY LINK Employee Accounts Installation

## 1. Replace the Flutter files

Extract the ZIP into the EWAY LINK project root and allow it to replace the included files.

## 2. Add the database foundation

Open Supabase Dashboard > SQL Editor. Copy the complete contents of:

`supabase/employee_accounts.sql`

Run it once. Your existing Owner username becomes the part before `@` in the current authentication email. For example, `jahanzeb.khan@eway.com.pk` becomes `jahanzeb.khan`.

## 3. Deploy the employee Edge Function

Open Supabase Dashboard > Edge Functions and create a function named exactly:

`manage-employee`

Replace its `index.ts` with the complete file at:

`supabase/functions/manage-employee/index.ts`

Turn **Verify JWT** off for this function. The function performs its own user-token validation and allows only an active Owner account.

Deploy the function.

## 4. Validate Flutter

Run:

`flutter analyze`

Then run the app and sign in using the Owner username, not the email address.

## 5. Create the employee

Open **Employees** in the left menu, select **New Employee**, and enter:

- Full name
- Username
- Employee or Coordinator role
- Temporary password of at least 8 characters

The employee signs in using only the username and temporary password. No employee email is required or shown.
