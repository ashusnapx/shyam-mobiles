-- RLS, table privileges, profile/address triggers, storage bucket.
begin;
create extension if not exists pgtap with schema extensions;
select plan(97);

-- Helpers -------------------------------------------------------------------

create schema tests;
grant usage on schema tests to anon, authenticated, service_role;
-- act as 'alice' | 'bob' | 'staff' (authenticated), 'anon', or 'service' (service_role); `reset role` to go back
create function tests.login(p_who text) returns void language plpgsql as $$
declare
  v_uid uuid := case p_who
    when 'alice' then '11111111-1111-1111-1111-111111111111'
    when 'bob' then '22222222-2222-2222-2222-222222222222'
    when 'staff' then '33333333-3333-3333-3333-333333333333' end;
  v_role text := case p_who when 'anon' then 'anon' when 'service' then 'service_role' else 'authenticated' end;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', v_role)::text, true);
  perform set_config('role', v_role, true);
end $$;

-- Fixtures (as postgres) ----------------------------------------------------

insert into auth.users (id, email, phone) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.dev', '919876543210'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.dev', '14155550100'),
  ('33333333-3333-3333-3333-333333333333', 'staff@test.dev', null);
insert into public.admins (user_id) values ('33333333-3333-3333-3333-333333333333');

insert into public.categories (id, slug, name, kind) values ('c0000000-0000-0000-0000-000000000001', 'test-cat', 'Test cat', 'phone');
insert into public.brands (id, slug, name) values ('b0000000-0000-0000-0000-000000000001', 'test-brand', 'Test');
insert into public.products (id, slug, name, brand_id, category_id, is_active) values
  ('a0000000-0000-0000-0000-000000000001', 'test-active', 'Test Active', 'b0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', true),
  ('a0000000-0000-0000-0000-000000000002', 'test-inactive', 'Test Inactive', 'b0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', false);
insert into public.variants (id, product_id, sku, name, price_paise, mrp_paise, stock, is_active) values
  ('d0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'T-1', 'Active', 10000, 12000, 10, true),
  ('d0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'T-2', 'Inactive', 10000, 12000, 10, false),
  ('d0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000002', 'T-3', 'Of inactive product', 10000, 12000, 10, true);
insert into public.product_images (product_id, path) values
  ('a0000000-0000-0000-0000-000000000001', 'test/active.webp'),
  ('a0000000-0000-0000-0000-000000000002', 'test/inactive.webp');

insert into public.addresses (id, user_id, name, phone, line1, city, state, pincode, is_default) values
  ('e0000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Alice', '+919876543210', '1 MG Road', 'Patna', 'Bihar', '800001', true),
  ('e0000000-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'Bob', '+919876543211', '2 MG Road', 'Patna', 'Bihar', '800001', true);
insert into public.cart_items (user_id, variant_id, qty) values
  ('11111111-1111-1111-1111-111111111111', 'd0000000-0000-0000-0000-000000000001', 1),
  ('22222222-2222-2222-2222-222222222222', 'd0000000-0000-0000-0000-000000000001', 2);
insert into public.wishlist (user_id, product_id) values
  ('11111111-1111-1111-1111-111111111111', 'a0000000-0000-0000-0000-000000000001'),
  ('22222222-2222-2222-2222-222222222222', 'a0000000-0000-0000-0000-000000000001');

delete from public.orders; -- rolled back at the end; keeps counts below exact
insert into public.orders (id, user_id, status, payment_method, subtotal_paise, total_paise, address) values
  ('f0000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'confirmed', 'cod', 10000, 10000, '{}'),
  ('f0000000-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'confirmed', 'cod', 10000, 10000, '{}');
insert into public.order_items (order_id, variant_id, product_name, variant_name, unit_price_paise, qty, gst_rate) values
  ('f0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'Test Active', 'Active', 10000, 1, 18),
  ('f0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000001', 'Test Active', 'Active', 10000, 1, 18);
insert into public.order_events (order_id, status) values
  ('f0000000-0000-0000-0000-000000000001', 'confirmed'),
  ('f0000000-0000-0000-0000-000000000002', 'confirmed');
insert into public.payment_events (razorpay_event_id, type, payload) values ('evt_test', 'payment.captured', '{}');

delete from public.repair_bookings;
insert into public.repair_bookings (id, user_id, device_brand, device_model, issue, preferred_date, slot, contact_phone) values
  ('90000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Apple', 'iPhone 13', 'screen', current_date + 1, 'morning', '+919876543210'),
  ('90000000-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'Samsung', 'Galaxy S21', 'battery', current_date + 1, 'evening', '+919876543211');

-- Profiles trigger ----------------------------------------------------------

select is((select phone::text from public.profiles where id = '11111111-1111-1111-1111-111111111111'), '+919876543210', 'signup copies an Indian phone to the profile');
select is((select phone::text from public.profiles where id = '22222222-2222-2222-2222-222222222222'), null, 'non +91 phone is left null');
select is((select count(*)::int from public.profiles where id = '33333333-3333-3333-3333-333333333333'), 1, 'email signup gets a profile');

-- Anon ----------------------------------------------------------------------

select tests.login('anon');
select is((select count(*)::int from public.products where slug like 'test-%'), 1, 'anon: only active products');
select is((select count(*)::int from public.variants where sku like 'T-%'), 1, 'anon: only active variants of active products');
select is((select count(*)::int from public.product_images where path like 'test/%'), 1, 'anon: only images of active products');
select is((select count(*)::int from public.product_cards where slug like 'test-%'), 1, 'anon: product_cards lists active products');
select is((select count(*)::int from public.categories where slug = 'test-cat'), 1, 'anon: reads categories');
select is((select count(*)::int from public.store_settings), 1, 'anon: reads store_settings');
-- anon has no grant at all on per-user tables (20261028000300_grants.sql)
select throws_ok('select 1 from public.cart_items', '42501', null, 'anon: cart denied');
select throws_ok('select 1 from public.wishlist', '42501', null, 'anon: wishlist denied');
select throws_ok('select 1 from public.addresses', '42501', null, 'anon: addresses denied');
select throws_ok('select 1 from public.orders', '42501', null, 'anon: orders denied');
select throws_ok('select 1 from public.order_items', '42501', null, 'anon: order items denied');
select throws_ok('select 1 from public.repair_bookings', '42501', null, 'anon: repairs denied');
select throws_ok('select 1 from public.profiles', '42501', null, 'anon: profiles denied');
select throws_ok('select 1 from public.payment_events', '42501', null, 'anon: payment_events denied');
select throws_ok('select 1 from public.admins', '42501', null, 'anon: admins denied');
select throws_ok($$insert into public.brands (slug, name) values ('x', 'X')$$, '42501', null, 'anon: cannot write catalog');
select throws_ok($$insert into public.cart_items (user_id, variant_id, qty) values ('11111111-1111-1111-1111-111111111111', 'd0000000-0000-0000-0000-000000000001', 1)$$,
  '42501', null, 'anon: cannot write cart');
select throws_ok('select public.is_admin()', '42501', null, 'anon: cannot call is_admin');

-- Alice: own rows only ------------------------------------------------------

select tests.login('alice');
select is(public.is_admin(), false, 'alice is not admin');
select is((select count(*)::int from public.products where slug like 'test-%'), 1, 'alice: inactive products hidden');
select throws_ok($$insert into public.brands (slug, name) values ('x', 'X')$$, '42501', null, 'alice: cannot insert catalog');
select is_empty($$update public.products set name = 'Hacked' where slug = 'test-active' returning 1$$, 'alice: cannot update products');
select is_empty($$update public.variants set stock = 0 where sku = 'T-1' returning 1$$, 'alice: cannot update variants');
select is_empty($$update public.store_settings set cod_max_paise = 1 returning 1$$, 'alice: cannot update store_settings');

select is((select count(*)::int from public.cart_items), 1, 'alice: sees only her cart');
select throws_ok($$insert into public.cart_items (user_id, variant_id, qty) values ('22222222-2222-2222-2222-222222222222', 'd0000000-0000-0000-0000-000000000002', 1)$$,
  '42501', null, 'alice: cannot add to bob''s cart');
select is_empty($$update public.cart_items set qty = 5 where user_id = '22222222-2222-2222-2222-222222222222' returning 1$$, 'alice: cannot change bob''s cart');
select is_empty($$delete from public.cart_items where user_id = '22222222-2222-2222-2222-222222222222' returning 1$$, 'alice: cannot delete bob''s cart');
select lives_ok($$update public.cart_items set qty = 3 where user_id = '11111111-1111-1111-1111-111111111111'$$, 'alice: updates her cart');
select throws_ok('truncate public.cart_items', '42501', null, 'alice: cannot truncate');

select is((select count(*)::int from public.wishlist), 1, 'alice: sees only her wishlist');
select throws_ok($$insert into public.wishlist (user_id, product_id) values ('22222222-2222-2222-2222-222222222222', 'a0000000-0000-0000-0000-000000000002')$$,
  '42501', null, 'alice: cannot write bob''s wishlist');
select is_empty($$delete from public.wishlist where user_id = '22222222-2222-2222-2222-222222222222' returning 1$$, 'alice: cannot delete bob''s wishlist');

select is((select count(*)::int from public.addresses), 1, 'alice: sees only her addresses');
select throws_ok($$insert into public.addresses (user_id, name, phone, line1, city, state, pincode) values ('22222222-2222-2222-2222-222222222222', 'X', '+919876543210', 'abc', 'Patna', 'Bihar', '800001')$$,
  '42501', null, 'alice: cannot add bob''s address');
select is_empty($$update public.addresses set city = 'Gaya' where user_id = '22222222-2222-2222-2222-222222222222' returning 1$$, 'alice: cannot edit bob''s address');

select is((select count(*)::int from public.profiles), 1, 'alice: sees only her profile');
select lives_ok($$update public.profiles set full_name = 'Alice A' where id = '11111111-1111-1111-1111-111111111111'$$, 'alice: edits her name');
select is_empty($$update public.profiles set full_name = 'X' where id = '22222222-2222-2222-2222-222222222222' returning 1$$, 'alice: cannot edit bob''s profile');
select throws_ok($$update public.profiles set id = '22222222-2222-2222-2222-222222222222'$$, '42501', null, 'alice: cannot change profile id');

select is((select array_agg(id::text) from public.orders), '{f0000000-0000-0000-0000-000000000001}', 'alice: sees only her order');
select is((select count(*)::int from public.order_items), 1, 'alice: sees only her order items');
select is((select count(*)::int from public.order_events), 1, 'alice: sees only her order events');
select throws_ok($$insert into public.orders (user_id, status, payment_method, subtotal_paise, total_paise, address) values ('11111111-1111-1111-1111-111111111111', 'delivered', 'cod', 1, 1, '{}')$$,
  '42501', null, 'alice: cannot insert orders');
select throws_ok($$update public.orders set payment_status = 'paid'$$, '42501', null, 'alice: cannot update orders');
select throws_ok($$delete from public.orders$$, '42501', null, 'alice: cannot delete orders');
select throws_ok($$update public.order_items set unit_price_paise = 1$$, '42501', null, 'alice: cannot update order items');
select throws_ok($$insert into public.order_events (order_id, status) values ('f0000000-0000-0000-0000-000000000001', 'delivered')$$, '42501', null, 'alice: cannot insert order events');
select throws_ok('select 1 from public.payment_events', '42501', null, 'alice: payment_events denied');
select throws_ok($$insert into public.payment_events (razorpay_event_id, type, payload) values ('x', 'x', '{}')$$, '42501', null, 'alice: cannot insert payment_events');
select throws_ok('select 1 from public.admins', '42501', null, 'alice: admins denied');
select throws_ok($$insert into public.admins (user_id) values ('11111111-1111-1111-1111-111111111111')$$, '42501', null, 'alice: cannot make herself admin');

-- Repairs: insert check
select is((select count(*)::int from public.repair_bookings), 1, 'alice: sees only her repairs');
select lives_ok($$insert into public.repair_bookings (user_id, device_brand, device_model, issue, preferred_date, slot, contact_phone)
  values ('11111111-1111-1111-1111-111111111111', 'OnePlus', '9', 'battery', (now() at time zone 'Asia/Kolkata')::date, 'morning', '+919876543210')$$, 'alice: books a repair for today');
select throws_ok($$insert into public.repair_bookings (user_id, device_brand, device_model, issue, preferred_date, slot, contact_phone, status)
  values ('11111111-1111-1111-1111-111111111111', 'OnePlus', '9', 'battery', current_date + 1, 'morning', '+919876543210', 'completed')$$, '42501', null, 'repair: status must be requested');
select throws_ok($$insert into public.repair_bookings (user_id, device_brand, device_model, issue, preferred_date, slot, contact_phone, quote_paise)
  values ('11111111-1111-1111-1111-111111111111', 'OnePlus', '9', 'battery', current_date + 1, 'morning', '+919876543210', 0)$$, '42501', null, 'repair: quote must be null');
select throws_ok($$insert into public.repair_bookings (user_id, device_brand, device_model, issue, preferred_date, slot, contact_phone, admin_note)
  values ('11111111-1111-1111-1111-111111111111', 'OnePlus', '9', 'battery', current_date + 1, 'morning', '+919876543210', 'vip')$$, '42501', null, 'repair: admin_note must be null');
select throws_ok($$insert into public.repair_bookings (user_id, device_brand, device_model, issue, preferred_date, slot, contact_phone)
  values ('11111111-1111-1111-1111-111111111111', 'OnePlus', '9', 'battery', (now() at time zone 'Asia/Kolkata')::date - 1, 'morning', '+919876543210')$$, '42501', null, 'repair: no past dates');
select throws_ok($$insert into public.repair_bookings (user_id, device_brand, device_model, issue, preferred_date, slot, contact_phone)
  values ('11111111-1111-1111-1111-111111111111', 'OnePlus', '9', 'battery', (now() at time zone 'Asia/Kolkata')::date + 31, 'morning', '+919876543210')$$, '42501', null, 'repair: at most 30 days ahead');
select throws_ok($$insert into public.repair_bookings (user_id, device_brand, device_model, issue, preferred_date, slot, contact_phone)
  values ('22222222-2222-2222-2222-222222222222', 'OnePlus', '9', 'battery', current_date + 1, 'morning', '+919876543210')$$, '42501', null, 'repair: cannot book for someone else');
select is_empty($$update public.repair_bookings set status = 'completed', quote_paise = 0 returning 1$$, 'alice: cannot update her repair');

-- Address rules
select lives_ok($$insert into public.addresses (user_id, name, phone, line1, city, state, pincode, is_default)
  values ('11111111-1111-1111-1111-111111111111', 'Office', '+919876543210', '3 Boring Road', 'Patna', 'Bihar', '800001', true)$$, 'alice: adds a second default address');
select is((select array_agg(name) from public.addresses where is_default), '{Office}', 'new default unsets the old one');
select lives_ok($$update public.addresses set is_default = true where id = 'e0000000-0000-0000-0000-000000000001'$$, 'alice: switches default back');
select is((select array_agg(name) from public.addresses where is_default), '{Alice}', 'exactly one default after switching');
select throws_ok($$insert into public.addresses (user_id, name, phone, line1, city, state, pincode, label)
  values ('11111111-1111-1111-1111-111111111111', 'Shop', '+919876543210', '4 Boring Road', 'Patna', 'Bihar', '800001', 'office')$$,
  '23514', null, 'address label must be home, work or other');
select is((select label from public.addresses where id = 'e0000000-0000-0000-0000-000000000001'), 'home', 'address label defaults to home');
select lives_ok($$insert into public.addresses (user_id, name, phone, line1, city, state, pincode)
  select '11111111-1111-1111-1111-111111111111', 'Extra ' || n, '+919876543210', 'Lane ' || n, 'Patna', 'Bihar', '800001' from generate_series(1, 8) n$$,
  'alice: fills up to 10 addresses');
select throws_ok($$insert into public.addresses (user_id, name, phone, line1, city, state, pincode)
  values ('11111111-1111-1111-1111-111111111111', 'Eleventh', '+919876543210', 'Lane 11', 'Patna', 'Bihar', '800001')$$, 'P0001', 'ADDRESS_LIMIT', 'the 11th address is refused');

-- Storage
select throws_ok($$insert into storage.objects (bucket_id, name) values ('product-images', 'test/x.webp')$$, '42501', null, 'alice: cannot upload product images');

-- Bob -----------------------------------------------------------------------

select tests.login('bob');
select is((select qty from public.cart_items), 2, 'bob: sees his cart, untouched by alice');
select is((select array_agg(id::text) from public.orders), '{f0000000-0000-0000-0000-000000000002}', 'bob: sees only his order');
select is((select count(*)::int from public.addresses), 1, 'bob: sees only his address');
select is((select count(*)::int from public.wishlist), 1, 'bob: wishlist intact');

-- Staff ---------------------------------------------------------------------

select tests.login('staff');
select is(public.is_admin(), true, 'staff is admin');
select is((select count(*)::int from public.products where slug like 'test-%'), 2, 'staff: sees inactive products');
select is((select count(*)::int from public.variants where sku like 'T-%'), 3, 'staff: sees inactive variants');
select is((select count(*)::int from public.product_images where path like 'test/%'), 2, 'staff: sees images of inactive products');
select is((select count(*)::int from public.repair_bookings), 3, 'staff: sees all repairs');
select lives_ok($$insert into public.repair_bookings (user_id, device_brand, device_model, issue, preferred_date, slot, contact_phone, status, quote_paise)
  values ('22222222-2222-2222-2222-222222222222', 'Vivo', 'V30', 'charging', current_date, 'evening', '+919876543211', 'confirmed', 50000)$$, 'staff: books a walk-in repair for a customer');
select is((select count(*)::int from public.orders), 2, 'staff: sees all orders');
select is((select count(*)::int from public.order_items), 2, 'staff: sees all order items');
select isnt_empty($$update public.products set is_active = true where slug = 'test-inactive' returning 1$$, 'staff: updates products');
select lives_ok($$insert into public.brands (slug, name) values ('test-brand-2', 'Test 2')$$, 'staff: inserts brands');
select isnt_empty($$update public.store_settings set delivery_fee_paise = 5900 returning 1$$, 'staff: updates store_settings');
select throws_ok($$update public.store_settings set store_lat = 24.0670269, store_lng = null$$, '23514', null,
  'store_settings: a map pin needs both lat and lng');
select lives_ok($$update public.store_settings set store_lat = 24.0670269, store_lng = 82.6307508$$, 'store_settings: full map pin saves');
select throws_ok($$update public.store_settings set store_photos = array_fill('store/x.jpg'::text, array[9])$$, '23514', null,
  'store_settings: at most 8 store photos');
select throws_ok($$update public.store_settings set store_maps_url = 'javascript:alert(1)'$$, '23514', null,
  'store_settings: maps link must be https');
select isnt_empty($$update public.repair_bookings set status = 'confirmed', quote_paise = 150000 where id = '90000000-0000-0000-0000-000000000002' returning 1$$,
  'staff: updates repairs');
select throws_ok($$update public.orders set status = 'delivered'$$, '42501', null, 'staff: no direct order updates either');
select throws_ok('select 1 from public.payment_events', '42501', null, 'staff: payment_events denied');
select lives_ok($$insert into storage.objects (bucket_id, name) values ('product-images', 'test/x.webp')$$, 'staff: uploads product images');

reset role;
select results_eq(
  $$select public, file_size_limit, allowed_mime_types from storage.buckets where id = 'product-images'$$,
  $$values (true, 5242880::bigint, '{image/webp,image/jpeg,image/png}'::text[])$$,
  'product-images bucket: public, 5 MB, webp/jpeg/png');

select * from finish();
rollback;
