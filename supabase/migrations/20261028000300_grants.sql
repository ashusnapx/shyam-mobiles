-- Table privileges. Current Supabase grants API roles nothing on new public tables, so every
-- privilege is explicit here; RLS (20261028000100) still decides which rows each role sees.
-- New tables must be added to this list in the migration that creates them.
-- https://supabase.com/docs/guides/api/securing-your-api

-- Start from zero whatever the project's default privileges are: older projects auto-grant everything,
-- newer ones still leave truncate/references/trigger/maintain on tables and update on sequences.
revoke all on all tables in schema public from anon, authenticated, service_role;
revoke all on all sequences in schema public from anon, authenticated;

-- Public catalog: anyone can browse.
grant select on public.categories, public.brands, public.products, public.product_images,
  public.variants, public.product_cards, public.store_settings to anon, authenticated;

-- Staff edit the catalog and settings (RLS: is_admin()).
grant insert, update, delete on public.categories, public.brands, public.products,
  public.product_images, public.variants to authenticated;
grant update on public.store_settings to authenticated;

-- Own rows (RLS: user_id = auth.uid()).
grant select, update (full_name, phone) on public.profiles to authenticated;
grant select, insert, delete on public.wishlist to authenticated;
grant select, insert, update, delete on public.cart_items, public.addresses to authenticated;

-- Orders are read-only to clients; every change goes through an RPC.
grant select on public.orders, public.order_items, public.order_events to authenticated;

-- Repairs: customers create and read their own; staff update (RLS). No insert of id, number or timestamps:
-- a chosen `number` would collide with the sequence later and block someone else's booking.
grant select, update on public.repair_bookings to authenticated;
grant insert (user_id, device_brand, device_model, issue, description, preferred_date, slot, contact_phone,
  status, quote_paise, admin_note) on public.repair_bookings to authenticated;
grant usage on sequence public.repair_number_seq to authenticated; -- the `number` default calls nextval()

-- admins and payment_events: no client access at all.

-- Edge Functions use the secret key (service_role: bypasses RLS, still needs privileges).
grant select, insert, update, delete on all tables in schema public to service_role;
