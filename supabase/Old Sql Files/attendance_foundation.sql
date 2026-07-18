-- EWAY LINK Attendance Foundation
-- Run once in the Supabase SQL Editor.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  role text not null default 'employee'
    check (role in ('owner', 'coordinator', 'employee')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

create or replace function public.is_owner()
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'owner' and is_active = true
  );
$$;

alter table public.profiles enable row level security;

drop policy if exists "profiles_read_own_or_owner" on public.profiles;
create policy "profiles_read_own_or_owner"
on public.profiles for select
to authenticated
using (id = auth.uid() or public.is_owner());

drop policy if exists "owners_update_profiles" on public.profiles;
create policy "owners_update_profiles"
on public.profiles for update
to authenticated
using (public.is_owner())
with check (public.is_owner());

-- After creating your own user in Supabase Authentication, promote it once:
-- update public.profiles
-- set role = 'owner', full_name = 'Jahanzeb Khan'
-- where id = (select id from auth.users where email = 'YOUR_EMAIL');
