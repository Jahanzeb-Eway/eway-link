-- EWAY LINK Firebase Cloud Messaging device registration.
-- Run once in Supabase SQL Editor before launching the updated app.

create table if not exists public.push_device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  token text not null unique,
  platform text not null check (platform in ('android', 'ios', 'web')),
  app_id text not null,
  is_active boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists push_device_tokens_user_active
  on public.push_device_tokens(user_id, is_active);

alter table public.push_device_tokens enable row level security;

drop policy if exists "users_read_own_push_devices"
  on public.push_device_tokens;
create policy "users_read_own_push_devices"
on public.push_device_tokens
for select to authenticated
using (user_id = auth.uid());

create or replace function public.register_push_device(
  p_token text,
  p_platform text,
  p_app_id text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_platform not in ('android', 'ios', 'web') then
    raise exception 'Unsupported push platform';
  end if;

  insert into public.push_device_tokens (
    user_id,
    token,
    platform,
    app_id,
    is_active,
    last_seen_at,
    updated_at
  )
  values (
    auth.uid(),
    p_token,
    p_platform,
    p_app_id,
    true,
    now(),
    now()
  )
  on conflict (token) do update
  set user_id = excluded.user_id,
      platform = excluded.platform,
      app_id = excluded.app_id,
      is_active = true,
      last_seen_at = now(),
      updated_at = now();
end;
$$;

create or replace function public.unregister_push_device(p_token text)
returns void
language sql
security definer
set search_path = public
as $$
  update public.push_device_tokens
  set is_active = false,
      updated_at = now()
  where token = p_token
    and user_id = auth.uid();
$$;

revoke all on function public.register_push_device(text, text, text)
  from public;
grant execute on function public.register_push_device(text, text, text)
  to authenticated;

revoke all on function public.unregister_push_device(text)
  from public;
grant execute on function public.unregister_push_device(text)
  to authenticated;
