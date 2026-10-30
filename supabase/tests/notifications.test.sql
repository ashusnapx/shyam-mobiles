-- Notifications: every order, payment, repair, coupon, feedback and stock event reaches the right people (and only
-- them), with the copy people read; RLS; the read RPCs; device tokens; and the push trigger never failing anything.
begin;
create extension if not exists pgtap with schema extensions;
select plan(125);

-- Fixtures ------------------------------------------------------------------------

delete from public.admins; -- staff = exactly the two below (rolled back at the end)
delete from public.promotions; -- no automatic sale changes the totals
update public.store_settings set delivery_fee_paise = 0, cod_enabled = true, cod_max_paise = 2500000,
  referral_enabled = true, referral_friend_paise = 20000, referral_reward_paise = 20000, referral_min_order_paise = 199900;
insert into auth.users (id, email) values
  ('ab000000-0000-0000-0000-000000000001', 'nt-asha@test.dev'),
  ('ab000000-0000-0000-0000-000000000002', 'nt-ravi@test.dev'),
  ('ab000000-0000-0000-0000-000000000003', 'nt-kiran@test.dev'),
  ('ab000000-0000-0000-0000-000000000011', 'nt-staff1@test.dev'),
  ('ab000000-0000-0000-0000-000000000012', 'nt-staff2@test.dev');
insert into public.admins (user_id) values ('ab000000-0000-0000-0000-000000000011'), ('ab000000-0000-0000-0000-000000000012');
insert into public.categories (id, slug, name, kind) values ('ab0000c0-0000-0000-0000-000000000001', 'nt-cat', 'Nt cat', 'phone');
insert into public.brands (id, slug, name) values ('ab0000b0-0000-0000-0000-000000000001', 'nt-brand', 'Nt');
insert into public.products (id, slug, name, brand_id, category_id) values
  ('ab0000a0-0000-0000-0000-000000000001', 'nt-phone', 'Test Phone', 'ab0000b0-0000-0000-0000-000000000001', 'ab0000c0-0000-0000-0000-000000000001');
insert into public.variants (id, product_id, sku, name, price_paise, mrp_paise, stock) values
  ('ab0000d0-0000-0000-0000-000000000001', 'ab0000a0-0000-0000-0000-000000000001', 'NT-1', '8 GB', 50000, 50000, 5),
  ('ab0000d0-0000-0000-0000-000000000002', 'ab0000a0-0000-0000-0000-000000000001', 'NT-2', '12 GB', 50000, 50000, 100),
  ('ab0000d0-0000-0000-0000-000000000003', 'ab0000a0-0000-0000-0000-000000000001', 'NT-3', '16 GB', 250000, 250000, 100);
insert into public.addresses (user_id, name, phone, line1, city, state, pincode) values
  ('ab000000-0000-0000-0000-000000000001', 'Asha', '+919876543210', '1 Main Road', 'Waidhan', 'Madhya Pradesh', '486886'),
  ('ab000000-0000-0000-0000-000000000003', 'Kiran', '+919876543212', '3 Main Road', 'Waidhan', 'Madhya Pradesh', '486886');

create function pg_temp.as_user(p uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
create function pg_temp.asha() returns void language sql as $$ select pg_temp.as_user('ab000000-0000-0000-0000-000000000001') $$;
create function pg_temp.ravi() returns void language sql as $$ select pg_temp.as_user('ab000000-0000-0000-0000-000000000002') $$;
create function pg_temp.kiran() returns void language sql as $$ select pg_temp.as_user('ab000000-0000-0000-0000-000000000003') $$;
create function pg_temp.staff1() returns void language sql as $$ select pg_temp.as_user('ab000000-0000-0000-0000-000000000011') $$;
-- the Edge Functions and pg_cron: no user
create function pg_temp.service() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform set_config('role', 'service_role', true);
end $$;
create function pg_temp.keep(p_name text, p_id uuid) returns uuid language sql as $$ select set_config('nt.' || p_name, p_id::text, true)::uuid $$;
create function pg_temp.id(p_name text) returns uuid language sql as $$ select current_setting('nt.' || p_name)::uuid $$;
create function pg_temp.num(p_name text) returns text language sql security definer as $$
  select coalesce((select number from public.orders where id = pg_temp.id(p_name)),
                  (select number from public.repair_bookings where id = pg_temp.id(p_name))) $$;
-- a fresh one-line cart, ordered
create function pg_temp.order_as(p_user uuid, p_variant uuid, p_qty int, p_method public.payment_method) returns uuid
language plpgsql as $$
begin
  perform pg_temp.as_user(p_user);
  insert into public.cart_items (user_id, variant_id, qty) values (p_user, p_variant, p_qty);
  return public.place_order((select id from public.addresses where user_id = p_user), p_method);
end $$;
create function pg_temp.book(p_model text) returns uuid language plpgsql as $$
begin
  perform pg_temp.asha();
  insert into public.repair_bookings (user_id, device_brand, device_model, issue, preferred_date, slot, contact_phone)
  values (auth.uid(), 'Samsung', p_model, 'screen', (now() at time zone 'Asia/Kolkata')::date + 1, 'morning', '+919876543210');
  return (select id from public.repair_bookings where device_model = p_model);
end $$;

-- What reached p_user since the last look: "kind: title" lines, sorted by kind, or null for nothing.
create temp table seen (id uuid primary key);
create function pg_temp.news(p_user uuid) returns text language plpgsql security definer as $$
declare v text;
begin
  select string_agg(kind || ': ' || title, ' / ' order by kind, title) into v
  from public.notifications n where user_id = p_user and not exists (select 1 from seen s where s.id = n.id);
  insert into seen select id from public.notifications where user_id = p_user on conflict do nothing;
  return v;
end $$;
-- the newest notification of p_kind for p_user: "body → link"
create function pg_temp.said(p_user uuid, p_kind text) returns text language sql security definer as $$
  select body || ' → ' || coalesce(link, '-') from public.notifications where user_id = p_user and kind = p_kind
  order by created_at desc limit 1 $$;
create function pg_temp.asha_news() returns text language sql as $$ select pg_temp.news('ab000000-0000-0000-0000-000000000001') $$;
create function pg_temp.ravi_news() returns text language sql as $$ select pg_temp.news('ab000000-0000-0000-0000-000000000002') $$;
create function pg_temp.staff1_news() returns text language sql as $$ select pg_temp.news('ab000000-0000-0000-0000-000000000011') $$;
create function pg_temp.staff2_news() returns text language sql as $$ select pg_temp.news('ab000000-0000-0000-0000-000000000012') $$;
create function pg_temp.asha_said(p_kind text) returns text language sql as $$ select pg_temp.said('ab000000-0000-0000-0000-000000000001', p_kind) $$;
create function pg_temp.staff2_said(p_kind text) returns text language sql as $$ select pg_temp.said('ab000000-0000-0000-0000-000000000012', p_kind) $$;

-- Money copy ----------------------------------------------------------------------

select is(private.inr(12999900), '₹1,29,999', 'Indian grouping');
select is(private.inr(4950), '₹49.50', 'paise only when there are some');
select is(private.inr(100000000), '₹10,00,000', 'lakhs');

-- A cash-on-delivery order, end to end ------------------------------------------

select pg_temp.keep('cod', pg_temp.order_as('ab000000-0000-0000-0000-000000000001', 'ab0000d0-0000-0000-0000-000000000002', 1, 'cod'));
select is(pg_temp.asha_news(), 'order_confirmed: ' || pg_temp.num('cod') || ' is confirmed', 'placing COD: the customer hears it''s confirmed');
select is(pg_temp.asha_said('order_confirmed'), '₹500, cash on delivery. We’ll tell you when it’s packed. → /orders/' || pg_temp.id('cod'),
  'with the amount, linking to the order');
select is(pg_temp.staff1_news(), 'staff_new_order: New order ' || pg_temp.num('cod'), 'every admin hears about a new order');
select is(pg_temp.staff2_news(), 'staff_new_order: New order ' || pg_temp.num('cod'), 'one row per admin');
select is(pg_temp.staff2_said('staff_new_order'), '₹500 · Cash on delivery · Test Phone · Waidhan → /admin/orders/' || pg_temp.id('cod'),
  'staff see amount, payment, items and town, linking to the admin order');
select is(pg_temp.ravi_news(), null, 'nobody else hears about it');

select pg_temp.staff1();
select public.admin_update_order(pg_temp.id('cod'), 'packed');
select is(pg_temp.asha_news(), 'order_packed: ' || pg_temp.num('cod') || ' is packed', 'packed');
select is(concat(pg_temp.staff1_news(), pg_temp.staff2_news()), '', 'staff aren''t told what staff just did');

select pg_temp.staff1();
select public.admin_update_order(pg_temp.id('cod'), 'shipped', null, 'Delhivery', 'DL123');
select is(pg_temp.asha_news(), 'order_shipped: ' || pg_temp.num('cod') || ' is on its way', 'shipped');
select is(pg_temp.asha_said('order_shipped'), 'Delhivery, tracking DL123. → /orders/' || pg_temp.id('cod'), 'with the courier and tracking');

select pg_temp.staff1();
select public.admin_update_order(pg_temp.id('cod'), 'shipped', null, null, 'DL999');
select is(pg_temp.asha_news(), 'order_tracking: Tracking updated for ' || pg_temp.num('cod'), 'a tracking fix is news, even without a note');
select is(pg_temp.asha_said('order_tracking'), 'Delhivery, tracking DL999. → /orders/' || pg_temp.id('cod'), 'the new number');

select pg_temp.staff1();
select public.admin_update_order(pg_temp.id('cod'), 'shipped', 'Arrives Friday.', null, 'DL777');
select is(pg_temp.asha_news(), 'order_tracking: Tracking updated for ' || pg_temp.num('cod'), 'tracking plus a note: one notification');
select is(pg_temp.asha_said('order_tracking'), 'Delhivery, tracking DL777. Arrives Friday. → /orders/' || pg_temp.id('cod'), 'the note joins it');

select pg_temp.staff1();
select public.admin_update_order(pg_temp.id('cod'), 'shipped', 'Running a day late.');
select is(pg_temp.asha_news(), 'order_update: Update on ' || pg_temp.num('cod'), 'a staff note on the timeline');
select is(pg_temp.asha_said('order_update'), 'Running a day late. → /orders/' || pg_temp.id('cod'), 'says the note');

select pg_temp.staff1();
select public.admin_update_order(pg_temp.id('cod'), 'delivered');
select is(pg_temp.asha_news(), 'order_delivered: ' || pg_temp.num('cod') || ' is delivered', 'delivered');
select is(pg_temp.asha_said('order_delivered'), 'How was it? Tap to rate your order. → /orders/' || pg_temp.id('cod'), 'invites a rating');

select pg_temp.staff1();
select public.admin_update_order(pg_temp.id('cod'), 'refunded');
select is(pg_temp.asha_news(), 'order_refunded: Refund of ₹500 for ' || pg_temp.num('cod'), 'refunded, once');

-- The customer cancels ---------------------------------------------------------------

select pg_temp.keep('cod2', pg_temp.order_as('ab000000-0000-0000-0000-000000000001', 'ab0000d0-0000-0000-0000-000000000002', 1, 'cod'));
select pg_temp.asha_news(), pg_temp.staff1_news(), pg_temp.staff2_news();
select pg_temp.asha();
select public.cancel_order(pg_temp.id('cod2'));
select is(pg_temp.asha_news(), 'order_cancelled: You cancelled ' || pg_temp.num('cod2'), 'your own cancel, as a receipt');
select is(pg_temp.asha_said('order_cancelled'), 'Nothing was charged. → /orders/' || pg_temp.id('cod2'), 'nothing charged on COD');
select is(pg_temp.staff1_news(), 'staff_order_cancelled: ' || pg_temp.num('cod2') || ' cancelled by the customer', 'staff hear stock is back');
select ok(pg_temp.staff2_said('staff_order_cancelled') like 'Stock is back: ₹500 · %', 'with what came back');
select is(pg_temp.staff2_news(), 'staff_order_cancelled: ' || pg_temp.num('cod2') || ' cancelled by the customer', 'both admins');

-- Paying online -----------------------------------------------------------------------

select pg_temp.keep('rzp', pg_temp.order_as('ab000000-0000-0000-0000-000000000001', 'ab0000d0-0000-0000-0000-000000000002', 1, 'razorpay'));
select is(pg_temp.asha_news(), 'order_awaiting_payment: Finish paying for ' || pg_temp.num('rzp'), 'an online order waits for payment');
select is(concat(pg_temp.staff1_news(), pg_temp.staff2_news()), '', 'staff hear nothing until it''s paid');

select pg_temp.service();
select public.mark_payment_failed(pg_temp.id('rzp'));
reset role;
select is(pg_temp.asha_news(), 'payment_failed: Payment failed for ' || pg_temp.num('rzp'), 'a failed payment');
select ok(pg_temp.asha_said('payment_failed') like 'Your items are still held for you. Try paying again before %m.%', 'says until when');

select pg_temp.service();
select public.mark_order_paid(pg_temp.id('rzp'), 'pay_nt1');
select public.mark_order_paid(pg_temp.id('rzp'), 'pay_nt1'); -- the webhook again
reset role;
select is(pg_temp.asha_news(), 'payment_received: Payment received for ' || pg_temp.num('rzp'), 'paid: one notification, however often it lands');
select is(pg_temp.staff1_news(), 'staff_order_paid: Paid order ' || pg_temp.num('rzp'), 'staff hear about a paid order');
select is(pg_temp.staff2_said('staff_order_paid'), '₹500 · Paid online · Test Phone · Waidhan → /admin/orders/' || pg_temp.id('rzp'), 'its summary');
select pg_temp.staff2_news();

select pg_temp.asha();
select public.cancel_order(pg_temp.id('rzp'));
select is(pg_temp.asha_news(), 'order_cancelled: You cancelled ' || pg_temp.num('rzp'), 'cancelling a paid order');
select ok(pg_temp.asha_said('order_cancelled') like 'A full refund of ₹500 to your original payment method is on its way%', 'promises the refund');
select is(pg_temp.staff1_news(), 'staff_refund_needed: Refund ₹500 for ' || pg_temp.num('rzp'), 'staff: refund needed');
select is(pg_temp.staff2_news(), 'staff_refund_needed: Refund ₹500 for ' || pg_temp.num('rzp'), 'both admins');

select pg_temp.service();
select public.mark_order_refunded('pay_nt1');
reset role;
select is(pg_temp.asha_news(), 'order_refunded: Refund of ₹500 for ' || pg_temp.num('rzp'), 'the refund lands');
select is(pg_temp.asha_said('order_refunded'), 'Refund issued. Banks usually take 5–7 working days to show it. → /orders/' || pg_temp.id('rzp'),
  'the timeline''s refund note is the body');

-- Expiry, a late payment, a revived order -------------------------------------------------

select pg_temp.keep('exp', pg_temp.order_as('ab000000-0000-0000-0000-000000000001', 'ab0000d0-0000-0000-0000-000000000002', 1, 'razorpay'));
select pg_temp.asha_news();
reset role;
update public.orders set reserved_until = now() - interval '1 minute' where id = pg_temp.id('exp');
select pg_temp.service();
select public.expire_unpaid_orders();
reset role;
select is(pg_temp.asha_news(), 'order_expired: ' || pg_temp.num('exp') || ' was cancelled', 'the payment hold ran out');
select is(concat(pg_temp.staff1_news(), pg_temp.staff2_news()), '', 'staff never saw that order');

select pg_temp.service();
select public.mark_order_paid(pg_temp.id('exp'), 'pay_nt2');
reset role;
select is(pg_temp.asha_news(), 'payment_received: Payment received for ' || pg_temp.num('exp'), 'a late payment revives an expired order');
select pg_temp.staff1_news(), pg_temp.staff2_news();

select pg_temp.keep('late', pg_temp.order_as('ab000000-0000-0000-0000-000000000001', 'ab0000d0-0000-0000-0000-000000000002', 1, 'razorpay'));
select public.cancel_order(pg_temp.id('late'));
select pg_temp.asha_news();
select is(concat(pg_temp.staff1_news(), pg_temp.staff2_news()), '', 'an unpaid online order cancelled by its customer is not staff news');
select pg_temp.service();
select public.mark_order_paid(pg_temp.id('late'), 'pay_nt3');
reset role;
select is(pg_temp.asha_news(), 'order_late_payment: We got your payment for ' || pg_temp.num('late'), 'money after a cancel');
select is(pg_temp.staff1_news(), 'staff_refund_needed: Refund ₹500 for ' || pg_temp.num('late'), 'staff must refund it');
select pg_temp.staff2_news();

-- The shop cancels ------------------------------------------------------------------------

select pg_temp.keep('shop', pg_temp.order_as('ab000000-0000-0000-0000-000000000001', 'ab0000d0-0000-0000-0000-000000000002', 1, 'cod'));
select pg_temp.asha_news(), pg_temp.staff1_news(), pg_temp.staff2_news();
select pg_temp.staff1();
select public.admin_update_order(pg_temp.id('shop'), 'cancelled', 'This colour is out of stock, sorry.');
select is(pg_temp.asha_news(), 'order_cancelled: ' || pg_temp.num('shop') || ' was cancelled by the shop', 'cancelled by the shop');
select is(pg_temp.asha_said('order_cancelled'), 'This colour is out of stock, sorry. → /orders/' || pg_temp.id('shop'), 'with their note');
select is(concat(pg_temp.staff1_news(), pg_temp.staff2_news()), '', 'nothing to refund: no staff notification');

-- Low stock: once per crossing, after sales only ----------------------------------------------

select pg_temp.order_as('ab000000-0000-0000-0000-000000000001', 'ab0000d0-0000-0000-0000-000000000001', 1, 'cod'); -- 5 → 4
select ok(pg_temp.staff2_news() not like '%stock%', 'above 3: quiet');
select pg_temp.order_as('ab000000-0000-0000-0000-000000000001', 'ab0000d0-0000-0000-0000-000000000001', 2, 'cod'); -- 4 → 2
select ok(pg_temp.staff2_news() like 'staff_low_stock: Low stock: Test Phone / staff_new_order: %', 'crossing to 3 or fewer');
select is(pg_temp.staff2_said('staff_low_stock'), '8 GB (NT-1): only 2 left. → /admin/products/ab0000a0-0000-0000-0000-000000000001',
  'which variant, how many, linking to the product');
select pg_temp.order_as('ab000000-0000-0000-0000-000000000001', 'ab0000d0-0000-0000-0000-000000000001', 1, 'cod'); -- 2 → 1
select ok(pg_temp.staff2_news() not like '%stock%', 'the next sale below 3 is quiet');
select pg_temp.order_as('ab000000-0000-0000-0000-000000000001', 'ab0000d0-0000-0000-0000-000000000001', 1, 'cod'); -- 1 → 0
select ok(pg_temp.staff2_news() like '% / staff_out_of_stock: Out of stock: Test Phone', 'selling the last one');
select pg_temp.staff1();
update public.variants set stock = 10 where id = 'ab0000d0-0000-0000-0000-000000000001';
update public.variants set stock = 2 where id = 'ab0000d0-0000-0000-0000-000000000001';
reset role;
select is(pg_temp.staff2_news(), null, 'staff edits aren''t sales');
select pg_temp.asha_news(), pg_temp.staff1_news();

-- A repair, every step -----------------------------------------------------------------------

select pg_temp.keep('r1', pg_temp.book('Galaxy A56'));
reset role;
select is(pg_temp.asha_news(), 'repair_booked: Repair booked for your Galaxy A56', 'booked');
select ok(pg_temp.asha_said('repair_booked') like 'Screen · %, morning (10 am – 1 pm). We’ll confirm the time soon. → /repairs/%', 'when, and what''s next');
select is(pg_temp.staff1_news(), 'staff_new_repair: New repair ' || pg_temp.num('r1') || ': Samsung Galaxy A56', 'staff: a new booking');
select ok(pg_temp.staff2_said('staff_new_repair') like 'Screen · %, morning (10 am – 1 pm) → /admin/repairs/' || pg_temp.id('r1'), 'what and when');
select is(pg_temp.ravi_news(), null, 'nobody else');
select pg_temp.staff2_news();

select pg_temp.staff1();
select public.admin_update_repair(pg_temp.id('r1'), 'confirmed');
select ok(pg_temp.asha_news() like 'repair_confirmed: Repair confirmed for %, morning (10 am – 1 pm)', 'confirmed with date and slot');
select is(concat(pg_temp.staff1_news(), pg_temp.staff2_news()), '', 'staff did it');

select pg_temp.staff1();
select public.admin_set_repair_quote(pg_temp.id('r1'), 20000);
select is(pg_temp.asha_news(), 'repair_quote: ₹200 quote for your Galaxy A56 screen: approve to start', 'a quote asks for approval');
select is(pg_temp.asha_said('repair_quote'), 'Work starts only after you approve this price. → /repairs/' || pg_temp.id('r1'), 'and says why');

select pg_temp.asha();
select public.decline_repair_quote(pg_temp.id('r1'), 'Too costly');
select is(pg_temp.staff1_news(), 'staff_quote_declined: Quote declined for ' || pg_temp.num('r1'), 'staff hear a no');
select is(pg_temp.staff2_said('staff_quote_declined'),
  '₹200 for the Samsung Galaxy A56 screen. Reason: “Too costly”. Quote again or cancel it. → /admin/repairs/' || pg_temp.id('r1'), 'with the reason');
select is(pg_temp.asha_news(), null, 'not the customer: they said it');
select pg_temp.staff2_news();

select pg_temp.staff1();
select public.admin_set_repair_quote(pg_temp.id('r1'), 15000, 'Without the frame.');
select is(pg_temp.asha_news(), 'repair_quote: ₹150 quote for your Galaxy A56 screen: approve to start', 'a new quote');
select pg_temp.asha();
select public.approve_repair_quote(pg_temp.id('r1'), 15000);
select is(pg_temp.staff2_news(), 'staff_quote_approved: Quote approved for ' || pg_temp.num('r1'), 'staff hear a yes');
select is(pg_temp.asha_news(), null, 'the customer said it');
select pg_temp.staff1_news();

select pg_temp.staff1();
select public.admin_update_repair(pg_temp.id('r1'), 'in_progress');
select is(pg_temp.asha_news(), 'repair_started: Work has started on your Galaxy A56', 'work started');
select pg_temp.staff1();
select public.admin_set_repair_quote(pg_temp.id('r1'), 18000);
select is(pg_temp.asha_news(), 'repair_quote: New ₹180 quote for your Galaxy A56 screen: approve to continue', 'a quote changed mid-repair');
select pg_temp.staff1();
select public.admin_set_repair_quote(pg_temp.id('r1'), 18000, null, true);
select is(pg_temp.asha_news(), 'repair_quote_agreed: ₹180 agreed for your Galaxy A56 screen', 'agreed on the phone');
select pg_temp.staff1();
select public.admin_update_repair(pg_temp.id('r1'), 'in_progress', 'Waiting for the part, tomorrow.');
select is(pg_temp.asha_news(), 'repair_update: Update on your Galaxy A56 repair', 'a staff note');
select pg_temp.staff1();
select public.admin_update_repair(pg_temp.id('r1'), 'ready');
select is(pg_temp.asha_news(), 'repair_ready: Your Galaxy A56 is ready for pickup', 'ready for pickup');
select is(pg_temp.asha_said('repair_ready'), 'Pay ₹180 when you collect it. → /repairs/' || pg_temp.id('r1'), 'with what to pay');
select pg_temp.staff1();
select public.admin_update_repair(pg_temp.id('r1'), 'completed');
select is(pg_temp.asha_news(), 'repair_completed: Your Galaxy A56 repair is complete', 'completed');
select ok(pg_temp.asha_said('repair_completed') like 'How did we do? Tap to rate the repair.%', 'invites a rating');
select is(concat(pg_temp.staff1_news(), pg_temp.staff2_news()), '', 'staff did every step');

select pg_temp.keep('r2', pg_temp.book('Galaxy A35'));
select pg_temp.asha_news(), pg_temp.staff1_news(), pg_temp.staff2_news();
select pg_temp.asha();
select public.cancel_repair(pg_temp.id('r2'));
select is(pg_temp.staff1_news(), 'staff_repair_cancelled: ' || pg_temp.num('r2') || ' cancelled by the customer', 'staff hear a customer cancel');
select is(pg_temp.asha_news(), null, 'their own cancel isn''t news to them');
select pg_temp.staff2_news();

select pg_temp.keep('r3', pg_temp.book('Galaxy M14'));
select pg_temp.asha_news(), pg_temp.staff1_news(), pg_temp.staff2_news();
select pg_temp.staff1();
select public.admin_update_repair(pg_temp.id('r3'), 'cancelled', 'We don''t stock this screen.');
select is(pg_temp.asha_news(), 'repair_cancelled: Your Galaxy M14 repair was cancelled', 'the shop cancels');
select is(pg_temp.asha_said('repair_cancelled'), 'We don''t stock this screen. → /repairs/' || pg_temp.id('r3'), 'with the reason');

-- Referrals and personal coupons ----------------------------------------------------------------

select pg_temp.ravi();
select public.my_referral() is not null;
reset role;
select set_config('nt.code', (select code from public.referral_codes where user_id = 'ab000000-0000-0000-0000-000000000002'), true);
select pg_temp.kiran();
select public.apply_referral_code(current_setting('nt.code'));
reset role;
select is(pg_temp.news('ab000000-0000-0000-0000-000000000003'), 'referral_welcome: Your welcome gift: ₹200 off your first order', 'the friend''s welcome gift');
select ok(pg_temp.said('ab000000-0000-0000-0000-000000000003', 'referral_welcome') like 'Use code FRIEND% on an order of ₹1,999 or more by %. → /offers/%',
  'how to use it, linking to the coupon');

select pg_temp.keep('ref', pg_temp.order_as('ab000000-0000-0000-0000-000000000003', 'ab0000d0-0000-0000-0000-000000000003', 1, 'cod'));
select pg_temp.staff1();
select public.admin_update_order(pg_temp.id('ref'), 'packed');
select public.admin_update_order(pg_temp.id('ref'), 'shipped');
select public.admin_update_order(pg_temp.id('ref'), 'delivered');
reset role;
select is(pg_temp.ravi_news(), 'referral_reward: You earned a ₹200 coupon for referring a friend', 'the referrer''s reward');

insert into public.promotions (title, code, kind, value, is_public, user_id)
values ('Wholesale buyer', 'NTBULK01', 'percent', 5, false, 'ab000000-0000-0000-0000-000000000001');
select is(pg_temp.asha_news(), 'coupon: A coupon just for you: Wholesale buyer', 'any personal coupon');
select ok(pg_temp.asha_said('coupon') like 'Use code NTBULK01. → /offers/%', 'its code');

-- Feedback ----------------------------------------------------------------------------------------

select pg_temp.staff1_news(), pg_temp.staff2_news();
select pg_temp.asha();
select public.send_feedback('order', 2, 'Box was dented', pg_temp.id('cod'));
select is(pg_temp.staff1_news(), 'staff_feedback_low: Low rating: 2 stars for order ' || pg_temp.num('cod'), 'a low rating is called out');
select ok(pg_temp.staff2_said('staff_feedback_low') like 'Box was dented → /admin/feedback/%', 'their words, linking to the feedback');
select pg_temp.staff2_news();
select pg_temp.asha();
select public.send_feedback('order', 5, 'Sorted at the store', pg_temp.id('cod'));
select is(pg_temp.staff2_news(), 'staff_feedback: New rating: 5 stars for order ' || pg_temp.num('cod'), 'a re-rating is news again');
select pg_temp.asha();
select public.send_feedback('repair', 1, '', p_repair_id => pg_temp.id('r1'));
select is(pg_temp.staff2_news(), 'staff_feedback_low: Low rating: 1 star for repair ' || pg_temp.num('r1'), 'repairs too');
select pg_temp.staff1();
update public.feedback set status = 'resolved';
reset role;
select is(concat(pg_temp.staff1_news(), pg_temp.staff2_news()), 'staff_feedback: New rating: 5 stars for order ' || pg_temp.num('cod')
  || ' / staff_feedback_low: Low rating: 1 star for repair ' || pg_temp.num('r1'), 'staff changing the status is not news');
select is(pg_temp.asha_news(), null, 'customers aren''t told about their own feedback');

-- RLS and the read RPCs ------------------------------------------------------------------------------

select pg_temp.ravi();
select is((select count(*)::int from public.notifications where user_id <> auth.uid()), 0, 'nobody reads anyone else''s');
select public.mark_notifications_read();
select pg_temp.ravi();
select public.mark_notifications_read((select array_agg(id) from public.notifications));
delete from public.notifications;
reset role;
select is((select count(*)::int from public.notifications where user_id = 'ab000000-0000-0000-0000-000000000001' and read_at is not null), 0,
  'nor marks them read');
select ok((select count(*) from public.notifications where user_id = 'ab000000-0000-0000-0000-000000000001') > 30, 'nor deletes them');
select is((select count(*)::int from public.notifications where user_id = 'ab000000-0000-0000-0000-000000000002'), 0, 'but your own, yes');

select pg_temp.asha();
select throws_ok($$insert into public.notifications (user_id, kind, title) values (auth.uid(), 'order_update', 'Free phone')$$,
  '42501', null, 'nobody inserts notifications');
select throws_ok($$update public.notifications set title = 'x'$$, '42501', null, 'only read_at can change');
select is(public.unread_notifications(), (select count(*)::int from public.notifications), 'unread count');
select pg_temp.keep('n1', (select id from public.notifications order by created_at limit 1));
select public.mark_notifications_read(array[pg_temp.id('n1')]);
select is(public.unread_notifications(), (select count(*)::int - 1 from public.notifications), 'marking one read');
select isnt((select read_at from public.notifications where id = pg_temp.id('n1')), null, 'sets read_at');
select public.mark_notifications_read();
select is(public.unread_notifications(), 0, 'null marks all read');
select lives_ok(format('delete from public.notifications where id = %L', pg_temp.id('n1')), 'delete your own');
select is((select count(*)::int from public.notifications where id = pg_temp.id('n1')), 0, 'gone');
reset role;
set local role anon;
select throws_ok('select public.unread_notifications()', '42501', null, 'signed out: no count');
select throws_ok('select count(*) from public.notifications', '42501', null, 'signed out: no rows');
reset role;

-- Device tokens -------------------------------------------------------------------------------------

select pg_temp.asha();
select throws_ok($$select public.register_device('short')$$, 'P0001', 'BAD_REQUEST', 'not an FCM token');
select lives_ok($$select public.register_device('ntTokenAAAAAAAAAAAAAAAAAAAA:APA91b-x_1')$$, 'register this phone');
select lives_ok($$select public.register_device('ntTokenAAAAAAAAAAAAAAAAAAAA:APA91b-x_1')$$, 'again on the next launch');
select is((select count(*)::int from public.device_tokens), 1, 'one row per phone');
select throws_ok($$insert into public.device_tokens (token, user_id) values ('ntTokenBBBBBBBBBBBBBBBBBBBBBB', auth.uid())$$,
  '42501', null, 'only through register_device');
select pg_temp.ravi();
select public.register_device('ntTokenAAAAAAAAAAAAAAAAAAAA:APA91b-x_1');
select is((select count(*)::int from public.device_tokens), 1, 'someone else signs in on that phone: it''s theirs');
select pg_temp.asha();
select is((select count(*)::int from public.device_tokens), 0, 'and no longer the first person''s');
reset role;
set local role anon;
select throws_ok($$select public.register_device('ntTokenAAAAAAAAAAAAAAAAAAAA:APA91b-x_1')$$, '42501', null, 'signed out: refused');
reset role;

-- Push: off until configured, and never failing what triggered it ---------------------------------------

create function pg_temp.pushes() returns bigint language sql as $$
  select count(*) from net.http_request_queue where url = 'http://127.0.0.1:54321/functions/v1/send-push' $$;
delete from vault.secrets where name in ('push_url', 'push_secret'); -- the local stack may have push set up
select lives_ok($$select private.notify('ab000000-0000-0000-0000-000000000002', 'order_update', 'Hello', 'Body', '/orders/x')$$,
  'a notification with push not set up');
select is(pg_temp.pushes(), 0::bigint, 'sends nothing');
select vault.create_secret('http://127.0.0.1:54321/functions/v1/send-push', 'push_url');
select vault.create_secret('test-push-secret', 'push_secret');
select private.notify('ab000000-0000-0000-0000-000000000001', 'order_update', 'No phone', 'Body', '/orders/x');
select is(pg_temp.pushes(), 0::bigint, 'nothing for someone with no phone');
select private.notify('ab000000-0000-0000-0000-000000000002', 'order_update', 'To the phone', 'Body', '/orders/x');
select is(pg_temp.pushes(), 1::bigint, 'set up: one request to send-push');
select is((select headers ->> 'x-push-secret' from net.http_request_queue order by id desc limit 1), 'test-push-secret', 'signed with the shared secret');
select is((select convert_from(body, 'UTF8')::jsonb -> 'tokens' from net.http_request_queue order by id desc limit 1),
  '["ntTokenAAAAAAAAAAAAAAAAAAAA:APA91b-x_1"]'::jsonb, 'to that user''s phones');
select vault.update_secret(id, 'not a url') from vault.secrets where name = 'push_url';
select lives_ok($$select private.notify('ab000000-0000-0000-0000-000000000002', 'order_update', 'Broken push', 'Body', '/orders/x')$$,
  'a failing push doesn''t fail the transaction');
select is((select count(*)::int from public.notifications where title = 'Broken push'), 1, 'the notification is still saved');

select is((select schedule from cron.job where jobname = 'notifications-cleanup'), '30 3 * * *', 'old notifications are pruned nightly');

select * from finish();
rollback;
