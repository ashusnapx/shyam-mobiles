-- A typed code never makes the order dearer than the running sale: the sale wins and the code stays unused.
begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

insert into auth.users (id, email) values ('be000000-0000-0000-0000-000000000001', 'best-offer@test.dev');
insert into public.addresses (user_id, name, phone, line1, city, state, pincode)
values ('be000000-0000-0000-0000-000000000001', 'Ravi Kumar', '+919811122233', 'Main Road', 'Waidhan', 'Madhya Pradesh', '486886');
insert into public.categories (id, slug, name, kind) values ('be0000c0-0000-0000-0000-000000000001', 'best-offer-phones', 'Best offer phones', 'phone');
insert into public.brands (id, slug, name) values ('be0000b0-0000-0000-0000-000000000001', 'best-offer-brand', 'Bestbrand');
insert into public.products (id, slug, name, brand_id, category_id) values
  ('be0000a0-0000-0000-0000-000000000001', 'best-offer-phone', 'Bestbrand Phone', 'be0000b0-0000-0000-0000-000000000001', 'be0000c0-0000-0000-0000-000000000001'),
  ('be0000a0-0000-0000-0000-000000000002', 'best-offer-cable', 'Bestbrand Cable', 'be0000b0-0000-0000-0000-000000000001', 'be0000c0-0000-0000-0000-000000000001');
insert into public.variants (id, product_id, sku, name, price_paise, mrp_paise, stock) values
  ('be0000d0-0000-0000-0000-000000000001', 'be0000a0-0000-0000-0000-000000000001', 'BEST-PHONE', 'Black', 5000000, 5000000, 5),
  ('be0000d0-0000-0000-0000-000000000002', 'be0000a0-0000-0000-0000-000000000002', 'BEST-CABLE', 'White', 150000, 150000, 5);
-- every other sale stays out of the way of this test
update public.promotions set is_active = false where code is null;
insert into public.promotions (id, title, kind, value, max_discount_paise, applies_to) values
  ('be0000e0-0000-0000-0000-000000000001', 'Best phone sale', 'percent', 5, 200000, 'items');
insert into public.promotion_targets (promotion_id, target_type, target_id)
values ('be0000e0-0000-0000-0000-000000000001', 'product', 'be0000a0-0000-0000-0000-000000000001');
insert into public.promotions (id, title, code, kind, value) values
  ('be0000e0-0000-0000-0000-000000000002', 'Rs 100 off', 'BESTCODE100', 'flat', 10000);

select set_config('request.jwt.claims', '{"sub":"be000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
set local role authenticated;
insert into public.cart_items (user_id, variant_id, qty) values (auth.uid(), 'be0000d0-0000-0000-0000-000000000001', 1);

select is(public.quote_order()::jsonb ->> 'discount_paise', '200000', 'no code: the sale takes Rs 2,000 off');
select is(public.quote_order('BESTCODE100')::jsonb ->> 'discount_paise', '200000', 'a weaker code still gets the sale price');
select is(public.quote_order('BESTCODE100')::jsonb #>> '{promotion,title}', 'Best phone sale', '... through the sale');
select is(public.quote_order('BESTCODE100')::jsonb ->> 'coupon_error', 'COUPON_BETTER_OFFER', 'and the quote says why');

select lives_ok($$ select set_config('t.order', public.place_order(
  (select id from public.addresses where user_id = auth.uid()), 'razorpay', 'BESTCODE100')::text, true) $$,
  'checkout with the weaker code goes through');
select is((select discount_paise || ' ' || coalesce(coupon_code, '-') from public.orders where id = current_setting('t.order')::uuid),
  '200000 -', 'the order gets the sale, not the code');
select is((select count(*)::int from public.promotion_redemptions where promotion_id = 'be0000e0-0000-0000-0000-000000000002'),
  0, 'the code is still unused');

-- on a cart the sale doesn't cover, the code is the better offer again
insert into public.cart_items (user_id, variant_id, qty) values (auth.uid(), 'be0000d0-0000-0000-0000-000000000002', 1);
select is(public.quote_order('BESTCODE100')::jsonb ->> 'discount_paise', '10000', 'without the sale, the code applies');
select is(public.quote_order('BESTCODE100')::jsonb ->> 'coupon_error', null, 'with no complaint');

select * from finish();
rollback;
