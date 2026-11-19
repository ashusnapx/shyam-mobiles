-- Made-to-order accessories: no stock check or decrement, a phone model per line, no restock, models learned.
begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

insert into auth.users (id, email) values ('c7000000-0000-0000-0000-000000000001', 'mto@test.dev');
insert into public.addresses (user_id, name, phone, line1, city, state, pincode)
values ('c7000000-0000-0000-0000-000000000001', 'Ravi Kumar', '+919811122233', 'Main Road', 'Waidhan', 'Madhya Pradesh', '486886');
insert into public.categories (id, slug, name, kind) values
  ('c70000c0-0000-0000-0000-000000000001', 'mto-phones', 'MTO phones', 'phone'),
  ('c70000c0-0000-0000-0000-000000000002', 'mto-covers', 'MTO covers', 'accessory');
insert into public.brands (id, slug, name) values ('c70000b0-0000-0000-0000-000000000001', 'mto-brand', 'Mtobrand');
insert into public.products (id, slug, name, brand_id, category_id) values
  ('c70000a0-0000-0000-0000-000000000001', 'mto-phone', 'Mtobrand Zeta 7', 'c70000b0-0000-0000-0000-000000000001', 'c70000c0-0000-0000-0000-000000000001'),
  ('c70000a0-0000-0000-0000-000000000002', 'mto-cover', 'Mto back cover', 'c70000b0-0000-0000-0000-000000000001', 'c70000c0-0000-0000-0000-000000000002'),
  ('c70000a0-0000-0000-0000-000000000004', 'mto-mixed', 'Mto mixed cover', 'c70000b0-0000-0000-0000-000000000001', 'c70000c0-0000-0000-0000-000000000002'),
  ('c70000a0-0000-0000-0000-000000000003', 'mto-odd', 'Odd <b>phone</b>', 'c70000b0-0000-0000-0000-000000000001', 'c70000c0-0000-0000-0000-000000000001');
insert into public.variants (id, product_id, sku, name, price_paise, mrp_paise, stock, made_to_order, lead_days) values
  ('c70000d0-0000-0000-0000-000000000001', 'c70000a0-0000-0000-0000-000000000001', 'MTO-T-PHONE', 'Black', 900000, 900000, 5, false, 2),
  ('c70000d0-0000-0000-0000-000000000002', 'c70000a0-0000-0000-0000-000000000002', 'MTO-T-COVER', 'For your phone', 19900, 19900, 0, true, 3),
  ('c70000d0-0000-0000-0000-000000000005', 'c70000a0-0000-0000-0000-000000000004', 'MIX-T-1', 'Stocked', 29900, 29900, 4, false, 2),
  ('c70000d0-0000-0000-0000-000000000006', 'c70000a0-0000-0000-0000-000000000004', 'MIX-T-2', 'Any phone', 19900, 19900, 0, true, 3);
update public.promotions set is_active = false; -- prices only, no offers in the way

select is((select count(*)::int from public.product_cards where id = 'c70000a0-0000-0000-0000-000000000002'), 0,
  'an all-made-to-order product is not a shop card');
select is((select in_stock::text || ' ' || made_to_order::text || ' ' || lead_days::text from public.product_cards
  where id = 'c70000a0-0000-0000-0000-000000000004'), 'true true 3', 'a mixed product stays listed');
select is((select made_to_order::text || ' ' || coalesce(lead_days::text, '-') from public.product_cards
  where id = 'c70000a0-0000-0000-0000-000000000001'), 'false -', 'a stocked card is not made to order');

select set_config('request.jwt.claims', '{"sub":"c7000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select throws_ok($$ insert into public.cart_items (user_id, variant_id, qty, for_model)
  values (auth.uid(), 'c70000d0-0000-0000-0000-000000000002', 1, 'x') $$, '23514', null, 'a one-letter model is refused');
select throws_ok($$ insert into public.cart_items (user_id, variant_id, qty, for_model)
  values (auth.uid(), 'c70000d0-0000-0000-0000-000000000002', 1, 'Galaxy  A15') $$, '23514', null, 'an untidy model is refused');
select throws_ok($$ insert into public.cart_items (user_id, variant_id, qty, for_model)
  values (auth.uid(), 'c70000d0-0000-0000-0000-000000000002', 1, '<b>A15</b>') $$, '23514', null, 'markup is refused');

insert into public.cart_items (user_id, variant_id, qty, for_model) values
  (auth.uid(), 'c70000d0-0000-0000-0000-000000000001', 1, 'Ignored 1'),
  (auth.uid(), 'c70000d0-0000-0000-0000-000000000002', 2, null);
select throws_ok($$ select public.quote_order() $$, 'P0001', 'MODEL_REQUIRED', 'quote asks for the phone model first');
select throws_ok($$ select public.place_order((select id from public.addresses where user_id = auth.uid()), 'cod') $$,
  'P0001', 'MODEL_REQUIRED', 'so does checkout');

update public.cart_items set for_model = 'Galaxy A15 5G' where variant_id = 'c70000d0-0000-0000-0000-000000000002';
select is(public.quote_order()::jsonb ->> 'subtotal_paise', '939800', 'priced as usual');
select lives_ok($$ select set_config('t.order', public.place_order(
  (select id from public.addresses where user_id = auth.uid()), 'cod')::text, true) $$,
  'checkout goes through with zero stock on the made-to-order line');
select is((select string_agg(coalesce(for_model, '-'), ',' order by unit_price_paise) from public.order_items
  where order_id = current_setting('t.order')::uuid), 'Galaxy A15 5G,-', 'the model rides on the made-to-order line only');
select is((select string_agg(stock::text, ',' order by sku) from public.variants where sku like 'MTO-T-%'),
  '0,4', 'only the stocked line is decremented');
select ok(not public.phone_models()::jsonb ? 'Galaxy A15 5G', 'a model typed on an undelivered order is not suggested');
select ok(public.phone_models()::jsonb ? 'Mtobrand Zeta 7', 'catalog phone names are suggestions');
select ok(not public.phone_models()::jsonb ? 'Odd <b>phone</b>', 'a name with markup is not suggested');

set local role authenticated;
select lives_ok($$ select public.cancel_order(current_setting('t.order')::uuid) $$, 'customer cancels');
select is((select string_agg(stock::text, ',' order by sku) from public.variants where sku like 'MTO-T-%'),
  '0,5', 'cancel restocks the phone, never the made-to-order line');

reset role;
update public.orders set status = 'delivered' where id = current_setting('t.order')::uuid;
select ok(public.phone_models()::jsonb ? 'Galaxy A15 5G', 'a model on a delivered order becomes a suggestion');

select * from finish();
rollback;
