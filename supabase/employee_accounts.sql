-- EWAY LINK Employee Accounts
-- Run once in the Supabase SQL Editor.

alter table public.profiles
  add column if not exists username text;

update public.profiles as profile
set username = lower(split_part(auth_user.email, '@', 1))
from auth.users as auth_user
where auth_user.id = profile.id
  and (profile.username is null or btrim(profile.username) = '');

update public.profiles
set username = lower(regexp_replace(full_name, '[^a-zA-Z0-9._-]+', '.', 'g'))
where username is null or btrim(username) = '';

alter table public.profiles
  alter column username set not null;

create unique index if not exists profiles_username_lower_unique
  on public.profiles (lower(username));

alter table public.profiles
  drop constraint if exists profiles_username_format;

alter table public.profiles
  add constraint profiles_username_format
  check (username = lower(username) and username ~ '^[a-z0-9._-]{3,32}$');

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  resolved_username text;
begin
  resolved_username := lower(coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'username'), ''),
    split_part(new.email, '@', 1)
  ));

  insert into public.profiles (id, full_name, username)
  values (
    new.id,
    coalesce(
      nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
      resolved_username
    ),
    resolved_username
  )
  on conflict (id) do update
  set full_name = excluded.full_name,
      username = excluded.username,
      updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Resolves a username to its internal Supabase identity. This keeps existing
-- accounts compatible while all EWAY LINK screens use usernames only.
create or replace function public.resolve_login_email(p_username text)
returns text
language sql
stable
security definer
set search_path = public, auth
as $$
  select auth_user.email
  from public.profiles as profile
  join auth.users as auth_user on auth_user.id = profile.id
  where lower(profile.username) = lower(btrim(p_username))
    and profile.is_active = true
  limit 1;
$$;

revoke all on function public.resolve_login_email(text) from public;
grant execute on function public.resolve_login_email(text) to anon, authenticated;

comment on column public.profiles.username is
  'Lowercase EWAY LINK login username. Employee email identities remain internal.';
