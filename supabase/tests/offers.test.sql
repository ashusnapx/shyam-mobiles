-- Offers: pricing (quote_order / place_order), coupon rules and attacks, automatic sales, listings, banners,
-- referrals, admin RPCs and RLS.
begin;
create extension if not exists pgtap with schema extensions;
select plan(153);

create schema tests;
grant usage on schema tests to anon, authenticated, service_role;
create function tests.login(p_who text) returns void language plpgsql as $$
declare
  v_uid uuid := case p_who
    when 'alice' then '11111111-1111-1111-1111-111111111111'
    when 'bob' then '22222222-2222-2222-2222-222222222222'
    when 'staff' then '33333333-3333-3333-3333-333333333333'
    when 'carol' then '44444444-4444-4444-4444-444444444444'
    when 'dave' then '55555555-5555-5555-5555-555555555555'
    when 'erin' then '66666666-6666-6666-6666-666666666666' end;
  v_role text := case p_who when 'anon' then 'anon' else 'authenticated' end;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', v_role)::text, true);
  perform set_config('role', v_role, true);
end $$;
create function tests.id(p_name text) returns uuid language sql as $$ select current_setting('tests.' || p_name)::uuid $$;
create function tests.keep(p_name text, p_id uuid) returns uuid language sql as $$ select set_config('tests.' || p_name, p_id::text, true)::uuid $$;
create function tests.pid(n int) returns uuid language sql as $$ select format('f1000000-0000-0000-0000-%s', lpad(n::text, 12, '0'))::uuid $$;
-- '1 2x2' = variant 1 once and variant 2 twice, replacing the caller's cart
create function tests.cart(p_lines text) returns void language sql as $$
  delete from public.cart_items where user_id = auth.uid();
  insert into public.cart_items (user_id, variant_id, qty)
  select auth.uid(), ('d0000000-0000-0000-0000-00000000000' || split_part(l, 'x', 1))::uuid, coalesce(nullif(split_part(l, 'x', 2), '')::int, 1)
  from unnest(string_to_array(p_lines, ' ')) l;
$$;
-- quote_order as 'subtotal/fee/discount/total/code or title or -/coupon_error or -'
create function tests.q(p_code text default null, p_method public.payment_method default null) returns text language sql as $$
  select concat_ws('/', j ->> 'subtotal_paise', j ->> 'delivery_fee_paise', j ->> 'discount_paise', j ->> 'total_paise',
    coalesce(j #>> '{promotion,code}', j #>> '{promotion,title}', '-'), coalesce(j ->> 'coupon_error', '-'))
  from (select public.quote_order(p_code, p_method)::jsonb j) x
$$;
create function tests.place(p_method public.payment_method, p_code text default null) returns uuid language sql as $$
  select public.place_order((select id from public.addresses where user_id = auth.uid()), p_method, p_code)
$$;
-- 'message|detail' of the error p_sql raises
create function tests.err(p_sql text) returns text language plpgsql as $$
declare
  v_msg text;
  v_detail text;
begin
  execute p_sql;
  return 'no error';
exception when others then
  get stacked diagnostics v_msg = message_text, v_detail = pg_exception_detail;
  return v_msg || '|' || coalesce(v_detail, '');
end $$;
create function tests.deliver(p_order uuid) returns void language plpgsql as $$
begin
  perform tests.login('staff');
  perform public.admin_update_order(p_order, 'packed');
  perform public.admin_update_order(p_order, 'shipped');
  perform public.admin_update_order(p_order, 'delivered');
end $$;
create function tests.codes(p_offers json) returns text[] language sql as $$
  select coalesce(array_agg(o ->> 'code' order by o ->> 'code') filter (where o ->> 'code' is not null), '{}') from json_array_elements(p_offers) o
$$;
grant execute on all functions in schema tests to anon, authenticated, service_role;

-- Fixtures ------------------------------------------------------------------

delete from public.orders;
delete from public.promotions;
delete from public.banners;
delete from public.referrals;
delete from public.referral_codes;
delete from public.coupon_attempts;
update public.store_settings set delivery_fee_paise = 4900, free_delivery_min_paise = 99900, cod_enabled = true,
  cod_max_paise = 2500000, referral_enabled = true, referral_friend_paise = 20000, referral_reward_paise = 20000,
  referral_min_order_paise = 199900, referral_monthly_cap = 10;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.dev'),
  ('33333333-3333-3333-3333-333333333333', 'staff@test.dev'),
  ('44444444-4444-4444-4444-444444444444', 'carol@test.dev'),
  ('55555555-5555-5555-5555-555555555555', 'dave@test.dev'),
  ('66666666-6666-6666-6666-666666666666', 'erin@test.dev');
insert into public.admins (user_id) values ('33333333-3333-3333-3333-333333333333');
insert into public.addresses (user_id, name, phone, line1, city, state, pincode)
select id, initcap(split_part(email, '@', 1)), '+919876543210', '1 Rajeev Complex', 'Waidhan', 'Madhya Pradesh', '486886'
from auth.users where email like '%@test.dev';

insert into public.categories (id, slug, name, kind) values
  ('c0000000-0000-0000-0000-000000000001', 'test-phones', 'Test phones', 'phone'),
  ('c0000000-0000-0000-0000-000000000002', 'test-acc', 'Test accessories', 'accessory');
insert into public.brands (id, slug, name) values
  ('b0000000-0000-0000-0000-000000000001', 'test-b1', 'B1'),
  ('b0000000-0000-0000-0000-000000000002', 'test-b2', 'B2');
insert into public.products (id, slug, name, brand_id, category_id) values
  ('a0000000-0000-0000-0000-000000000001', 'test-phone', 'Test Phone', 'b0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001'),
  ('a0000000-0000-0000-0000-000000000002', 'test-case', 'Test Case', 'b0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000002'),
  ('a0000000-0000-0000-0000-000000000003', 'test-charger', 'Test Charger', 'b0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002'),
  ('a0000000-0000-0000-0000-000000000004', 'test-cable', 'Test Cable', 'b0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000002');
insert into public.variants (id, product_id, sku, name, price_paise, mrp_paise, stock) values
  ('d0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'T-PHONE', 'Phone', 1000000, 1000000, 50),
  ('d0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000002', 'T-CASE', 'Case', 50000, 50000, 50),
  ('d0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000003', 'T-CHARGER', 'Charger', 30000, 30000, 50),
  ('d0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000004', 'T-CABLE', 'Cable', 100, 100, 50);
insert into public.collections (id, slug, name) values ('70000000-0000-0000-0000-000000000001', 'test-picks', 'Test picks');
insert into public.collection_products (collection_id, product_id) values
  ('70000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000003');

insert into public.promotions (id, title, code, kind, value, max_discount_paise, min_subtotal_paise, applies_to, starts_at,
  ends_at, usage_limit, per_user_limit, first_order_only, online_only, is_public, user_id, is_active)
select tests.pid(n), title, code, kind::public.promotion_kind, value, cap, min, scope::public.promotion_scope,
  now() + starts, now() + ends, usage, per_user, first, online, public, owner, active
from (values
  (1, 'Welcome', 'WELCOME', 'flat', 10000, null::int, 99900, 'order', interval '0', null::interval, null::int, 1, true, false, true, null::uuid, true),
  (2, 'Accessories', 'ACCX', 'percent', 20, 10000, 60000, 'items', '0', null, null, null, false, false, true, null, true),
  (3, 'Hidden', 'HIDDEN1', 'percent', 5, null, 0, 'order', '0', null, null, null, false, false, false, null, true),
  (4, 'Bob only', 'BOBONLY', 'flat', 5000, null, 0, 'order', '0', null, null, 1, false, false, false, '22222222-2222-2222-2222-222222222222', true),
  (5, 'Paused', 'PAUSED1', 'flat', 5000, null, 0, 'order', '0', null, null, null, false, false, true, null, false),
  (6, 'Soon', 'SOON1', 'flat', 5000, null, 0, 'order', '1 day', null, null, null, false, false, true, null, true),
  (7, 'Over', 'OLD1', 'flat', 5000, null, 0, 'order', '-2 days', '-1 day', null, null, false, false, true, null, true),
  (8, 'Product', 'PROD1', 'percent', 10, null, 0, 'items', '0', null, null, null, false, false, true, null, true),
  (9, 'Brand', 'BRAND1', 'percent', 10, null, 0, 'items', '0', null, null, null, false, false, true, null, true),
  (10, 'Group', 'GROUP1', 'percent', 10, null, 0, 'items', '0', null, null, null, false, false, true, null, true),
  (11, 'Ship free', 'SHIPFREE', 'free_delivery', 0, null, 0, 'order', '0', null, null, null, false, false, true, null, true),
  (12, 'Flat 500', 'FLAT500', 'flat', 50000, null, 0, 'order', '0', null, null, null, false, false, true, null, true),
  (13, 'Online', 'ONLINE1', 'flat', 5000, null, 0, 'order', '0', null, null, null, false, true, true, null, true),
  (14, 'Once', 'ONCE1', 'flat', 5000, null, 0, 'order', '0', null, 1, null, false, false, true, null, true),
  (15, 'Mine', 'MINE1', 'flat', 5000, null, 0, 'order', '0', null, null, 1, false, false, true, null, true),
  (16, 'Split', 'SPLIT1', 'flat', 1001, null, 0, 'order', '0', null, null, null, false, false, true, null, true),
  (17, 'One percent', 'PCT1', 'percent', 1, null, 0, 'order', '0', null, null, null, false, false, true, null, true),
  (18, 'Flat 100', 'FLAT100', 'flat', 10000, null, 0, 'order', '0', null, null, null, false, false, true, null, true)
) v(n, title, code, kind, value, cap, min, scope, starts, ends, usage, per_user, first, online, public, owner, active);
insert into public.promotion_targets (promotion_id, target_type, target_id) values
  (tests.pid(2), 'category', 'c0000000-0000-0000-0000-000000000002'),
  (tests.pid(8), 'product', 'a0000000-0000-0000-0000-000000000002'),
  (tests.pid(9), 'brand', 'b0000000-0000-0000-0000-000000000001'),
  (tests.pid(10), 'collection', '70000000-0000-0000-0000-000000000001');

-- Codes: validity ---------------------------------------------------------------

select tests.login('alice');
select throws_ok($$select public.quote_order()$$, 'P0001', 'CART_EMPTY', 'quote: empty cart');
select tests.cart('1');
select is(tests.q(), '1000000/0/0/1000000/-/-', 'quote without a code: plain totals');
select is(tests.q(' welCOME '), '1000000/0/10000/990000/WELCOME/-', 'a code is trimmed and uppercased; flat 100 off');
select is(tests.q('NOPE'), '1000000/0/0/1000000/-/COUPON_NOT_FOUND', 'unknown code');
select is(tests.q('BOBONLY'), '1000000/0/0/1000000/-/COUPON_NOT_FOUND', 'someone else''s personal coupon looks unknown');
select is(tests.q('PAUSED1'), '1000000/0/0/1000000/-/COUPON_NOT_FOUND', 'a paused coupon looks unknown');
select is(tests.q('SOON1'), '1000000/0/0/1000000/-/COUPON_NOT_STARTED', 'not started yet');
select is(tests.q('OLD1'), '1000000/0/0/1000000/-/COUPON_EXPIRED', 'ended');
select is(tests.q('HIDDEN1'), '1000000/0/50000/950000/HIDDEN1/-', 'a hidden code works when typed');
select is(tests.q('PROD1'), '1000000/0/0/1000000/-/COUPON_NOT_APPLICABLE', 'no eligible line');
select ok(public.quote_order('WELCOME')::jsonb #> '{promotion}' ?& array['id', 'title', 'code', 'kind'], 'quote promotion has id, title, code, kind');

-- Eligible lines, targets, cap ----------------------------------------------------

select tests.cart('1 2');
select is(tests.q('ACCX'), '1050000/0/0/1050000/-/COUPON_MIN_ORDER', 'min subtotal counts eligible lines only (₹500 of accessories < ₹600)');
select is(public.quote_order('ACCX') ->> 'coupon_error_detail', '60000', '... detail = the minimum in paise');
select tests.cart('1 2 3');
select is(tests.q('ACCX'), '1080000/0/10000/1070000/ACCX/-', 'category target; 20% of ₹800 = ₹160 capped at ₹100');
select is(tests.q('PROD1'), '1080000/0/5000/1075000/PROD1/-', 'product target: 10% of the case only');
select is(tests.q('BRAND1'), '1080000/0/103000/977000/BRAND1/-', 'brand target: phone + charger');
select is(tests.q('GROUP1'), '1080000/0/3000/1077000/GROUP1/-', 'collection target: the charger only');

-- Delivery, the ₹1 floor ------------------------------------------------------------

select tests.cart('2');
select is(tests.q(), '50000/4900/0/54900/-/-', 'below the free-delivery minimum: fee');
select is(tests.q('SHIPFREE'), '50000/0/0/50000/SHIPFREE/-', 'free delivery coupon waives the fee');
select is(tests.q('FLAT500'), '50000/4900/49900/5000/FLAT500/-', 'flat ₹500 on a ₹500 cart stops at ₹1 before delivery');
select tests.cart('2x2');
select is(tests.q(), '100000/0/0/100000/-/-', 'at the free-delivery minimum: free');
select is(tests.q('FLAT100'), '100000/4900/10000/94900/FLAT100/-', 'free delivery is judged on subtotal − discount');
select is(tests.q('PCT1'), '100000/0/0/100000/-/COUPON_NOT_APPLICABLE', 'a code that would raise the total (fee comes back) does not apply');

-- online_only ---------------------------------------------------------------------

select tests.cart('1');
select is(tests.q('ONLINE1', 'cod'), '1000000/0/0/1000000/-/COUPON_ONLINE_ONLY', 'online-only code refused for COD');
select is(tests.q('ONLINE1', 'razorpay'), '1000000/0/5000/995000/ONLINE1/-', 'online-only code with Razorpay');
select is(tests.q('ONLINE1'), '1000000/0/5000/995000/ONLINE1/-', 'online-only code before a method is picked');
select throws_ok($$select tests.place('cod', 'ONLINE1')$$, 'P0001', 'COUPON_ONLINE_ONLY', 'place_order refuses it for COD');

-- place_order: writes and the split -------------------------------------------------

select tests.cart('2 3');
select is(tests.q('split1', 'cod'), '80000/4900/1001/83899/SPLIT1/-', 'quote before placing');
select lives_ok($$select tests.keep('split', tests.place('cod', 'split1'))$$, 'order placed with a code');
select results_eq(
  $$select subtotal_paise, delivery_fee_paise, discount_paise, total_paise, coupon_code, promotion_id from public.orders where id = tests.id('split')$$,
  $$values (80000, 4900, 1001, 83899, 'SPLIT1', tests.pid(16))$$, 'order: discount, code and promotion; total = subtotal + fee − discount');
select results_eq(
  $$select variant_id, discount_paise from public.order_items where order_id = tests.id('split') order by variant_id$$,
  $$values ('d0000000-0000-0000-0000-000000000002'::uuid, 626), ('d0000000-0000-0000-0000-000000000003'::uuid, 375)$$,
  'split by line total (625.6 / 375.4 rounded down), remainder to the largest line');
reset role;
select results_eq($$select promotion_id, user_id, discount_paise from public.promotion_redemptions where order_id = tests.id('split')$$,
  $$values (tests.pid(16), '11111111-1111-1111-1111-111111111111'::uuid, 1001)$$, 'redemption written');
select tests.login('alice');
select tests.cart('1');
select is(tests.q('WELCOME'), '1000000/0/0/1000000/-/COUPON_FIRST_ORDER', 'first-order code refused once an order exists');

-- per_user_limit and usage_limit; a cancelled order gives the use back ----------------

select tests.keep('mine', tests.place('cod', 'MINE1'));
select tests.cart('1');
select is(tests.q('MINE1'), '1000000/0/0/1000000/-/COUPON_LIMIT_REACHED', 'per-user limit reached');
select public.cancel_order(tests.id('mine'));
select is(tests.q('MINE1'), '1000000/0/5000/995000/MINE1/-', 'cancelling the order gives the use back');

select tests.login('bob');
select tests.cart('2');
select tests.keep('once', tests.place('cod', 'ONCE1'));
select tests.login('alice');
select is(tests.q('ONCE1'), '1000000/0/0/1000000/-/COUPON_USED_UP', 'usage limit counts the whole shop');
select throws_ok($$select tests.place('cod', 'ONCE1')$$, 'P0001', 'COUPON_USED_UP', 'place_order refuses a used-up code');
select tests.login('bob');
select public.cancel_order(tests.id('once'));
select tests.login('alice');
select is(tests.q('ONCE1'), '1000000/0/5000/995000/ONCE1/-', '... until that order is cancelled');

-- COD limit on the discounted total; bad codes raise -----------------------------------

reset role;
update public.store_settings set cod_max_paise = 990000;
select tests.login('alice');
select throws_ok($$select tests.place('cod')$$, 'P0001', 'COD_UNAVAILABLE', 'COD refused: ₹10,000 > ₹9,900');
select lives_ok($$select tests.keep('codok', tests.place('cod', 'FLAT100'))$$, 'COD allowed once the code brings the total to ₹9,900');
select is((select total_paise from public.orders where id = tests.id('codok')), 990000, '... total 990000');
reset role;
update public.store_settings set cod_max_paise = 2500000;
select tests.login('alice');
select tests.cart('1 2');
select throws_ok($$select tests.place('cod', 'NOPE')$$, 'P0001', 'COUPON_NOT_FOUND', 'place_order raises a bad code (no silent fallback)');
select is(tests.err($$select tests.place('cod', 'ACCX')$$), 'COUPON_MIN_ORDER|60000', 'place_order: COUPON_MIN_ORDER with the minimum in details');
select is((select count(*)::int from public.cart_items), 2, 'refused checkouts leave the cart alone');

-- orders total check ------------------------------------------------------------

reset role;
select throws_ok($$insert into public.orders (user_id, status, payment_method, subtotal_paise, delivery_fee_paise, discount_paise, total_paise, address)
  values ('11111111-1111-1111-1111-111111111111', 'confirmed', 'cod', 10000, 0, 1000, 10000, '{}')$$, '23514', null, 'total must subtract the discount');
select throws_ok($$insert into public.orders (user_id, status, payment_method, subtotal_paise, delivery_fee_paise, discount_paise, total_paise, address)
  values ('11111111-1111-1111-1111-111111111111', 'confirmed', 'cod', 10000, 0, 9901, 99, '{}')$$, '23514', null, 'an order never costs under ₹1 before delivery');
select throws_ok($$insert into public.orders (user_id, status, payment_method, subtotal_paise, delivery_fee_paise, discount_paise, total_paise, address)
  values ('11111111-1111-1111-1111-111111111111', 'confirmed', 'cod', 10000, 0, -1, 10001, '{}')$$, '23514', null, 'no negative discount');
select throws_ok(format($$update public.order_items set discount_paise = 50001 where order_id = %L and variant_id = 'd0000000-0000-0000-0000-000000000002'$$,
  tests.id('split')), '23514', null, 'a line discount never passes the line total');

-- Rate limit ----------------------------------------------------------------------

select tests.login('dave');
select tests.cart('1');
select is((select count(*)::int from generate_series(1, 10) n where tests.q('GUESS' || n) like '%COUPON_NOT_FOUND'), 10, 'ten wrong guesses');
select is(tests.q('WELCOME'), '1000000/0/0/1000000/-/COUPON_RATE_LIMIT', 'the eleventh lookup is refused, even for a good code');
select throws_ok($$select tests.place('cod', 'WELCOME')$$, 'P0001', 'COUPON_RATE_LIMIT', 'place_order is rate limited too');
select is(tests.q(), '1000000/0/0/1000000/-/-', 'quotes without a code still work');
reset role;
update public.coupon_attempts set at = now() - interval '11 minutes';
select tests.login('dave');
select is(tests.q('WELCOME'), '1000000/0/10000/990000/WELCOME/-', 'the limit lifts after 10 minutes');

-- Automatic sales -------------------------------------------------------------------

reset role;
insert into public.promotions (id, title, kind, value, max_discount_paise, applies_to, ends_at, per_user_limit, first_order_only, online_only, is_active, starts_at)
values
  (tests.pid(31), 'Phones 5%', 'percent', 5, null, 'items', null, null, false, false, true, now()),
  (tests.pid(32), 'Flat 400', 'flat', 40000, null, 'order', null, null, false, false, true, now()),
  (tests.pid(33), 'Ends soon', 'flat', 50000, null, 'order', now() + interval '1 day', null, false, false, true, now()),
  (tests.pid(34), 'Online deal', 'flat', 60000, null, 'order', null, null, false, true, true, now()),
  (tests.pid(35), 'First order deal', 'flat', 70000, null, 'order', null, null, true, false, true, now()),
  (tests.pid(36), 'Paused sale', 'flat', 90000, null, 'order', null, null, false, false, false, now()),
  (tests.pid(37), 'Later sale', 'flat', 90000, null, 'order', null, null, false, false, true, now() + interval '1 day');
insert into public.promotion_targets (promotion_id, target_type, target_id) values (tests.pid(31), 'category', 'c0000000-0000-0000-0000-000000000001');

select tests.login('alice');
select tests.cart('1');
select is(tests.q(null, 'cod'), '1000000/0/50000/950000/Ends soon/-', 'best automatic sale; ₹500 tie broken by the earliest end');
select is(tests.q(null, 'razorpay'), '1000000/0/60000/940000/Online deal/-', 'online-only sale when paying online');
select is(tests.q('FLAT100', 'razorpay'), '1000000/0/60000/940000/Online deal/COUPON_BETTER_OFFER', 'a weaker typed code gives way to the bigger sale');
select is(tests.q('NOPE2', 'razorpay'), '1000000/0/60000/940000/Online deal/COUPON_NOT_FOUND', 'a bad code reports its error and falls back to the sale');
select lives_ok($$select tests.keep('auto', tests.place('cod'))$$, 'order with an automatic sale');
select results_eq($$select discount_paise, total_paise, promotion_id, coupon_code from public.orders where id = tests.id('auto')$$,
  $$values (50000, 950000, tests.pid(33), null::text)$$, '... recorded with its promotion and no code');
select tests.login('carol');
select tests.cart('1');
select is(tests.q(null, 'cod'), '1000000/0/70000/930000/First order deal/-', 'first-order sale for a new customer');
reset role;
update public.promotions set is_active = false where code is null;

-- Listings ------------------------------------------------------------------------

select tests.login('anon');
select ok(tests.codes(public.available_offers()) @> '{WELCOME,ACCX,SHIPFREE}', 'anon lists public running offers');
select ok(not tests.codes(public.available_offers()) && '{HIDDEN1,BOBONLY,PAUSED1,SOON1,OLD1}', 'anon: no hidden, personal, paused, future or ended codes');
select ok((public.available_offers() -> 0)::jsonb ?& array['id', 'title', 'description', 'code', 'kind', 'value', 'max_discount_paise',
  'min_subtotal_paise', 'starts_at', 'ends_at', 'applies_to', 'automatic'], 'offer rows have the contract keys');
select tests.login('bob');
select ok('BOBONLY' = any(tests.codes(public.available_offers())), 'bob sees his personal coupon');
select tests.login('alice');
select ok(not tests.codes(public.available_offers()) && '{BOBONLY,HIDDEN1,WELCOME}', 'alice: not bob''s coupon, not hidden, not a first-order code she can''t use');
select ok(tests.codes(public.offers_for_product('a0000000-0000-0000-0000-000000000002')) @> '{ACCX,PROD1,SPLIT1}'
  and not tests.codes(public.offers_for_product('a0000000-0000-0000-0000-000000000002')) && '{BRAND1,GROUP1,HIDDEN1}',
  'offers_for_product: only offers covering the case');
select tests.login('anon');
select is((select array_agg(id order by id) from public.offer_products(tests.pid(9))),
  '{a0000000-0000-0000-0000-000000000001,a0000000-0000-0000-0000-000000000003}'::uuid[], 'offer_products: what the brand offer covers');
select is_empty($$select 1 from public.offer_products(tests.pid(3))$$, 'offer_products: nothing for a hidden offer');
select tests.login('alice');
select is_empty($$select 1 from public.offer_products(tests.pid(4))$$, 'offer_products: nothing for someone else''s coupon');
select tests.login('bob');
select isnt_empty($$select 1 from public.offer_products(tests.pid(4))$$, 'offer_products: the owner sees theirs');

-- Banners -------------------------------------------------------------------------

select tests.login('staff');
select tests.keep('bp', public.admin_save_promotion(json_build_object('title', 'Diwali dhamaka', 'description', E'10% off\nall weekend',
  'code', 'sale10', 'kind', 'percent', 'value', 10, 'show_banner', true, 'ends_at', now() + interval '7 days')));
select results_eq($$select title, subtitle, cta_label, link, starts_at, ends_at, is_active from public.banners where promotion_id = tests.id('bp')$$,
  $$select 'Diwali dhamaka', '10% off all weekend', 'Use code SALE10', '/offers/' || id, starts_at, ends_at, true from public.promotions where id = tests.id('bp')$$,
  'show_banner makes a banner: same window, /offers/<id>, "Use code X"');
update public.banners set image_path = 'banners/1730000000000.webp', tone = 2 where promotion_id = tests.id('bp');
select public.admin_save_promotion(json_build_object('id', tests.id('bp'), 'title', 'Diwali mega sale', 'ends_at', now() + interval '3 days'));
select results_eq($$select title, ends_at, image_path, tone from public.banners where promotion_id = tests.id('bp')$$,
  $$values ('Diwali mega sale', now() + interval '3 days', 'banners/1730000000000.webp', 2)$$, 'editing the promotion updates its banner; image and tone stay');
select public.admin_save_promotion(json_build_object('id', tests.id('bp'), 'is_active', false));
select tests.login('anon');
select is_empty(format('select 1 from public.banners where promotion_id = %L', tests.id('bp')), 'a paused promotion''s banner is hidden');
select tests.login('staff');
select public.admin_save_promotion(json_build_object('id', tests.id('bp'), 'show_banner', false));
select is_empty(format('select 1 from public.banners where promotion_id = %L', tests.id('bp')), 'show_banner off deletes the banner');
reset role;
insert into public.promotions (id, title, kind, value, show_banner) values (tests.pid(41), 'Big sale', 'percent', 5, true);
select is((select cta_label from public.banners where promotion_id = tests.pid(41)), 'Shop the sale', 'automatic sale banner: "Shop the sale"');
delete from public.promotions where id = tests.pid(41);
select is_empty($$select 1 from public.banners where promotion_id = tests.pid(41)$$, 'deleting the promotion deletes its banner');
insert into public.promotions (id, title, code, kind, value, show_banner) values (tests.pid(42), 'Long', 'SUPERLONGCODE1', 'flat', 5000, true);
select is((select cta_label from public.banners where promotion_id = tests.pid(42)), 'View offer', 'a code too long for the button: "View offer"');
select throws_ok($$insert into public.promotions (title, code, kind, value, is_public, show_banner) values ('Secret', 'SECRETX', 'flat', 5000, false, true)$$,
  '23514', null, 'no banner for a hidden code');

insert into public.banners (title, link, starts_at, ends_at, is_active) values
  ('Test banner running', '/repairs', now() - interval '1 hour', null, true),
  ('Test banner paused', '/repairs', now() - interval '1 hour', null, false),
  ('Test banner future', '/repairs', now() + interval '1 day', null, true),
  ('Test banner over', '/repairs', now() - interval '2 days', now() - interval '1 day', true);
select tests.login('anon');
select is((select array_agg(title) from public.banners where title like 'Test banner%'), '{Test banner running}', 'anon reads running banners only');
select throws_ok($$insert into public.banners (title, link) values ('Mine', '/offers')$$, '42501', null, 'anon cannot add banners');
select tests.login('alice');
select is((select array_agg(title) from public.banners where title like 'Test banner%'), '{Test banner running}', 'customers read running banners only');
select throws_ok($$insert into public.banners (title, link) values ('Mine', '/offers')$$, '42501', null, 'customers cannot add banners');
select is_empty($$update public.banners set title = 'Hacked' returning 1$$, 'customers cannot edit banners');
select tests.login('staff');
select is((select count(*)::int from public.banners where title like 'Test banner%'), 4, 'staff read every banner');
select throws_ok($$insert into public.banners (title, link) values ('Evil', 'https://evil.example')$$, '23514', null, 'banner links are app routes, not URLs');
select throws_ok($$insert into public.banners (title, link) values ('Evil', '/offers/x y')$$, '23514', null, 'no spaces in banner links');
select throws_ok($$insert into public.banners (title, link, image_path) values ('Pic', '/offers', 'store/1.webp')$$, '23514', null, 'banner images live under banners/');
select lives_ok($$insert into public.banners (title, link) values ('Cases', '/search?category=cases-covers&sort=price')$$, 'a search link with filters is fine');

-- Referrals -------------------------------------------------------------------------

select tests.login('alice');
select matches(public.my_referral() ->> 'code', '^[A-Z0-9]{8}$', 'my_referral makes a code on first call');
select is(public.my_referral() ->> 'code', (select public.my_referral() ->> 'code'), 'the same code after that');
select ok((public.my_referral())::jsonb ?& array['enabled', 'code', 'friend_paise', 'reward_paise', 'min_order_paise', 'joined', 'rewarded', 'can_enter_code'],
  'my_referral has the contract keys');
select is((public.my_referral() ->> 'can_enter_code')::boolean, false, 'alice has orders: no friend code for her');
reset role;
select set_config('tests.alice_code', (select code from public.referral_codes where user_id = '11111111-1111-1111-1111-111111111111'), true);

select tests.login('carol');
select is((public.my_referral() ->> 'can_enter_code')::boolean, true, 'carol (no orders) can enter a code');
select throws_ok($$select public.apply_referral_code((select public.my_referral() ->> 'code'))$$, 'P0001', 'REFERRAL_SELF', 'own code refused');
select throws_ok($$select public.apply_referral_code('ZZZZZZZZ')$$, 'P0001', 'REFERRAL_INVALID', 'unknown code refused');
select is((select public.apply_referral_code(' ' || lower(current_setting('tests.alice_code')) || ' ')::jsonb - 'id' - 'code' - 'starts_at' - 'ends_at'),
  '{"title": "Welcome gift from a friend", "description": "", "kind": "flat", "value": 20000, "max_discount_paise": null,
    "min_subtotal_paise": 199900, "applies_to": "order", "automatic": false, "online_only": false, "first_order_only": true}'::jsonb,
  'carol applies alice''s code and gets her welcome coupon');
select throws_ok(format('select public.apply_referral_code(%L)', current_setting('tests.alice_code')), 'P0001', 'REFERRAL_USED', 'a second code refused');
select is((public.my_referral() ->> 'can_enter_code')::boolean, false, '... and the app stops offering it');
reset role;
select set_config('tests.friend_code', (select code from public.promotions where user_id = '44444444-4444-4444-4444-444444444444'), true);
select tests.login('alice');
select throws_ok(format('select public.apply_referral_code(%L)', current_setting('tests.alice_code')), 'P0001', 'REFERRAL_TOO_LATE', 'customers with an order cannot be referred');
select ok(not current_setting('tests.friend_code') = any(tests.codes(public.available_offers())), 'carol''s coupon is not listed for alice');
select tests.cart('1');
select is(tests.q(current_setting('tests.friend_code')), '1000000/0/0/1000000/-/COUPON_NOT_FOUND', '... and alice cannot use it');
select tests.login('carol');
select ok(current_setting('tests.friend_code') = any(tests.codes(public.available_offers())), 'carol sees her welcome coupon');
select tests.cart('1');
select tests.keep('c1', tests.place('cod', current_setting('tests.friend_code')));
select is((select discount_paise from public.orders where id = tests.id('c1')), 20000, 'carol''s first order uses it');
reset role;
select is((select status::text from public.referrals where referee_id = '44444444-4444-4444-4444-444444444444'), 'pending', 'no reward before delivery');
select tests.deliver(tests.id('c1'));
reset role;
select results_eq($$select kind::text, value, min_subtotal_paise, is_public, code ~ '^REWARD' from public.promotions
  where user_id = '11111111-1111-1111-1111-111111111111'$$, $$values ('flat', 20000, 199900, false, true)$$, 'delivery pays alice a personal reward coupon');
select results_eq($$select status::text, rewarded_at is not null from public.referrals where referee_id = '44444444-4444-4444-4444-444444444444'$$,
  $$values ('rewarded', true)$$, 'referral marked rewarded');
select tests.login('carol');
select tests.cart('1');
select tests.keep('c2', tests.place('cod'));
select tests.deliver(tests.id('c2'));
reset role;
select is((select count(*)::int from public.promotions where user_id = '11111111-1111-1111-1111-111111111111'), 1, 'a second delivery pays nothing more');

update public.store_settings set referral_monthly_cap = 1;
select tests.login('erin');
select lives_ok(format('select public.apply_referral_code(%L)', current_setting('tests.alice_code')), 'erin applies alice''s code');
select tests.cart('2');
select tests.keep('e1', tests.place('cod'));
select tests.deliver(tests.id('e1'));
reset role;
select is((select status::text from public.referrals where referee_id = '66666666-6666-6666-6666-666666666666'), 'pending', 'an order under the minimum pays nothing yet');
select tests.login('erin');
select tests.cart('1');
select tests.keep('e2', tests.place('cod'));
select tests.deliver(tests.id('e2'));
reset role;
select is((select status::text from public.referrals where referee_id = '66666666-6666-6666-6666-666666666666'), 'void', 'monthly cap reached: void');
select is((select count(*)::int from public.promotions where user_id = '11111111-1111-1111-1111-111111111111'), 1, '... and no second reward');
select tests.login('alice');
select results_eq($$select (j ->> 'joined')::int, (j ->> 'rewarded')::int from (select public.my_referral()::jsonb j) x$$, $$values (2, 1)$$, 'my_referral counts');
reset role;
update public.store_settings set referral_enabled = false;
select tests.login('dave');
select throws_ok(format('select public.apply_referral_code(%L)', current_setting('tests.alice_code')), 'P0001', 'REFERRAL_OFF', 'referrals switched off');
select is((public.my_referral() ->> 'can_enter_code')::boolean, false, 'no code entry while off');

-- Admin -----------------------------------------------------------------------------

select tests.login('alice');
select throws_ok($$select public.admin_save_promotion('{"title": "Mine", "kind": "flat", "value": 100000}')$$, 'P0001', 'FORBIDDEN', 'customers cannot save promotions');
select throws_ok($$select public.admin_promotions()$$, 'P0001', 'FORBIDDEN', 'customers cannot list promotions');
select tests.login('anon');
select throws_ok($$select public.admin_promotions()$$, '42501', null, 'anon cannot call admin_promotions');
select tests.login('staff');
select is(tests.err($$select public.admin_save_promotion('{"title": "Cases", "kind": "percent", "value": 10, "applies_to": "items"}')$$),
  'INVALID_PROMOTION|items needs a target', 'an items offer needs a target');
select is(tests.err($$select public.admin_save_promotion('{"title": "Too much", "kind": "percent", "value": 95}')$$),
  'INVALID_PROMOTION|promotions_value_check', 'percent is 1..90');
select is(tests.err($$select public.admin_save_promotion('{"title": "Ghost", "kind": "flat", "value": 1000, "applies_to": "items",
  "targets": [{"target_type": "product", "target_id": "a0000000-0000-0000-0000-0000000000ff"}]}')$$),
  'INVALID_PROMOTION|unknown target', 'targets must exist');
select matches(tests.err($$select public.admin_save_promotion('{"title": "Bad", "kind": "nope", "value": 1}')$$),
  '^INVALID_PROMOTION\|invalid input value for enum', 'unknown kind');
select is(tests.err($$select public.admin_save_promotion('{"title": "Dup", "code": "welcome", "kind": "flat", "value": 1000}')$$),
  'CODE_TAKEN|', 'a code in use');
select tests.keep('new', public.admin_save_promotion('{"title": "New cases", "code": " new10 ", "kind": "percent", "value": 10, "applies_to": "items",
  "targets": [{"target_type": "category", "target_id": "c0000000-0000-0000-0000-000000000002"}, {"target_type": "collection", "target_id": "70000000-0000-0000-0000-000000000001"}]}'));
select results_eq($$select code, per_user_limit, is_public, is_active, starts_at, (select count(*)::int from public.promotion_targets where promotion_id = id)
  from public.promotions where id = tests.id('new')$$, $$values ('NEW10', 1, true, true, now(), 2)$$, 'saved with defaults, uppercase code and both targets');
select lives_ok(format($$select public.admin_save_promotion('{"id": "%s", "is_active": false}')$$, tests.id('new')), 'pause with just the id');
select results_eq($$select is_active, value, (select count(*)::int from public.promotion_targets where promotion_id = id) from public.promotions where id = tests.id('new')$$,
  $$values (false, 10, 2)$$, 'left-out keys and targets are kept');
select throws_ok($$select public.admin_save_promotion('{"id": "f1000000-0000-0000-0000-0000000000ff", "is_active": false}')$$, 'P0001', 'NOT_FOUND', 'unknown id');
select results_eq($$select (p ->> 'uses')::int, (p ->> 'discount_total_paise')::int, p ->> 'status', json_array_length(p -> 'targets')
  from json_array_elements(public.admin_promotions()) p where p ->> 'code' = 'SPLIT1'$$, $$values (1, 1001, 'running', 0)$$, 'admin_promotions: uses and total given');
select is((select array_agg(distinct p ->> 'status' order by p ->> 'status') from json_array_elements(public.admin_promotions()) p),
  '{ended,paused,running,scheduled}', 'admin_promotions: every status');
select is_empty(format('delete from public.promotions where id = %L returning 1', tests.pid(16)), 'a used promotion cannot be deleted');
select isnt_empty(format('delete from public.promotions where id = %L returning 1', tests.id('new')), 'an unused one can');
select lives_ok($$insert into public.collections (slug, name) values ('test-diwali', 'Diwali picks')$$, 'staff create groups');

-- RLS -------------------------------------------------------------------------------

select tests.login('anon');
select throws_ok('select 1 from public.promotions', '42501', null, 'anon: promotions denied');
select throws_ok('select 1 from public.promotion_redemptions', '42501', null, 'anon: redemptions denied');
select throws_ok('select 1 from public.referrals', '42501', null, 'anon: referrals denied');
select throws_ok($$select public.quote_order()$$, '42501', null, 'anon cannot quote');
select throws_ok($$select public.my_referral()$$, '42501', null, 'anon cannot call my_referral');
select is((select count(*)::int from public.collection_products where collection_id = '70000000-0000-0000-0000-000000000001'), 1, 'anon reads groups');
select tests.login('alice');
select is_empty('select 1 from public.promotions', 'customers cannot read promotions');
select is_empty('select 1 from public.promotion_targets', 'customers cannot read targets');
select is_empty('select 1 from public.promotion_redemptions', 'customers cannot read redemptions, not even their own');
select is_empty('select 1 from public.referral_codes', 'customers cannot read referral codes');
select is_empty('select 1 from public.referrals', 'customers cannot read referrals');
select throws_ok('select 1 from public.coupon_attempts', '42501', null, 'customers: coupon_attempts denied');
select throws_ok(format($$insert into public.promotion_redemptions (order_id, promotion_id, user_id, discount_paise) values (%L, %L, auth.uid(), 0)$$,
  tests.id('codok'), tests.pid(18)), '42501', null, 'customers cannot insert redemptions');
select throws_ok($$insert into public.promotions (title, code, kind, value) values ('Mine', 'MINEMINE', 'flat', 100000)$$, '42501', null, 'customers cannot create promotions');
select is_empty($$update public.promotions set value = 90 returning 1$$, 'customers cannot edit promotions');
select throws_ok($$insert into public.collections (slug, name) values ('mine', 'Mine')$$, '42501', null, 'customers cannot create groups');
select throws_ok($$insert into public.referrals (referee_id, referrer_id) values (auth.uid(), '22222222-2222-2222-2222-222222222222')$$, '42501', null, 'customers cannot write referrals');
select is_empty($$update public.store_settings set referral_reward_paise = 9999999 returning 1$$, 'customers cannot change referral settings');
select tests.login('staff');
select isnt_empty('select 1 from public.promotion_redemptions', 'staff read redemptions');
reset role;
select ok(not has_function_privilege('authenticated', 'private.price_lines(uuid, uuid[], text, public.payment_method, boolean)', 'execute'),
  'clients cannot call the pricing function directly');
select ok(not exists (select 1 from pg_proc where proname = 'place_order' and pronargs = 2), 'the 2-argument place_order is gone');

-- Every order: Σ line discounts = order discount; total = subtotal + fee − discount -----------

select is_empty($$select o.id from public.orders o left join public.order_items i on i.order_id = o.id
  group by o.id having o.discount_paise <> coalesce(sum(i.discount_paise), 0) or o.total_paise <> o.subtotal_paise + o.delivery_fee_paise - o.discount_paise$$,
  'line discounts add up to every order''s discount');

select * from finish();
rollback;
