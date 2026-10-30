-- admin_start_refund / settle_refund (20261030000500_refunds.sql): amounts from the order rows, one refund in
-- flight per order, per-line flags, restock on processed, full refund -> refunded, failures free the lines.
begin;
create extension if not exists pgtap with schema extensions;
select plan(41);

insert into auth.users (id, email) values
  ('7f000000-0000-0000-0000-000000000001', 'rf-asha@test.dev'),
  ('7f000000-0000-0000-0000-000000000002', 'rf-bina@test.dev'),
  ('7f000000-0000-0000-0000-000000000003', 'rf-staff@test.dev');
insert into public.admins (user_id) values ('7f000000-0000-0000-0000-000000000003');
insert into public.categories (id, slug, name, kind) values ('7f0000c0-0000-0000-0000-000000000001', 'rf-cat', 'Rf cat', 'phone');
insert into public.brands (id, slug, name) values ('7f0000b0-0000-0000-0000-000000000001', 'rf-brand', 'Rf');
insert into public.products (id, slug, name, brand_id, category_id) values
  ('7f0000a0-0000-0000-0000-000000000001', 'rf-phone', 'Rf Phone', '7f0000b0-0000-0000-0000-000000000001', '7f0000c0-0000-0000-0000-000000000001');
insert into public.variants (id, product_id, sku, name, price_paise, mrp_paise, stock) values
  ('7f0000d0-0000-0000-0000-000000000001', '7f0000a0-0000-0000-0000-000000000001', 'RF-A', 'A', 30000, 30000, 5),
  ('7f0000d0-0000-0000-0000-000000000002', '7f0000a0-0000-0000-0000-000000000001', 'RF-B', 'B', 40000, 40000, 5);

-- o1: delivered, paid online: line A 2 × ₹300 with ₹50 off, line B ₹400, delivery ₹49 -> ₹999
-- o2: confirmed and paid; o3: cash on delivery, unpaid; o4: cancelled and paid (needs refund)
insert into public.orders (id, user_id, status, payment_method, payment_status, subtotal_paise, delivery_fee_paise,
                           discount_paise, total_paise, address, razorpay_payment_id) values
  ('7f0000e0-0000-0000-0000-000000000001', '7f000000-0000-0000-0000-000000000001', 'delivered', 'razorpay', 'paid', 100000, 4900, 5000, 99900, '{}', 'pay_rf1'),
  ('7f0000e0-0000-0000-0000-000000000002', '7f000000-0000-0000-0000-000000000001', 'confirmed', 'razorpay', 'paid', 40000, 0, 0, 40000, '{}', 'pay_rf2'),
  ('7f0000e0-0000-0000-0000-000000000003', '7f000000-0000-0000-0000-000000000001', 'confirmed', 'cod', 'pending', 40000, 0, 0, 40000, '{}', null),
  ('7f0000e0-0000-0000-0000-000000000004', '7f000000-0000-0000-0000-000000000001', 'cancelled', 'razorpay', 'paid', 40000, 0, 0, 40000, '{}', 'pay_rf4');
insert into public.order_items (id, order_id, variant_id, product_name, variant_name, unit_price_paise, qty, gst_rate, discount_paise) values
  ('7f0000f0-0000-0000-0000-000000000001', '7f0000e0-0000-0000-0000-000000000001', '7f0000d0-0000-0000-0000-000000000001', 'Phone A', 'A', 30000, 2, 18, 5000),
  ('7f0000f0-0000-0000-0000-000000000002', '7f0000e0-0000-0000-0000-000000000001', '7f0000d0-0000-0000-0000-000000000002', 'Phone B', 'B', 40000, 1, 18, 0),
  ('7f0000f0-0000-0000-0000-000000000003', '7f0000e0-0000-0000-0000-000000000002', '7f0000d0-0000-0000-0000-000000000002', 'Phone B', 'B', 40000, 1, 18, 0),
  ('7f0000f0-0000-0000-0000-000000000004', '7f0000e0-0000-0000-0000-000000000004', '7f0000d0-0000-0000-0000-000000000002', 'Phone B', 'B', 40000, 1, 18, 0);

create function pg_temp.as_role(p_role text, p_uid uuid default null) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', p_role)::text, true);
  perform set_config('role', p_role, true);
end $$;
create function pg_temp.start(p_order text, p_items uuid[] default null, p_restock boolean default false,
  p_instant boolean default false) returns json language sql as $$
  select public.admin_start_refund('7f000000-0000-0000-0000-000000000003', p_order::uuid, p_items, p_restock, p_instant) $$;
create function pg_temp.stock(p_sku text) returns int language sql as $$ select stock from public.variants where sku = p_sku $$;
create function pg_temp.last_note(p_order text) returns text language sql as $$
  select note from public.order_events where order_id = p_order::uuid order by id desc limit 1 $$;

-- Who may call ---------------------------------------------------------------------------------------------------

select pg_temp.as_role('authenticated', '7f000000-0000-0000-0000-000000000003');
select throws_ok($$select pg_temp.start('7f0000e0-0000-0000-0000-000000000001')$$, '42501', null, 'not even staff call it from the app');
select throws_ok($$select public.settle_refund(gen_random_uuid(), 'rfnd_x', 'processed')$$, '42501', null, 'nor settle_refund');
select pg_temp.as_role('service_role');
select throws_ok($$select public.admin_start_refund('7f000000-0000-0000-0000-000000000001', '7f0000e0-0000-0000-0000-000000000001')$$,
  'P0001', 'FORBIDDEN', 'the function passes a staff id: a customer id is refused');
select throws_ok($$select public.admin_start_refund(null, '7f0000e0-0000-0000-0000-000000000001')$$, 'P0001', 'FORBIDDEN', 'no id, no refund');
select throws_ok($$select pg_temp.start('7f0000e0-0000-0000-0000-0000000000ff')$$, 'P0001', 'NOT_FOUND', 'unknown order');
select throws_ok($$select pg_temp.start('7f0000e0-0000-0000-0000-000000000003')$$, 'P0001', 'REFUND_NOT_ALLOWED', 'cash on delivery, unpaid');
select throws_ok($$select pg_temp.start('7f0000e0-0000-0000-0000-000000000002')$$, 'P0001', 'REFUND_NOT_ALLOWED',
  'an order still being fulfilled is cancelled before a full refund');
select throws_ok($$select pg_temp.start('7f0000e0-0000-0000-0000-000000000004', array['7f0000f0-0000-0000-0000-000000000004']::uuid[])$$,
  'P0001', 'REFUND_NOT_ALLOWED', 'a cancelled order is refunded in full, not by item');
select throws_ok($$select pg_temp.start('7f0000e0-0000-0000-0000-000000000001', array['7f0000f0-0000-0000-0000-000000000003']::uuid[])$$,
  'P0001', 'BAD_REQUEST', 'a line of another order');

-- Partial refund of line A ---------------------------------------------------------------------------------------

select is((pg_temp.start('7f0000e0-0000-0000-0000-000000000001', array['7f0000f0-0000-0000-0000-000000000001']::uuid[], true) ->> 'amount_paise')::int,
  55000, 'line A at what was paid: 2 × ₹300 − ₹50 off');
select is((select refund_id from public.order_items where id = '7f0000f0-0000-0000-0000-000000000001'),
  (select id from public.refunds where order_id = '7f0000e0-0000-0000-0000-000000000001'), 'the line points at its refund');
select is((select payment_id from json_to_record(pg_temp.start('7f0000e0-0000-0000-0000-000000000001')) as x(payment_id text, retry boolean) where retry),
  'pay_rf1', 'while Razorpay never answered, any new request retries that same refund');
select is((select count(*)::int from public.refunds where order_id = '7f0000e0-0000-0000-0000-000000000001'), 1, '... no second row');
select is(public.settle_refund((select id from public.refunds where order_id = '7f0000e0-0000-0000-0000-000000000001'), 'rfnd_rf1', 'pending'),
  'pending', 'Razorpay took it: pending with its id');
select throws_ok($$select pg_temp.start('7f0000e0-0000-0000-0000-000000000001')$$, 'P0001', 'REFUND_IN_PROGRESS', 'one refund in flight per order');
select is(pg_temp.stock('RF-A'), 5, 'nothing restocked before it is processed');
select is(public.settle_refund(null, 'rfnd_rf1', 'processed', 'normal'), 'processed', 'refund.processed finds it by Razorpay id');
select is(pg_temp.stock('RF-A'), 7, 'staff chose restock: 2 back');
select results_eq($$select status::text, payment_status::text from public.orders where id = '7f0000e0-0000-0000-0000-000000000001'$$,
  $$values ('delivered', 'paid')$$, 'a partial refund leaves the order as it was');
select is(pg_temp.last_note('7f0000e0-0000-0000-0000-000000000001'),
  'Refund of ₹550 for Phone A issued to your original payment method. Banks usually take 5–7 working days to show it.', 'the timeline says what');
select is((select title from public.notifications where user_id = '7f000000-0000-0000-0000-000000000001' and kind = 'order_refunded'
           order by created_at desc limit 1), 'Refund of ₹550 for ' || (select number from public.orders where id = '7f0000e0-0000-0000-0000-000000000001'),
  'the customer is told');
select is(public.settle_refund(null, 'rfnd_rf1', 'processed'), 'processed', 'a replayed processed event is harmless');
select is(pg_temp.stock('RF-A'), 7, '... no second restock');
select throws_ok($$select pg_temp.start('7f0000e0-0000-0000-0000-000000000001', array['7f0000f0-0000-0000-0000-000000000001']::uuid[])$$,
  'P0001', 'BAD_REQUEST', 'a refunded line can’t be refunded again');

-- The rest: a failure frees the line, then an instant full refund ------------------------------------------------

select is((pg_temp.start('7f0000e0-0000-0000-0000-000000000001') ->> 'amount_paise')::int, 44900, 'full = ₹999 − ₹550 already back');
select is((select refund_id is not null from public.order_items where id = '7f0000f0-0000-0000-0000-000000000002'), true, 'line B flagged');
select is(public.settle_refund((select id from public.refunds where order_id = '7f0000e0-0000-0000-0000-000000000001' and status = 'pending'),
  null, 'failed', null, 'Your account does not have enough balance to carry out the refund operation.'), 'failed', 'refused by Razorpay');
select is((select refund_id from public.order_items where id = '7f0000f0-0000-0000-0000-000000000002'), null, 'line B is free again');
select ok(exists (select 1 from public.notifications where user_id = '7f000000-0000-0000-0000-000000000003' and kind = 'staff_refund_failed'
                  and body like '₹449: Your account does not have enough balance%'), 'staff are told why');
select is(public.settle_refund((select id from public.refunds where status = 'failed' and order_id = '7f0000e0-0000-0000-0000-000000000001'),
  'rfnd_late', 'processed'), 'failed', 'a settled refund stays settled');
select is((pg_temp.start('7f0000e0-0000-0000-0000-000000000001', null, false, true) ->> 'amount_paise')::int, 44900, 'staff try again, instant');
select is(public.settle_refund((select id from public.refunds where order_id = '7f0000e0-0000-0000-0000-000000000001' and status = 'pending'),
  'rfnd_rf3', 'processed', 'instant'), 'processed', 'instant refund processed');
select results_eq($$select status::text, payment_status::text from public.orders where id = '7f0000e0-0000-0000-0000-000000000001'$$,
  $$values ('refunded', 'refunded')$$, 'all of it back: refunded');
select is(pg_temp.last_note('7f0000e0-0000-0000-0000-000000000001'),
  'Refund of ₹449 sent instantly. It should show in your account within minutes.', 'instant copy');
select is(pg_temp.stock('RF-B'), 5, 'no restock unless staff ask');
select throws_ok($$select pg_temp.start('7f0000e0-0000-0000-0000-000000000001')$$, 'P0001', 'REFUND_NOT_ALLOWED', 'nothing left');

-- A cancelled, paid order: full only, never restocked twice ------------------------------------------------------

select is((pg_temp.start('7f0000e0-0000-0000-0000-000000000004', null, true) ->> 'amount_paise')::int, 40000, 'needs refund: all of it');
select is((select restock from public.refunds where order_id = '7f0000e0-0000-0000-0000-000000000004'), false, 'the cancel already restocked');

-- Who sees refunds ------------------------------------------------------------------------------------------------

select pg_temp.as_role('authenticated', '7f000000-0000-0000-0000-000000000001');
select is((select count(*)::int from public.refunds), 4, 'the customer sees refunds on her orders');
select pg_temp.as_role('authenticated', '7f000000-0000-0000-0000-000000000002');
select is((select count(*)::int from public.refunds), 0, 'nobody else does');
select throws_ok($$insert into public.refunds (order_id, amount_paise, full_refund) values ('7f0000e0-0000-0000-0000-000000000002', 100, true)$$,
  '42501', null, 'no client writes');

reset role;
select * from finish();
rollback;
