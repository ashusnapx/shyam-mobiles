-- place_order, cancel_order, cancel_repair, admin_update_order, admin_set_imeis, admin_dashboard.
begin;
create extension if not exists pgtap with schema extensions;
select plan(68);

create schema tests;
grant usage on schema tests to anon, authenticated, service_role;
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
-- the order id stored under a name with tests.keep()
create function tests.id(p_name text) returns uuid language sql as $$ select current_setting('tests.' || p_name)::uuid $$;
create function tests.keep(p_name text, p_id uuid) returns uuid language sql as $$ select set_config('tests.' || p_name, p_id::text, true)::uuid $$;
create function tests.stock(p_sku text) returns int language sql security definer set search_path = '' as $$
  select stock from public.variants where sku = p_sku $$;
grant execute on all functions in schema tests to anon, authenticated, service_role;

-- Fixtures ------------------------------------------------------------------

-- deterministic dashboard numbers: hide existing data inside this transaction
delete from public.orders;
delete from public.repair_bookings;
update public.products set is_active = false;
update public.store_settings set delivery_fee_paise = 4900, free_delivery_min_paise = 99900, cod_enabled = true, cod_max_paise = 2500000;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.dev'),
  ('33333333-3333-3333-3333-333333333333', 'staff@test.dev');
insert into public.admins (user_id) values ('33333333-3333-3333-3333-333333333333');

insert into public.categories (id, slug, name, kind) values ('c0000000-0000-0000-0000-000000000001', 'test-cat', 'Test cat', 'phone');
insert into public.brands (id, slug, name) values ('b0000000-0000-0000-0000-000000000001', 'test-brand', 'Test');
insert into public.products (id, slug, name, brand_id, category_id, gst_rate, is_active) values
  ('a0000000-0000-0000-0000-000000000001', 'test-phone', 'Test Phone', 'b0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 18, true),
  ('a0000000-0000-0000-0000-000000000002', 'test-retired', 'Test Retired', 'b0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 18, false);
insert into public.product_images (product_id, path, sort) values
  ('a0000000-0000-0000-0000-000000000001', 'test/second.webp', 1),
  ('a0000000-0000-0000-0000-000000000001', 'test/cover.webp', 0);
insert into public.variants (id, product_id, sku, name, price_paise, mrp_paise, stock, is_active) values
  ('d0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'T-CHEAP', '4 GB', 50000, 60000, 5, true),
  ('d0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'T-PRICEY', '12 GB', 1500000, 1600000, 10, true),
  ('d0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'T-OFF', 'Off', 10000, 10000, 10, false),
  ('d0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'T-EMPTY', 'Empty', 20000, 20000, 0, true),
  ('d0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000002', 'T-RETIRED', 'Retired', 10000, 10000, 5, true);

insert into public.addresses (id, user_id, name, phone, line1, line2, city, district, state, pincode, label) values
  ('e0000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Alice', '+919876543210', '1 MG Road', 'Flat 2', 'Danapur', 'Patna', 'Bihar', '801503', 'work'),
  ('e0000000-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'Bob', '+919876543211', '2 MG Road', null, 'Patna', null, 'Bihar', '800001', 'home');

-- place_order: failures -----------------------------------------------------

select tests.login('anon');
select throws_ok($$select public.place_order('e0000000-0000-0000-0000-000000000001', 'cod')$$, '42501', null, 'anon cannot place orders');

select tests.login('alice');
select throws_ok($$select public.place_order('e0000000-0000-0000-0000-000000000001', 'cod')$$, 'P0001', 'CART_EMPTY', 'empty cart');

insert into public.cart_items (user_id, variant_id, qty) values ('11111111-1111-1111-1111-111111111111', 'd0000000-0000-0000-0000-000000000001', 1);
select throws_ok($$select public.place_order('e0000000-0000-0000-0000-000000000002', 'cod')$$, 'P0001', 'ADDRESS_NOT_FOUND', 'someone else''s address');
select throws_ok($$select public.place_order(gen_random_uuid(), 'cod')$$, 'P0001', 'ADDRESS_NOT_FOUND', 'unknown address');

insert into public.cart_items (user_id, variant_id, qty) values ('11111111-1111-1111-1111-111111111111', 'd0000000-0000-0000-0000-000000000004', 1);
select throws_ok($$select public.place_order('e0000000-0000-0000-0000-000000000001', 'cod')$$, 'P0001', 'OUT_OF_STOCK', 'not enough stock');
delete from public.cart_items where variant_id = 'd0000000-0000-0000-0000-000000000004';

insert into public.cart_items (user_id, variant_id, qty) values ('11111111-1111-1111-1111-111111111111', 'd0000000-0000-0000-0000-000000000003', 1);
select throws_ok($$select public.place_order('e0000000-0000-0000-0000-000000000001', 'cod')$$, 'P0001', 'OUT_OF_STOCK', 'inactive variant');
delete from public.cart_items where variant_id = 'd0000000-0000-0000-0000-000000000003';

insert into public.cart_items (user_id, variant_id, qty) values ('11111111-1111-1111-1111-111111111111', 'd0000000-0000-0000-0000-000000000005', 1);
select throws_ok($$select public.place_order('e0000000-0000-0000-0000-000000000001', 'cod')$$, 'P0001', 'OUT_OF_STOCK', 'variant of an inactive product');
delete from public.cart_items where variant_id = 'd0000000-0000-0000-0000-000000000005';

update public.cart_items set qty = 5 where variant_id = 'd0000000-0000-0000-0000-000000000001';
update public.variants set stock = 4 where sku = 'T-CHEAP'; -- as alice: RLS makes this a no-op
select is(tests.stock('T-CHEAP'), 5, 'clients cannot change stock');
select is((select count(*)::int from public.cart_items), 1, 'failed checkouts leave the cart alone');

-- place_order: razorpay below the free-delivery threshold ---------------------

update public.cart_items set qty = 1;
select lives_ok($$select tests.keep('rzp', public.place_order('e0000000-0000-0000-0000-000000000001', 'razorpay'))$$, 'razorpay order placed');
select results_eq(
  $$select status::text, payment_status::text, subtotal_paise, delivery_fee_paise, total_paise from public.orders where id = tests.id('rzp')$$,
  $$values ('pending_payment', 'pending', 50000, 4900, 54900)$$,
  'totals from DB prices plus delivery fee');
select ok((select reserved_until between now() + interval '14 minutes' and now() + interval '16 minutes' from public.orders where id = tests.id('rzp')),
  'stock held for 15 minutes');
select matches((select number from public.orders where id = tests.id('rzp')), '^SM[0-9]{6}$', 'order number SM + 6 digits');
select is((select address from public.orders where id = tests.id('rzp')),
  '{"name": "Alice", "phone": "+919876543210", "line1": "1 MG Road", "line2": "Flat 2", "landmark": null, "city": "Danapur", "district": "Patna", "state": "Bihar", "pincode": "801503"}'::jsonb,
  'address snapshot has exactly the contract keys, district included');
select results_eq(
  $$select variant_id, product_name, variant_name, image_path, unit_price_paise, qty, gst_rate from public.order_items where order_id = tests.id('rzp')$$,
  $$values ('d0000000-0000-0000-0000-000000000001'::uuid, 'Test Phone', '4 GB', 'test/cover.webp', 50000, 1, 18.00::numeric(4,2))$$,
  'order item snapshot with first image by sort');
select results_eq($$select status::text from public.order_events where order_id = tests.id('rzp')$$, $$values ('pending_payment')$$, 'first timeline event');
select is(tests.stock('T-CHEAP'), 4, 'stock decremented');
select is_empty('select 1 from public.cart_items', 'cart cleared');

-- place_order: COD, free delivery ------------------------------------------

insert into public.cart_items (user_id, variant_id, qty) values ('11111111-1111-1111-1111-111111111111', 'd0000000-0000-0000-0000-000000000001', 2);
select lives_ok($$select tests.keep('cod', public.place_order('e0000000-0000-0000-0000-000000000001', 'cod'))$$, 'cod order placed');
select results_eq(
  $$select status::text, payment_status::text, subtotal_paise, delivery_fee_paise, total_paise, reserved_until from public.orders where id = tests.id('cod')$$,
  $$values ('confirmed', 'pending', 100000, 0, 100000, null::timestamptz)$$,
  'COD starts confirmed; free delivery at/above threshold');
select is(tests.stock('T-CHEAP'), 2, 'cod stock decremented');

-- COD rules
insert into public.cart_items (user_id, variant_id, qty) values ('11111111-1111-1111-1111-111111111111', 'd0000000-0000-0000-0000-000000000002', 2);
select throws_ok($$select public.place_order('e0000000-0000-0000-0000-000000000001', 'cod')$$, 'P0001', 'COD_UNAVAILABLE', 'COD refused above cod_max_paise');
reset role;
update public.store_settings set cod_enabled = false;
update public.cart_items set qty = 1;
select tests.login('alice');
select throws_ok($$select public.place_order('e0000000-0000-0000-0000-000000000001', 'cod')$$, 'P0001', 'COD_UNAVAILABLE', 'COD refused when disabled');
select lives_ok($$select tests.keep('big', public.place_order('e0000000-0000-0000-0000-000000000001', 'razorpay'))$$, 'same cart can pay online');
reset role;
update public.store_settings set cod_enabled = true;

-- cancel_order --------------------------------------------------------------

select tests.login('bob');
select throws_ok(format('select public.cancel_order(%L)', tests.id('rzp')), 'P0001', 'NOT_FOUND', 'bob cannot cancel alice''s order');
select tests.login('alice');
select lives_ok(format('select public.cancel_order(%L)', tests.id('rzp')), 'alice cancels her unpaid order');
select results_eq($$select status::text, reserved_until from public.orders where id = tests.id('rzp')$$, $$values ('cancelled', null::timestamptz)$$, 'order cancelled');
select is(tests.stock('T-CHEAP'), 3, 'cancel restocks');
select is((select note from public.order_events where order_id = tests.id('rzp') order by id desc limit 1), 'Cancelled by you.', 'unpaid cancel event has no refund line');
select throws_ok(format('select public.cancel_order(%L)', tests.id('rzp')), 'P0001', 'INVALID_TRANSITION', 'cannot cancel twice');

-- admin_update_order ----------------------------------------------------------

select throws_ok(format($$select public.admin_update_order(%L, 'packed')$$, tests.id('cod')), 'P0001', 'FORBIDDEN', 'customers cannot run admin_update_order');
select throws_ok($$select public.admin_set_imeis(gen_random_uuid(), '{}')$$, 'P0001', 'FORBIDDEN', 'customers cannot run admin_set_imeis');
select throws_ok('select public.admin_dashboard()', 'P0001', 'FORBIDDEN', 'customers cannot run admin_dashboard');

select tests.login('staff');
select throws_ok($$select public.admin_update_order(gen_random_uuid(), 'packed')$$, 'P0001', 'NOT_FOUND', 'unknown order');
select throws_ok(format($$select public.admin_update_order(%L, 'shipped')$$, tests.id('cod')), 'P0001', 'INVALID_TRANSITION', 'confirmed -> shipped skips packed');
select throws_ok(format($$select public.admin_update_order(%L, 'confirmed')$$, tests.id('big')), 'P0001', 'INVALID_TRANSITION', 'admin cannot confirm an unpaid order');
select throws_ok(format($$select public.admin_update_order(%L, 'pending_payment')$$, tests.id('rzp')), 'P0001', 'INVALID_TRANSITION', 'cancelled is final');
select lives_ok(format($$select public.admin_update_order(%L, 'packed')$$, tests.id('cod')), 'confirmed -> packed');
select lives_ok(format($$select public.admin_update_order(%L, 'shipped', 'Out for delivery', 'Delhivery', 'DL123')$$, tests.id('cod')), 'packed -> shipped');
select results_eq($$select courier, tracking_number from public.orders where id = tests.id('cod')$$, $$values ('Delhivery', 'DL123')$$, 'courier saved');
select lives_ok(format($$select public.admin_update_order(%L, 'shipped', null, null, 'DL124')$$, tests.id('cod')), 'same status edits tracking');
select results_eq($$select courier, tracking_number from public.orders where id = tests.id('cod')$$, $$values ('Delhivery', 'DL124')$$, 'tracking fixed, courier kept');
select throws_ok(format($$select public.admin_update_order(%L, 'cancelled')$$, tests.id('cod')), 'P0001', 'INVALID_TRANSITION', 'shipped cannot be cancelled');
select throws_ok(format($$select public.admin_update_order(%L, 'refunded')$$, tests.id('cod')), 'P0001', 'INVALID_TRANSITION', 'shipped cannot be refunded');
select lives_ok(format($$select public.admin_update_order(%L, 'delivered')$$, tests.id('cod')), 'shipped -> delivered');
select is((select payment_status::text from public.orders where id = tests.id('cod')), 'paid', 'COD becomes paid on delivery');
select results_eq($$select status::text from public.order_events where order_id = tests.id('cod') order by id$$,
  $$values ('confirmed'), ('packed'), ('shipped'), ('shipped'), ('delivered')$$, 'one event per transition, plus the tracking fix');
select is((select note from public.order_events where order_id = tests.id('cod') and status = 'shipped' order by id desc limit 1),
  'Courier and tracking updated: Delhivery · DL124', 'the customer sees the new tracking number');
select lives_ok(format($$select public.admin_update_order(%L, 'refunded', 'Returned')$$, tests.id('cod')), 'delivered -> refunded');
select results_eq($$select status::text, payment_status::text from public.orders where id = tests.id('cod')$$, $$values ('refunded', 'refunded')$$, 'refund recorded');
select is(tests.stock('T-PRICEY'), 9, 'online order holds stock');
select lives_ok(format($$select public.admin_update_order(%L, 'cancelled', 'Customer called')$$, tests.id('big')), 'admin cancels an unpaid order');
select is(tests.stock('T-PRICEY'), 10, 'admin cancel restocks');

-- admin_set_imeis -------------------------------------------------------------

select tests.login('alice');
insert into public.cart_items (user_id, variant_id, qty) values ('11111111-1111-1111-1111-111111111111', 'd0000000-0000-0000-0000-000000000001', 2);
select tests.keep('two', public.place_order('e0000000-0000-0000-0000-000000000001', 'cod'));
select tests.keep('item', (select id from public.order_items where order_id = tests.id('two')));
select tests.login('staff');
select throws_ok(format($$select public.admin_set_imeis(%L, '{356938035643809}')$$, tests.id('item')), 'P0001', 'INVALID_IMEIS', 'IMEI count must equal qty');
select throws_ok(format($$select public.admin_set_imeis(%L, '{356938035643809,35693803564381X}')$$, tests.id('item')), 'P0001', 'INVALID_IMEIS', 'IMEIs are 15 digits');
select throws_ok(format($$select public.admin_set_imeis(%L, '{356938035643809,35693803564380}')$$, tests.id('item')), 'P0001', 'INVALID_IMEIS', 'IMEIs are exactly 15 digits');
select throws_ok(format($$select public.admin_set_imeis(%L, '{356938035643809,356938035643809}')$$, tests.id('item')), 'P0001', 'INVALID_IMEIS', 'IMEIs are distinct');
select throws_ok(format($$select public.admin_set_imeis(%L, null)$$, tests.id('item')), 'P0001', 'INVALID_IMEIS', 'null IMEIs refused');
select lives_ok(format($$select public.admin_set_imeis(%L, '{356938035643809,356938035643817}')$$, tests.id('item')), 'valid IMEIs saved');
select is((select imeis from public.order_items where id = tests.id('item')), '{356938035643809,356938035643817}', 'IMEIs stored');
select throws_ok($$select public.admin_set_imeis(gen_random_uuid(), '{}')$$, 'P0001', 'NOT_FOUND', 'unknown order item');

-- admin_dashboard -------------------------------------------------------------

reset role;
insert into public.repair_bookings (user_id, device_brand, device_model, issue, preferred_date, slot, contact_phone, status) values
  ('11111111-1111-1111-1111-111111111111', 'Apple', 'iPhone 12', 'screen', current_date, 'morning', '+919876543210', 'in_progress'),
  ('11111111-1111-1111-1111-111111111111', 'Apple', 'iPhone 11', 'battery', current_date, 'morning', '+919876543210', 'completed');
select tests.login('staff');
-- orders: rzp cancelled, cod refunded, big cancelled, two confirmed (100000); low stock: T-CHEAP 1, T-EMPTY 0 (one product)
select is(public.admin_dashboard()::jsonb,
  '{"orders_today": 1, "revenue_today_paise": 100000, "open_orders": 1, "low_stock": 1, "open_repairs": 1, "needs_refund": 0, "repairs_awaiting_approval": 0}'::jsonb,
  'dashboard numbers');
select tests.login('anon');
select throws_ok('select public.admin_dashboard()', '42501', null, 'anon cannot call admin_dashboard');

-- cancel_repair -------------------------------------------------------------

reset role;
insert into public.repair_bookings (id, user_id, device_brand, device_model, issue, preferred_date, slot, contact_phone) values
  ('90000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Apple', 'iPhone 13', 'screen', current_date, 'morning', '+919876543210');
select tests.login('bob');
select throws_ok($$select public.cancel_repair('90000000-0000-0000-0000-000000000001')$$, 'P0001', 'NOT_FOUND', 'bob cannot cancel alice''s repair');
select tests.login('alice');
select lives_ok($$select public.cancel_repair('90000000-0000-0000-0000-000000000001')$$, 'alice cancels her repair');
select is((select status::text from public.repair_bookings where id = '90000000-0000-0000-0000-000000000001'), 'cancelled', 'repair cancelled');
select throws_ok($$select public.cancel_repair(id) from public.repair_bookings where status = 'in_progress'$$, 'P0001', 'INVALID_TRANSITION', 'in-progress repairs cannot be cancelled');
select tests.login('staff');
select throws_ok($$update public.repair_bookings set status = 'confirmed' where id = '90000000-0000-0000-0000-000000000001'$$, '42501', null,
  'staff cannot update repairs directly (admin_update_repair, repair_flow.test.sql)');

select * from finish();
rollback;
