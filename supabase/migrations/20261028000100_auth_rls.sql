-- Profiles trigger, admin check, address rules, row-level security, storage.

-- Profiles ------------------------------------------------------------------

create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_phone text := '+' || ltrim(coalesce(new.phone, ''), '+'); -- auth stores phones without '+'
  v_name text := left(btrim(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name')), 80);
begin
  insert into public.profiles (id, full_name, phone)
  values (
    new.id,
    case when public.is_name(v_name) then v_name end, -- a sign-up must never fail on a junk display name
    case when v_phone ~ '^\+91[6-9][0-9]{9}$' then v_phone end
  );
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

-- Auth: no passwords -------------------------------------------------------

-- Sign-in is passwordless (SPEC), but Auth's /signup still accepts a password and nothing proves who owns the
-- email or phone. Without this, anyone could pre-register a customer's email/phone with a password, and once the
-- customer signs in by code, read their orders and addresses with that password. This access token hook
-- (config.toml; dashboard: Auth → Hooks) refuses every token from a password grant, refreshes included; email and
-- phone confirmations stop /signup from issuing a session at all.
create schema private;
-- accounts on these email domains may still use a password: seed.sql adds the local dev accounts'; empty in production
create table private.password_sign_in_domains (domain text primary key);
alter table private.password_sign_in_domains enable row level security;
create policy "auth reads" on private.password_sign_in_domains for select to supabase_auth_admin using (true);

create function private.custom_access_token_hook(event jsonb) returns jsonb
language sql stable set search_path = '' as $$
  select case
    when event -> 'claims' -> 'amr' @> '[{"method": "password"}]' and not exists (
      select 1 from auth.users u join private.password_sign_in_domains d on d.domain = split_part(u.email, '@', 2)
      where u.id = (event ->> 'user_id')::uuid)
    then jsonb_build_object('error', jsonb_build_object('http_code', 403, 'message', 'Sign in with a one-time code.'))
    else event
  end;
$$;

grant usage on schema private to supabase_auth_admin;
grant select on private.password_sign_in_domains to supabase_auth_admin;
revoke execute on function private.custom_access_token_hook(jsonb) from public, anon, authenticated;
grant execute on function private.custom_access_token_hook(jsonb) to supabase_auth_admin;

-- Admins --------------------------------------------------------------------

create function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.admins where user_id = (select auth.uid()));
$$;

-- Addresses -----------------------------------------------------------------

-- Max 10 per user; setting is_default clears the user's other default in the same statement.
create function public.addresses_before_write() returns trigger
language plpgsql set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('addresses:' || new.user_id, 0)); -- serialize per user
  if tg_op = 'INSERT' and (select count(*) from public.addresses where user_id = new.user_id) >= 10 then
    raise exception 'ADDRESS_LIMIT';
  end if;
  if new.is_default then
    update public.addresses set is_default = false
    where user_id = new.user_id and id <> new.id and is_default;
  end if;
  return new;
end $$;

create trigger addresses_before_write before insert or update of is_default on public.addresses
for each row execute function public.addresses_before_write();

-- Cart: max 20 lines per user (an upsert of an existing line is an update, not a new line).
create function public.cart_items_before_insert() returns trigger
language plpgsql set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('cart:' || new.user_id, 0));
  if (select count(*) from public.cart_items where user_id = new.user_id) >= 20
     and not exists (select 1 from public.cart_items where user_id = new.user_id and variant_id = new.variant_id) then
    raise exception 'CART_LIMIT' using detail = 'at most 20 lines in a cart';
  end if;
  return new;
end $$;

create trigger cart_items_before_insert before insert on public.cart_items
for each row execute function public.cart_items_before_insert();

-- Repairs: a customer has at most 3 open bookings; staff (walk-ins) are exempt.
create function public.repair_bookings_before_insert() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.user_id is null or public.is_admin() then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended('repairs:' || new.user_id, 0));
  if (select count(*) from public.repair_bookings
      where user_id = new.user_id and status not in ('completed', 'cancelled')) >= 3 then
    raise exception 'REPAIR_LIMIT' using detail = 'at most 3 open repair bookings';
  end if;
  return new;
end $$;

create trigger repair_bookings_before_insert before insert on public.repair_bookings
for each row execute function public.repair_bookings_before_insert();

revoke execute on function public.handle_new_user(), public.is_admin(), public.addresses_before_write(),
  public.cart_items_before_insert(), public.repair_bookings_before_insert()
  from public, anon, authenticated;
grant execute on function public.is_admin() to authenticated, service_role;

-- Table privileges: 20261028000300_grants.sql.
-- At most one permissive policy per table, role and action: Postgres runs every matching permissive
-- policy for every row (advisor 0006 multiple_permissive_policies), so staff access is OR-ed in instead.

-- Policies: catalog and settings -------------------------------------------

create policy "public read" on public.categories for select to anon, authenticated using (true);
create policy "public read" on public.brands for select to anon, authenticated using (true);
create policy "public read" on public.store_settings for select to anon, authenticated using (true);

-- customers see active items only; staff also see inactive ones
create policy "public read" on public.products for select to anon using (is_active);
create policy "read" on public.products for select to authenticated
  using (is_active or (select public.is_admin()));
create policy "public read" on public.variants for select to anon
  using (is_active and exists (select 1 from public.products p where p.id = product_id and p.is_active));
create policy "read" on public.variants for select to authenticated
  using ((is_active and exists (select 1 from public.products p where p.id = product_id and p.is_active))
         or (select public.is_admin()));
create policy "public read" on public.product_images for select to anon
  using (exists (select 1 from public.products p where p.id = product_id and p.is_active));
create policy "read" on public.product_images for select to authenticated
  using (exists (select 1 from public.products p where p.id = product_id and p.is_active) or (select public.is_admin()));

do $$
declare t text;
begin
  foreach t in array array['categories', 'brands', 'products', 'variants', 'product_images'] loop
    execute format('create policy "admin insert" on public.%I for insert to authenticated with check ((select public.is_admin()))', t);
    execute format('create policy "admin update" on public.%I for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()))', t);
    execute format('create policy "admin delete" on public.%I for delete to authenticated using ((select public.is_admin()))', t);
  end loop;
end $$;
create policy "admin update" on public.store_settings for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- Policies: the user's own rows ---------------------------------------------

create policy "own read" on public.profiles for select to authenticated
  using (id = (select auth.uid()));
create policy "own update" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "own rows" on public.wishlist for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "own rows" on public.cart_items for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "own rows" on public.addresses for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Policies: orders (read-only; writes go through RPCs) -----------------------

create policy "own or admin read" on public.orders for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
-- the subquery is itself filtered by the orders policy above
create policy "own or admin read" on public.order_items for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id));
create policy "own or admin read" on public.order_events for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id));

-- admins, payment_events: no policies, no client access.

-- Policies: repairs ---------------------------------------------------------

create policy "own or admin read" on public.repair_bookings for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
-- customers book for themselves; "today" is the shop's date (IST), not UTC. Staff book anything.
create policy "own or admin insert" on public.repair_bookings for insert to authenticated
  with check (
    (user_id = (select auth.uid())
     and status = 'requested' and quote_paise is null and admin_note is null
     and preferred_date between (now() at time zone 'Asia/Kolkata')::date
                            and (now() at time zone 'Asia/Kolkata')::date + 30)
    or (select public.is_admin())
  );
create policy "admin update" on public.repair_bookings for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- Storage: product images ---------------------------------------------------

-- public bucket: anyone can download by URL; only admins upload, replace or delete
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('product-images', 'product-images', true, 5242880, '{image/webp,image/jpeg,image/png}');

create policy "product-images admin write" on storage.objects for all to authenticated
  using (bucket_id = 'product-images' and (select public.is_admin()))
  with check (bucket_id = 'product-images' and (select public.is_admin()));
