-- Phone packs: a phone + fitting accessories of every required type gets the pack's percent off (the accessories
-- only, or the whole pack), competing with the other automatic sales; the owner saves packs through admin_save_pack.
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

insert into auth.users (id, email) values
  ('ca000000-0000-0000-0000-000000000001', 'pack@test.dev'), ('ca000000-0000-0000-0000-000000000002', 'pack-admin@test.dev');
insert into public.admins (user_id) values ('ca000000-0000-0000-0000-000000000002');
insert into public.addresses (user_id, name, phone, line1, city, state, pincode)
values ('ca000000-0000-0000-0000-000000000001', 'Ravi Kumar', '+919811122233', 'Main Road', 'Waidhan', 'Madhya Pradesh', '486886');
insert into public.categories (id, slug, name, kind) values
  ('ca0000c0-0000-0000-0000-000000000001', 'pack-phones', 'Pack phones', 'phone'),
  ('ca0000c0-0000-0000-0000-000000000002', 'pack-bits', 'Pack bits', 'accessory');
insert into public.brands (id, slug, name) values ('ca0000b0-0000-0000-0000-000000000001', 'packbrand', 'Packbrand');
insert into public.products (id, slug, name, brand_id, category_id, specs) values
  ('ca0000a0-0000-0000-0000-000000000001', 'pack-phone', 'Packbrand Nova 5', 'ca0000b0-0000-0000-0000-000000000001', 'ca0000c0-0000-0000-0000-000000000001', '[]'),
  ('ca0000a0-0000-0000-0000-000000000002', 'pack-glass', 'Clear tempered glass', 'ca0000b0-0000-0000-0000-000000000001', 'ca0000c0-0000-0000-0000-000000000002',
   '[{"label":"Fits","value":"Nova 5"}]'),
  ('ca0000a0-0000-0000-0000-000000000003', 'pack-cover', 'Any back cover', 'ca0000b0-0000-0000-0000-000000000001', 'ca0000c0-0000-0000-0000-000000000002', '[]'),
  ('ca0000a0-0000-0000-0000-000000000004', 'pack-other-glass', 'Other tempered glass', 'ca0000b0-0000-0000-0000-000000000001', 'ca0000c0-0000-0000-0000-000000000002',
   '[{"label":"Fits","value":"Some Other 9"}]');
insert into public.variants (id, product_id, sku, name, price_paise, mrp_paise, stock, made_to_order) values
  ('ca0000d0-0000-0000-0000-000000000001', 'ca0000a0-0000-0000-0000-000000000001', 'PACK-PHONE', 'Black', 1000000, 1000000, 5, false),
  ('ca0000d0-0000-0000-0000-000000000002', 'ca0000a0-0000-0000-0000-000000000002', 'PACK-GLASS', 'Clear', 30000, 30000, 5, false),
  ('ca0000d0-0000-0000-0000-000000000003', 'ca0000a0-0000-0000-0000-000000000003', 'PACK-COVER', 'For your phone', 19900, 19900, 0, true),
  ('ca0000d0-0000-0000-0000-000000000004', 'ca0000a0-0000-0000-0000-000000000004', 'PACK-GLASS-2', 'Clear', 25000, 25000, 5, false);
update public.promotions set is_active = false where code is null; -- only the pack competes

-- the owner saves the pack
select set_config('request.jwt.claims', '{"sub":"ca000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
set local role authenticated;
select throws_ok($$ select public.admin_save_pack(json_build_object('title', 'Phone pack', 'kind', 'pack', 'value', 10,
  'applies_to', 'items', 'pack_types', json_build_array(),
  'targets', json_build_array(json_build_object('target_type', 'category', 'target_id', 'ca0000c0-0000-0000-0000-000000000001')))) $$,
  'P0001', 'INVALID_PROMOTION', 'a pack needs at least one accessory type');
select throws_ok($$ select public.admin_save_pack(json_build_object('title', 'Phone pack', 'kind', 'pack', 'value', 10,
  'applies_to', 'items', 'pack_types', json_build_array('case'),
  'targets', json_build_array(json_build_object('target_type', 'category', 'target_id', 'ca0000c0-0000-0000-0000-000000000002')))) $$,
  'P0001', 'INVALID_PROMOTION', 'and phone categories as targets');
select throws_ok($$ select public.admin_save_pack(json_build_object('title', 'Phone pack', 'kind', 'pack', 'value', 60,
  'applies_to', 'items', 'pack_types', json_build_array('case'),
  'targets', json_build_array(json_build_object('target_type', 'category', 'target_id', 'ca0000c0-0000-0000-0000-000000000001')))) $$,
  'P0001', 'INVALID_PROMOTION', 'at most 50% off');
select lives_ok($$ select set_config('t.pack', public.admin_save_pack(json_build_object('title', 'Phone pack', 'kind', 'pack',
  'value', 10, 'applies_to', 'items', 'per_user_limit', null, 'pack_types', json_build_array('glass', 'case', 'case'),
  'targets', json_build_array(json_build_object('target_type', 'category', 'target_id', 'ca0000c0-0000-0000-0000-000000000001'))))::text, true) $$,
  'a valid pack saves');
select is((select pack_types::text from public.promotions where id = current_setting('t.pack')::uuid), '{case,glass}',
  'types kept once each');

-- the customer
select set_config('request.jwt.claims', '{"sub":"ca000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select is((public.pack_offers()::jsonb -> 0 ->> 'categories'), '["ca0000c0-0000-0000-0000-000000000001"]', 'the app sees the pack');
insert into public.cart_items (user_id, variant_id, qty, for_model) values
  (auth.uid(), 'ca0000d0-0000-0000-0000-000000000001', 1, null),
  (auth.uid(), 'ca0000d0-0000-0000-0000-000000000002', 1, null),
  (auth.uid(), 'ca0000d0-0000-0000-0000-000000000004', 1, null);
select is(public.quote_order()::jsonb ->> 'discount_paise', '0', 'no case yet: no pack (a glass for another phone doesn''t count either)');

insert into public.cart_items (user_id, variant_id, qty, for_model) values (auth.uid(), 'ca0000d0-0000-0000-0000-000000000003', 1, 'nova 5');
select is(public.quote_order()::jsonb ->> 'discount_paise', '4990', 'a made-to-order cover for that phone completes it: 10% of the accessories');
select is(public.quote_order()::jsonb #>> '{promotion,kind}', 'pack', 'the quote names the pack');

reset role;
update public.promotions set pack_whole = true where id = current_setting('t.pack')::uuid;
set local role authenticated;
select is(public.quote_order()::jsonb ->> 'discount_paise', '104990', 'whole pack: the phone too');
reset role;
update public.promotions set pack_whole = false where id = current_setting('t.pack')::uuid;
insert into public.promotions (id, title, kind, value) values ('ca0000e0-0000-0000-0000-000000000001', 'Big flat sale', 'flat', 500000);
set local role authenticated;
select is(public.quote_order()::jsonb #>> '{promotion,title}', 'Big flat sale', 'a bigger sale wins; never both');
reset role;
update public.promotions set is_active = false where id = 'ca0000e0-0000-0000-0000-000000000001';
delete from public.cart_items where variant_id = 'ca0000d0-0000-0000-0000-000000000004';
set local role authenticated;

select lives_ok($$ select set_config('t.order', public.place_order(
  (select id from public.addresses where user_id = auth.uid()), 'razorpay')::text, true) $$, 'checkout with the pack');
select is((select discount_paise from public.orders where id = current_setting('t.order')::uuid), 4990, 'charged as quoted');
select is((select string_agg(discount_paise::text, ',' order by unit_price_paise desc) from public.order_items
  where order_id = current_setting('t.order')::uuid), '0,3000,1990', 'split over the accessories only, remainder to the largest');

select * from finish();
rollback;
