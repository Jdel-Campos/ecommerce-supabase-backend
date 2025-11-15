-- =============================================
-- SEED AUTH → PUBLIC (SAFE SYNCHRONIZATION)
-- DO NOT insert in auth.users. Use Admin API/Sign In/Sign Up to create users.
-- =============================================

BEGIN;

-- 1) Idempotent synchronization function
--   - Read auth.users
--   - Insert/update public.users as needed
--   - SECURITY DEFINER to allow reading in auth.* (adjust the OWNER if needed)
create or replace function public.sync_auth_users_to_public(target_emails text[] default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
begin
  -- Insert users that exist in auth.users and are not in public.users
  insert into public.users as pu (id, email, role, name)
  select
    au.id,
    au.email,
    coalesce(pu.role, 'customer') as role, -- default role if not exists
    coalesce((au.raw_user_meta_data->>'name'), pu.name) as name
  from auth.users au
  left join public.users pu on pu.id = au.id
  where (target_emails is null or au.email = any(target_emails))
    and pu.id is null
  on conflict (id) do nothing;

  -- Optional: update mutable fields (name) when coming from meta
  update public.users pu
  set name = coalesce(au.raw_user_meta_data->>'name', pu.name)
  from auth.users au
  where pu.id = au.id
    and (target_emails is null or au.email = any(target_emails))
    and (au.raw_user_meta_data->>'name') is not null
    and pu.name is distinct from (au.raw_user_meta_data->>'name');
end;
$$;

-- 2) Run the sync for the desired emails (adjust the list)
select public.sync_auth_users_to_public(ARRAY[
  'admin@example.com',
  'alice@example.com',
  'bob@example.com',
  'charlie@example.com'
]);

-- 3) Adjust the admin role (idempotent)
update public.users
set role = 'admin'
where email = 'admin@example.com';

-- 4) Checks
-- Should list synchronized users with their roles
table public.users;

-- Final summary (join with auth.users to check creation dates/metadata)
select
  u.id,
  u.email,
  u.role,
  u.name,
  a.created_at as auth_created_at
from public.users u
join auth.users a on a.id = u.id
where u.email in (
  'admin@example.com',
  'alice@example.com',
  'bob@example.com',
  'charlie@example.com'
)
order by u.email;

COMMIT;
