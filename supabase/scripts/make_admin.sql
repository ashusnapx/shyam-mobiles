-- Promote a user to staff (they must have signed in once). Match by email or phone:
--   psql "$DB_URL" -v who=owner@example.com -f supabase/scripts/make_admin.sql
--   psql "$DB_URL" -v who=+919876543210 -f supabase/scripts/make_admin.sql
\set ON_ERROR_STOP on

insert into public.admins (user_id)
select id from auth.users
where lower(email) = lower(:'who') or phone = ltrim(:'who', '+')
on conflict do nothing;

-- prints the matching user; no row means nobody signed in with that email/phone yet
select u.id, u.email, u.phone, a.created_at as admin_since
from auth.users u join public.admins a on a.user_id = u.id
where lower(u.email) = lower(:'who') or u.phone = ltrim(:'who', '+');
