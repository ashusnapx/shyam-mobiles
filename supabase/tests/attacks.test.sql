-- Regressions for holes found by scripts/api_e2e.py (attack suite): checkout race, repair mass assignment,
-- IMEI array shape, and the passwordless access token hook.
begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

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
  ('d0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'T-CASE', 'Case', 100, 100, 5);
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
