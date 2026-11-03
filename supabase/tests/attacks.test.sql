-- Regressions for holes found by scripts/api_e2e.py (attack suite): checkout race, repair mass assignment,
-- IMEI array shape, the passwordless access token hook, and the abuse caps (pending orders, lines, repairs, size).
begin;
create extension if not exists pgtap with schema extensions;
select plan(52);

create schema tests;
grant usage on schema tests to anon, authenticated, service_role;
create function tests.login(p_who text) returns void language plpgsql as $$
declare
  v_uid uuid := case p_who
    when 'alice' then '11111111-1111-1111-1111-111111111111'
    when 'staff' then '33333333-3333-3333-3333-333333333333' end;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
create function tests.id(p_name text) returns uuid language sql as $$ select current_setting('tests.' || p_name)::uuid $$;
create function tests.keep(p_name text, p_id uuid) returns uuid language sql as $$ select set_config('tests.' || p_name, p_id::text, true)::uuid $$;
grant execute on all functions in schema tests to anon, authenticated, service_role;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.dev'),
  ('33333333-3333-3333-3333-333333333333', 'staff@test.dev');
insert into public.admins (user_id) values ('33333333-3333-3333-3333-333333333333');
insert into public.categories (id, slug, name, kind) values ('c0000000-0000-0000-0000-000000000001', 'test-cat', 'Test cat', 'phone');
insert into public.brands (id, slug, name) values ('b0000000-0000-0000-0000-000000000001', 'test-brand', 'Test');
insert into public.products (id, slug, name, brand_id, category_id) values
  ('a0000000-0000-0000-0000-000000000001', 'test-phone', 'Test Phone', 'b0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001');
insert into public.variants (id, product_id, sku, name, price_paise, mrp_paise, stock) values
  ('d0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'T-PHONE', 'Phone', 50000, 50000, 5),
  ('d0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'T-CASE', 'Case', 100, 100, 5),
  -- with delivery 4900: total = int max, and int max + 1
  ('d0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'T-MAX', 'Max', 2147478747, 2147478747, 5),
  ('d0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'T-MAX1', 'Max+1', 2147478748, 2147478748, 5);
insert into public.variants (product_id, sku, name, price_paise, mrp_paise, stock)
select 'a0000000-0000-0000-0000-000000000001', format('T-L%s', lpad(n::text, 2, '0')), format('Line %s', n), 100, 100, 10
from generate_series(1, 21) n;
create function tests.cart(p_skus text[], p_qty int default 1) returns void language sql as $$
  delete from public.cart_items where user_id = auth.uid();
  insert into public.cart_items (user_id, variant_id, qty) select auth.uid(), id, p_qty from public.variants where sku = any(p_skus);
$$;
grant execute on function tests.cart(text[], int) to authenticated;
insert into public.addresses (id, user_id, name, phone, line1, city, state, pincode) values
  ('e0000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Alice', '+919876543210', '1 MG Road', 'Patna', 'Bihar', '800001');

-- place_order: a cart line added while checkout runs ------------------------------------------------

-- stands in for a parallel add-to-cart that commits between place_order's subtotal and its order lines
create function tests.add_line_mid_checkout() returns trigger language plpgsql as $$
begin
  insert into public.cart_items (user_id, variant_id, qty) values (new.user_id, 'd0000000-0000-0000-0000-000000000002', 1);
  return new;
end $$;
create trigger add_line_mid_checkout after insert on public.orders for each row execute function tests.add_line_mid_checkout();

select tests.login('alice');
insert into public.cart_items (user_id, variant_id, qty) values ('11111111-1111-1111-1111-111111111111', 'd0000000-0000-0000-0000-000000000001', 2);
select tests.keep('o', public.place_order('e0000000-0000-0000-0000-000000000001', 'razorpay'));
reset role;
drop trigger add_line_mid_checkout on public.orders;

select is((select array_agg(variant_id) from public.order_items where order_id = tests.id('o')),
  array['d0000000-0000-0000-0000-000000000001'::uuid], 'a line added mid-checkout is not in the order');
select is((select subtotal_paise from public.orders where id = tests.id('o')),
  (select sum(unit_price_paise * qty)::int from public.order_items where order_id = tests.id('o')), 'subtotal = the order''s own lines');
select is((select qty from public.cart_items where variant_id = 'd0000000-0000-0000-0000-000000000002'), 1, 'the late line stays in the cart');
select is((select stock from public.variants where sku = 'T-CASE'), 5, 'and its stock is untouched');
select is((select stock from public.variants where sku = 'T-PHONE'), 3, 'the priced line took its stock');

-- repair_bookings: customers can't choose id, number or timestamps -------------------------------------

select tests.login('alice');
select throws_ok($$insert into public.repair_bookings (user_id, number, device_brand, device_model, issue, preferred_date, slot, contact_phone)
  values ('11111111-1111-1111-1111-111111111111', 'RP100099', 'Vivo', 'Y20', 'screen', (now() at time zone 'Asia/Kolkata')::date, 'morning', '+919876543210')$$,
  '42501', null, 'customers cannot pick a repair number (would collide with the sequence later)');
select throws_ok($$insert into public.repair_bookings (user_id, created_at, device_brand, device_model, issue, preferred_date, slot, contact_phone)
  values ('11111111-1111-1111-1111-111111111111', '2000-01-01', 'Vivo', 'Y20', 'screen', (now() at time zone 'Asia/Kolkata')::date, 'morning', '+919876543210')$$,
  '42501', null, 'customers cannot backdate a booking');
select throws_ok($$insert into public.repair_bookings (id, user_id, device_brand, device_model, issue, preferred_date, slot, contact_phone)
  values (gen_random_uuid(), '11111111-1111-1111-1111-111111111111', 'Vivo', 'Y20', 'screen', (now() at time zone 'Asia/Kolkata')::date, 'morning', '+919876543210')$$,
  '42501', null, 'customers cannot choose the booking id');
select lives_ok($$insert into public.repair_bookings (user_id, device_brand, device_model, issue, description, preferred_date, slot, contact_phone)
  values ('11111111-1111-1111-1111-111111111111', 'Vivo', 'Y20', 'screen', 'cracked', (now() at time zone 'Asia/Kolkata')::date, 'morning', '+919876543210')$$,
  'the app''s booking insert still works');
select tests.login('staff');
select lives_ok($$insert into public.repair_bookings (user_id, device_brand, device_model, issue, preferred_date, slot, contact_phone, status, quote_paise, admin_note)
  values (null, 'Oppo', 'A5', 'battery', '2026-01-01', 'evening', '+919876543210', 'confirmed', 150000, 'walk-in')$$,
  'staff still book with status, quote and note');

-- admin_set_imeis: one-dimensional only -------------------------------------------------------------

select throws_ok(format($$select public.admin_set_imeis(%L, '{{356938035643809,356938035643817}}')$$,
  (select id from public.order_items where order_id = tests.id('o'))), 'P0001', 'INVALID_IMEIS', '2-D IMEI arrays refused');
reset role;

-- place_order: ORDER_TOO_LARGE instead of an int overflow --------------------------------------------

update public.store_settings set delivery_fee_paise = 4900, free_delivery_min_paise = 2147483647, cod_enabled = true;
select tests.login('alice');
select tests.cart('{T-MAX1}');
select throws_ok($$select public.place_order('e0000000-0000-0000-0000-000000000001', 'razorpay')$$, 'P0001', 'ORDER_TOO_LARGE', 'total of int max + 1 refused');
select tests.cart('{T-MAX}', 2);
select throws_ok($$select public.place_order('e0000000-0000-0000-0000-000000000001', 'razorpay')$$, 'P0001', 'ORDER_TOO_LARGE', 'a subtotal past int range refused (no raw overflow)');
select tests.cart('{T-MAX}');
select lives_ok($$select tests.keep('max', public.place_order('e0000000-0000-0000-0000-000000000001', 'razorpay'))$$, 'total of exactly int max places');
select is((select total_paise from public.orders where id = tests.id('max')), 2147483647, '... with the exact total');
reset role;
update public.store_settings set free_delivery_min_paise = 99900;

-- place_order: at most 2 unexpired unpaid online orders per customer --------------------------------

select tests.login('alice'); -- holds 'o' and 'max', both pending_payment
select tests.cart('{T-L01}');
select throws_ok($$select public.place_order('e0000000-0000-0000-0000-000000000001', 'razorpay')$$, 'P0001', 'PENDING_LIMIT', 'a third unpaid online order refused');
select lives_ok($$select public.place_order('e0000000-0000-0000-0000-000000000001', 'cod')$$, 'COD is not capped');
reset role;
update public.orders set reserved_until = now() - interval '1 second' where id = tests.id('o');
select tests.login('alice');
select tests.cart('{T-L01}');
select lives_ok($$select public.place_order('e0000000-0000-0000-0000-000000000001', 'razorpay')$$, 'an expired hold no longer counts');

-- place_order: at most 10 lines; cart: at most 20 ---------------------------------------------------

select tests.cart(array(select format('T-L%s', lpad(n::text, 2, '0')) from generate_series(1, 11) n));
select throws_ok($$select public.place_order('e0000000-0000-0000-0000-000000000001', 'cod')$$, 'P0001', 'CART_LIMIT', 'an 11-line order refused');
select tests.cart(array(select format('T-L%s', lpad(n::text, 2, '0')) from generate_series(1, 10) n));
select lives_ok($$select public.place_order('e0000000-0000-0000-0000-000000000001', 'cod')$$, '10 lines place');
select tests.cart(array(select format('T-L%s', lpad(n::text, 2, '0')) from generate_series(1, 20) n));
select throws_ok($$insert into public.cart_items (user_id, variant_id, qty)
  select '11111111-1111-1111-1111-111111111111', id, 1 from public.variants where sku = 'T-L21'$$, 'P0001', 'CART_LIMIT', 'a 21st cart line refused');
select lives_ok($$insert into public.cart_items (user_id, variant_id, qty)
  select '11111111-1111-1111-1111-111111111111', id, 2 from public.variants where sku = 'T-L01'
  on conflict (user_id, variant_id) do update set qty = excluded.qty$$, 'upserting an existing line at the cap still works');

-- repairs: at most 3 open per customer; staff exempt -------------------------------------------------

insert into public.repair_bookings (user_id, device_brand, device_model, issue, preferred_date, slot, contact_phone)
select '11111111-1111-1111-1111-111111111111', 'Vivo', 'Y' || n, 'screen', (now() at time zone 'Asia/Kolkata')::date, 'morning', '+919876543210'
from generate_series(1, 2) n; -- with the booking above: 3 open
select throws_ok($$insert into public.repair_bookings (user_id, device_brand, device_model, issue, preferred_date, slot, contact_phone)
  values ('11111111-1111-1111-1111-111111111111', 'Vivo', 'Y4', 'screen', (now() at time zone 'Asia/Kolkata')::date, 'morning', '+919876543210')$$,
  'P0001', 'REPAIR_LIMIT', 'a 4th open repair refused');
select public.cancel_repair((select id from public.repair_bookings where device_model = 'Y1'));
select lives_ok($$insert into public.repair_bookings (user_id, device_brand, device_model, issue, preferred_date, slot, contact_phone)
  values ('11111111-1111-1111-1111-111111111111', 'Vivo', 'Y4', 'screen', (now() at time zone 'Asia/Kolkata')::date, 'morning', '+919876543210')$$,
  'a cancelled booking frees a slot');
select tests.login('staff');
select lives_ok($$insert into public.repair_bookings (user_id, device_brand, device_model, issue, preferred_date, slot, contact_phone)
  values ('11111111-1111-1111-1111-111111111111', 'Vivo', 'Y5', 'screen', '2026-01-01', 'morning', '+919876543210')$$, 'staff book past the cap');
reset role;

-- input rules: enforced by the database, whatever the client sends ------------------------------------

select is(array[public.is_name('श्याम कुमार'), public.is_name('José Ñúñez'), public.is_name('Robert''); drop table public.orders; --')],
  array[true, true, true], 'names in any script, and SQL-ish text, are just text');
select is(array[public.is_name('😀😀'), public.is_name('...'), public.is_name('12345'), public.is_name('   '),
  public.is_name(E'Ali\u200bce'), public.is_name(E'Ali\u202eecila'), public.is_name(E'Ali\nce'), public.is_name(E'Ali\u0007ce'),
  public.is_name(E'\ufeffAlice')], array[false, false, false, false, false, false, false, false, false],
  'emoji-only, punctuation, digits, blank, zero-width, bidi, newline, control and BOM are not names');
select ok(public.is_clean_text(E'line one\nline two\ttab', true) and not public.is_clean_text(E'line one\nline two')
  and public.is_clean_text(E'क्\u200dष'), 'multi-line text keeps newlines; ZWJ (Hindi) is fine');

select tests.login('alice');
select throws_ok($$update public.profiles set full_name = '😀😀' where id = '11111111-1111-1111-1111-111111111111'$$, '23514', null, 'an emoji-only name is refused');
select throws_ok($$update public.profiles set full_name = repeat('a', 10000) where id = '11111111-1111-1111-1111-111111111111'$$, '23514', null, 'a 10,000-character name is refused');
select throws_ok($$update public.profiles set phone = '+91 98765 43210' where id = '11111111-1111-1111-1111-111111111111'$$, '23514', null, 'a phone with spaces is refused');
select throws_ok($$update public.profiles set phone = '+9198765432101' where id = '11111111-1111-1111-1111-111111111111'$$, '23514', null, 'an 11-digit phone is refused');
select throws_ok($$update public.addresses set pincode = '4868860' where id = 'e0000000-0000-0000-0000-000000000001'$$, '23514', null, 'a 7-digit pincode is refused');
select throws_ok($$update public.addresses set line1 = E'1 MG\u202e Road' where id = 'e0000000-0000-0000-0000-000000000001'$$, '23514', null, 'a bidi override in an address is refused');
select throws_ok($$update public.addresses set city = '🏙️🏙️' where id = 'e0000000-0000-0000-0000-000000000001'$$, '23514', null, 'an emoji-only city is refused');

select tests.login('staff');
select throws_ok($$update public.variants set sku = 'SАM-1' where sku = 'T-PHONE'$$, '23514', null, 'a Cyrillic look-alike in a SKU is refused');
select throws_ok($$update public.products set slug = 'tеst-phone' where id = 'a0000000-0000-0000-0000-000000000001'$$, '23514', null, 'a Cyrillic look-alike in a slug is refused');
select throws_ok($$update public.variants set attributes = '{"color_hex": "red"}' where sku = 'T-PHONE'$$, '23514', null, 'a colour must be #RRGGBB');
select throws_ok($$update public.variants set stock = 1000001 where sku = 'T-PHONE'$$, '23514', null, 'stock is capped at 1,000,000');
select throws_ok($$update public.store_settings set store_photos = '{../../etc/passwd.png}'$$, '23514', null, 'shop photo keys must be store/<millis>.<ext>');
select throws_ok($$insert into public.product_images (product_id, path) values ('a0000000-0000-0000-0000-000000000001', '../x.png')$$, '23514', null, 'image keys cannot climb out of their folder');
reset role;

select throws_ok(format($$update public.order_items set imeis = '{356938035643809,12}' where id = %L$$,
  (select id from public.order_items where order_id = tests.id('o'))), '23514', null, 'the table itself refuses malformed IMEIs');
insert into auth.users (id, email, raw_user_meta_data) values ('77777777-7777-7777-7777-777777777777', 'emoji@test.dev', '{"full_name": "😀😀"}');
select is((select full_name from public.profiles where id = '77777777-7777-7777-7777-777777777777'), null,
  'a junk display name never blocks sign-up (stored as null)');

-- access token hook: no password sessions ----------------------------------------------------------

insert into private.password_sign_in_domains (domain) values ('devlogin.test');
insert into auth.users (id, email, phone) values
  ('44444444-4444-4444-4444-444444444444', 'dev@devlogin.test', null),
  ('55555555-5555-5555-5555-555555555555', 'x@devlogin.test.evil.com', null),
  ('66666666-6666-6666-6666-666666666666', null, '919876543299');
create function tests.event(p_uid uuid, p_amr text, p_method text) returns jsonb language sql as $$
  select jsonb_build_object('user_id', p_uid, 'authentication_method', p_method,
    'claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated', 'amr', jsonb_build_array(jsonb_build_object('method', p_amr, 'timestamp', 1))))
$$;
create function tests.hook(p_uid uuid, p_amr text, p_method text) returns jsonb language sql as $$
  select private.custom_access_token_hook(tests.event(p_uid, p_amr, p_method))
$$;

select is(tests.hook('11111111-1111-1111-1111-111111111111', 'password', 'password') #>> '{error,http_code}', '403', 'password grant refused');
select is(tests.hook('11111111-1111-1111-1111-111111111111', 'password', 'token_refresh') #>> '{error,http_code}', '403', 'refreshing a password session refused');
select is(tests.hook('66666666-6666-6666-6666-666666666666', 'password', 'password') #>> '{error,http_code}', '403', 'phone + password refused');
select is(tests.hook('55555555-5555-5555-5555-555555555555', 'password', 'password') #>> '{error,http_code}', '403', 'a look-alike domain is not the dev domain');
select is(tests.hook('11111111-1111-1111-1111-111111111111', 'otp', 'otp'),
  tests.event('11111111-1111-1111-1111-111111111111', 'otp', 'otp'), 'OTP sign-in passes through unchanged');
select ok(tests.hook('44444444-4444-4444-4444-444444444444', 'password', 'password') ? 'claims', 'dev-domain accounts keep password sign-in');
select ok(not has_function_privilege('authenticated', 'private.custom_access_token_hook(jsonb)', 'execute')
  and not has_function_privilege('anon', 'private.custom_access_token_hook(jsonb)', 'execute'), 'clients cannot call the hook');
select ok(has_function_privilege('supabase_auth_admin', 'private.custom_access_token_hook(jsonb)', 'execute'), 'Auth can call the hook');
select ok(not has_schema_privilege('anon', 'private', 'usage') and not has_schema_privilege('authenticated', 'private', 'usage'),
  'API roles cannot reach the private schema (domain allowlist)');

select * from finish();
rollback;
