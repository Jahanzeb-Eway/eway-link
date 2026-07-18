# EWAY LINK Attendance + Leave Installation

This package combines annual leave management with the existing Attendance
module. There is no separate Leave menu.

## Included workflow

- Coordinator and employee accounts must check in before operational work.
- The first successful check-in unlocks the app for the rest of that calendar
  day, even after checkout.
- Each employee receives 21 paid working leave days per calendar year.
- Saturday and Sunday are weekend off-days and are never deducted.
- Employees apply from the Attendance screen.
- The owner receives the request in Attendance and can approve or reject it.
- Only approved requests reduce the remaining annual balance.
- The employee receives an in-app and push notification after the decision.
- The owner daily view shows approved employees as **On Leave** and weekends as
  **Weekend Off** instead of absent.

## Installation order

1. Replace the supplied Dart files using their included `lib/` paths.
2. In Supabase SQL Editor, run the complete file:
   `supabase/attendance_leave_management.sql`.
3. Run `flutter pub get`.
4. Run `flutter analyze`.
5. Stop the running app completely and start it again. Do not use only hot
   reload because the navigation and database workflow changed.

## Acceptance test

1. Sign in as an employee or coordinator and open Attendance.
2. Confirm the balance shows Annual 21, Approved Used 0, Pending 0, Remaining
   21 for a new employee.
3. Apply for a range containing a Saturday or Sunday and verify the displayed
   working-day count excludes those dates.
4. Sign in as the owner, open Attendance, and approve the request.
5. Sign back in as the employee and verify Approved Used increases and
   Remaining decreases only by the approved working days.
6. Check in, check out, then open another operational module. Access must remain
   unlocked for the rest of the day.
