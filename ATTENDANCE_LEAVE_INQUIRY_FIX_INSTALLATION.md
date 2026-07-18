# EWAY LINK Attendance, Leave and Inquiry Employee Access Fix

## Correct role workflow

- Owner and Coordinator can create customer inquiries.
- Employees cannot create or reject inquiries.
- All active Employees can see the Inquiry pricing queue.
- Employees edit inquiries through a restricted pricing screen.
- Employee-editable fields: Vendor and Rate only.
- Customer, Inquiry Number, Purchaser, Due Date, Item, Unit, Quantity and
  Previous Rate remain locked.
- Employees can save pricing as a draft or save and complete the inquiry.
- New inquiry push notifications go to the Owner and all active Employees.

## Other corrections included

- Fixed the Flutter leave-dialog lifecycle assertion on Chrome.
- Removed the two unnecessary null assertion warnings.
- Attendance time is displayed in Pakistan Standard Time using 12-hour AM/PM
  format with a PKT suffix.
- Annual leave remains 21 working days and excludes Saturday and Sunday.
- A completed check-in/check-out keeps operational access unlocked for the rest
  of the Pakistan calendar day.

## Installation

1. Extract this ZIP into the EWAY Link project root and replace the supplied
   files using their existing folders.
2. In Supabase SQL Editor run, in this order:
   - `supabase/attendance_leave_management.sql`
   - `supabase/inquiry_employee_pricing_access.sql`
3. Run `flutter pub get` and then `flutter analyze`.
4. Stop the running application completely and start it again.
5. Sign out and sign back in as Ali or Yasin so the refreshed RLS permissions
   and profile are used.

## Test

1. Create an inquiry as the Owner or Numra.
2. Sign in as Ali and confirm the inquiry appears but no Create Inquiry button
   appears.
3. Open Edit Inquiry and confirm only Vendor and Rate can be changed.
4. Save the rates and verify the Owner/Coordinator can see them.
5. Apply for leave, approve it as Owner, and confirm the approved working days
   are deducted while Saturday and Sunday are excluded.
