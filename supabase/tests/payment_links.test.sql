-- admin_new_payment_link / mark_link_paid / close_payment_link (20261030000510_payment_links.sql).
begin;
create extension if not exists pgtap with schema extensions;
select plan(33);

insert into auth.users (id, email) values
  ('7d000000-0000-0000-0000-000000000001', 'pl-asha@test.dev'),
  ('7d000000-0000-0000-0000-000000000003', 'pl-staff@test.dev');
insert into public.admins (user_id) values ('7d000000-0000-0000-0000-000000000003');
insert into public.categories (id, slug, name, kind) values ('7d0000c0-0000-0000-0000-000000000001', 'pl-cat', 'Pl cat', 'phone');
insert into public.brands (id, slug, name) values ('7d0000b0-0000-0000-0000-000000000001', 'pl-brand', 'Pl');
insert into public.products (id, slug, name, brand_id, category_id) values
  ('7d0000a0-0000-0000-0000-000000000001', 'pl-phone', 'Pl Phone', '7d0000b0-0000-0000-0000-000000000001', '7d0000c0-0000-0000-0000-000000000001');
insert into public.variants (id, product_id, sku, name, price_paise, mrp_paise, stock) values
  ('7d0000d0-0000-0000-0000-000000000001', '7d0000a0-0000-0000-0000-000000000001', 'PL-A', 'A', 40000, 40000, 5);

-- o1 online, awaiting payment; o2 cash on delivery; o3 already paid; o4 cash on delivery, cancelled
insert into public.orders (id, user_id, status, payment_method, payment_status, subtotal_paise, delivery_fee_paise, total_paise,
                           address, reserved_until, razorpay_payment_id) values
  ('7d0000e0-0000-0000-0000-000000000001', '7d000000-0000-0000-0000-000000000001', 'pending_payment', 'razorpay', 'failed', 40000, 4900, 44900,
   '{"name": "Asha Devi", "phone": "+919876543210"}', now() + interval '15 minutes', null),
  ('7d0000e0-0000-0000-0000-000000000002', '7d000000-0000-0000-0000-000000000001', 'confirmed', 'cod', 'pending', 40000, 0, 40000,
   '{"name": "Asha Devi", "phone": "+919876543210"}', null, null),
  ('7d0000e0-0000-0000-0000-000000000003', '7d000000-0000-0000-0000-000000000001', 'confirmed', 'razorpay', 'paid', 40000, 0, 40000,
   '{"name": "Asha Devi", "phone": "+919876543210"}', null, 'pay_pl3'),
  ('7d0000e0-0000-0000-0000-000000000004', '7d000000-0000-0000-0000-000000000001', 'cancelled', 'cod', 'pending', 40000, 0, 40000,
   '{"name": "Asha Devi", "phone": "+919876543210"}', null, null);
insert into public.order_items (order_id, variant_id, product_name, variant_name, unit_price_paise, qty, gst_rate)
select o, '7d0000d0-0000-0000-0000-000000000001', 'Pl Phone', 'A', 40000, 1, 18
from unnest(array['7d0000e0-0000-0000-0000-000000000001', '7d0000e0-0000-0000-0000-000000000002',
                  '7d0000e0-0000-0000-0000-000000000003', '7d0000e0-0000-0000-0000-000000000004']::uuid[]) o;

create function pg_temp.as_role(p_role text, p_uid uuid default null) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', p_role)::text, true);
  perform set_config('role', p_role, true);
end $$;
create function pg_temp.link(p_order text) returns json language sql as $$
  select public.admin_new_payment_link('7d000000-0000-0000-0000-000000000003', p_order::uuid) $$;
-- what create would store after Razorpay answers
create function pg_temp.issued(p_id uuid, p_rzp text) returns void language sql as $$
  update public.payment_links set razorpay_link_id = p_rzp, short_url = 'https://rzp.io/rzp/' || p_rzp where id = p_id $$;

select pg_temp.as_role('authenticated', '7d000000-0000-0000-0000-000000000003');
select throws_ok($$select pg_temp.link('7d0000e0-0000-0000-0000-000000000001')$$, '42501', null, 'not callable from the app');
select throws_ok($$select public.mark_link_paid('plink_x', 'pay_x', 100)$$, '42501', null, 'nor mark_link_paid');
select pg_temp.as_role('service_role');
select throws_ok($$select public.admin_new_payment_link('7d000000-0000-0000-0000-000000000001', '7d0000e0-0000-0000-0000-000000000001')$$,
  'P0001', 'FORBIDDEN', 'a customer id is refused');

-- Order links --------------------------------------------------------------------------------------------------------

select results_eq($$select (j ->> 'amount_paise')::int, j ->> 'customer_phone', j ->> 'customer_name', (j ->> 'reused')::boolean,
                    j ->> 'description' = 'Shyam Mobiles order ' || (select number from public.orders where id = '7d0000e0-0000-0000-0000-000000000001')
                  from pg_temp.link('7d0000e0-0000-0000-0000-000000000001') j$$,
  $$values (44900, '+919876543210', 'Asha Devi', false, true)$$, 'the order total, delivery name and phone, from the database');
select ok((select expires_at between now() + interval '71 hours' and now() + interval '73 hours' from public.payment_links
           where order_id = '7d0000e0-0000-0000-0000-000000000001'), 'valid for 3 days');
select is((pg_temp.link('7d0000e0-0000-0000-0000-000000000001') ->> 'reused')::boolean, true, 'asking again sends the open link');
select is((select count(*)::int from public.payment_links where order_id = '7d0000e0-0000-0000-0000-000000000001'), 1, '... no second link');
update public.payment_links set expires_at = now() - interval '1 minute' where order_id = '7d0000e0-0000-0000-0000-000000000001';
select is((pg_temp.link('7d0000e0-0000-0000-0000-000000000001') ->> 'reused')::boolean, false, 'a link whose time ran out is replaced');
select results_eq($$select status from public.payment_links where order_id = '7d0000e0-0000-0000-0000-000000000001' order by created_at, expires_at$$,
  $$values ('expired'), ('created')$$, '... and closed');
select throws_ok($$select pg_temp.link('7d0000e0-0000-0000-0000-000000000003')$$, 'P0001', 'LINK_NOT_ALLOWED', 'a paid order needs no link');
select throws_ok($$select pg_temp.link('7d0000e0-0000-0000-0000-000000000004')$$, 'P0001', 'LINK_NOT_ALLOWED', 'nor a cancelled one');
select throws_ok($$select pg_temp.link('7d0000e0-0000-0000-0000-0000000000ff')$$, 'P0001', 'NOT_FOUND', 'unknown order');

-- Custom amounts -----------------------------------------------------------------------------------------------------

select throws_ok($$select public.admin_new_payment_link('7d000000-0000-0000-0000-000000000003', null, 500000, '+919876543210', null, '  ')$$,
  'P0001', 'BAD_REQUEST', 'says what it is for');
select throws_ok($$select public.admin_new_payment_link('7d000000-0000-0000-0000-000000000003', null, 500000, '98765 43210', null, 'Bulk order')$$,
  '23514', null, 'an Indian mobile number in +91 form');
select throws_ok($$select public.admin_new_payment_link('7d000000-0000-0000-0000-000000000003', null, 99, '+919876543210', null, 'Bulk order')$$,
  '23514', null, 'at least ₹1');
select is((public.admin_new_payment_link('7d000000-0000-0000-0000-000000000003', null, 2500000, '+919812345678', ' Ravi Traders ',
            '10 × Redmi 13C, wholesale') ->> 'customer_name'), 'Ravi Traders', 'a wholesale link for ₹25,000');
select pg_temp.issued(id, 'plink_custom') from public.payment_links where order_id is null;

-- Paying ---------------------------------------------------------------------------------------------------------------

select pg_temp.issued(id, 'plink_o1') from public.payment_links where order_id = '7d0000e0-0000-0000-0000-000000000001' and status = 'created';
select throws_ok($$select public.mark_link_paid('plink_nope', 'pay_x', 44900)$$, 'P0001', 'NOT_FOUND', 'unknown link');
select throws_ok($$select public.mark_link_paid('plink_o1', 'pay_x', 44800)$$, 'P0001', 'AMOUNT_MISMATCH', 'the amount must be the link''s');
select lives_ok($$select public.mark_link_paid('plink_o1', 'pay_pl1', 44900)$$, 'an online order paid by link');
select results_eq($$select status::text, payment_status::text, razorpay_payment_id from public.orders where id = '7d0000e0-0000-0000-0000-000000000001'$$,
  $$values ('confirmed', 'paid', 'pay_pl1')$$, '... is confirmed, as mark_order_paid does');
select lives_ok($$select public.mark_link_paid('plink_o1', 'pay_pl1', 44900)$$, 'a replay is harmless');
select is((select count(*)::int from public.order_events where order_id = '7d0000e0-0000-0000-0000-000000000001' and note = 'Payment received'), 1, '... one event');

select public.admin_new_payment_link('7d000000-0000-0000-0000-000000000003', '7d0000e0-0000-0000-0000-000000000002');
select pg_temp.issued(id, 'plink_o2') from public.payment_links where order_id = '7d0000e0-0000-0000-0000-000000000002';
select lives_ok($$select public.mark_link_paid('plink_o2', 'pay_pl2', 40000)$$, 'cash on delivery, paid ahead by link');
select results_eq($$select status::text, payment_method::text, payment_status::text from public.orders where id = '7d0000e0-0000-0000-0000-000000000002'$$,
  $$values ('confirmed', 'razorpay', 'paid')$$, '... is paid online now (nothing to collect at the door)');
select is((select note from public.order_events where order_id = '7d0000e0-0000-0000-0000-000000000002' order by id desc limit 1),
  'Paid online with a payment link.', '... and the timeline says so');

-- a second link payment for an order already paid: left alone, staff refund it
insert into public.payment_links (order_id, amount_paise, description, customer_phone, expires_at, razorpay_link_id)
values ('7d0000e0-0000-0000-0000-000000000003', 40000, 'Old link', '+919876543210', now() + interval '1 day', 'plink_o3');
select lives_ok($$select public.mark_link_paid('plink_o3', 'pay_pl3b', 40000)$$, 'a second payment');
select is((select razorpay_payment_id from public.orders where id = '7d0000e0-0000-0000-0000-000000000003'), 'pay_pl3', '... keeps the first payment');
select ok(exists (select 1 from public.notifications where user_id = '7d000000-0000-0000-0000-000000000003'
                  and kind = 'staff_refund_needed' and body like '%pay_pl3b%'), '... staff are told to refund it');

select lives_ok($$select public.mark_link_paid('plink_custom', 'pay_plc', 2500000)$$, 'the wholesale link is paid');
select ok(exists (select 1 from public.notifications where user_id = '7d000000-0000-0000-0000-000000000003'
                  and kind = 'staff_link_paid' and title = '₹25,000 paid by payment link'), '... staff are told');

-- Closing ---------------------------------------------------------------------------------------------------------------

select public.close_payment_link('plink_custom', 'cancelled');
select is((select status from public.payment_links where razorpay_link_id = 'plink_custom'), 'paid', 'a paid link never closes');

-- Who sees links ------------------------------------------------------------------------------------------------------

select pg_temp.as_role('authenticated', '7d000000-0000-0000-0000-000000000001');
select is((select count(*)::int from public.payment_links), 0, 'customers don''t see links');
select pg_temp.as_role('authenticated', '7d000000-0000-0000-0000-000000000003');
select is((select count(*)::int from public.payment_links where created_by = '7d000000-0000-0000-0000-000000000003'), 4, 'staff see them');

reset role;
select * from finish();
rollback;
