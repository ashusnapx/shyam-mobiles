-- mark_order_paid / mark_payment_failed / mark_order_refunded / expire_unpaid_orders + cron job.
begin;
create extension if not exists pgtap with schema extensions;
select plan(50);

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
create function tests.id(p_name text) returns uuid language sql as $$ select current_setting('tests.' || p_name)::uuid $$;
create function tests.keep(p_name text, p_id uuid) returns uuid language sql as $$ select set_config('tests.' || p_name, p_id::text, true)::uuid $$;
create function tests.stock() returns int language sql security definer set search_path = '' as $$
  select stock from public.variants where sku = 'T-PAY' $$;
-- places an order from a fresh one-line cart as p_who
create function tests.order_as(p_who text, p_qty int, p_method public.payment_method) returns uuid language plpgsql as $$
begin
  perform tests.login(p_who);
  insert into public.cart_items (user_id, variant_id, qty) values (auth.uid(), 'd0000000-0000-0000-0000-000000000001', p_qty);
  return public.place_order((select id from public.addresses where user_id = auth.uid()), p_method);
end $$;
create function tests.order_row(p_name text) returns table (status text, payment_status text, razorpay_payment_id text)
language sql security definer set search_path = '' as $$
  select status::text, payment_status::text, razorpay_payment_id from public.orders where id = tests.id(p_name) $$;
grant execute on all functions in schema tests to anon, authenticated, service_role;

-- Fixtures ------------------------------------------------------------------

delete from public.orders;
update public.store_settings set cod_enabled = true, cod_max_paise = 2500000;
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.dev'),
  ('33333333-3333-3333-3333-333333333333', 'staff@test.dev');
insert into public.admins (user_id) values ('33333333-3333-3333-3333-333333333333');
insert into public.categories (id, slug, name, kind) values ('c0000000-0000-0000-0000-000000000001', 'test-cat', 'Test cat', 'phone');
insert into public.brands (id, slug, name) values ('b0000000-0000-0000-0000-000000000001', 'test-brand', 'Test');
insert into public.products (id, slug, name, brand_id, category_id) values
  ('a0000000-0000-0000-0000-000000000001', 'test-phone', 'Test Phone', 'b0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001');
insert into public.variants (id, product_id, sku, name, price_paise, mrp_paise, stock) values
  ('d0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'T-PAY', '8 GB', 50000, 50000, 5);
insert into public.addresses (user_id, name, phone, line1, city, state, pincode) values
  ('11111111-1111-1111-1111-111111111111', 'Alice', '+919876543210', '1 MG Road', 'Patna', 'Bihar', '800001'),
  ('22222222-2222-2222-2222-222222222222', 'Bob', '+919876543211', '2 MG Road', 'Patna', 'Bihar', '800001');

-- Only service_role may call payment functions ------------------------------

select tests.keep('o1', tests.order_as('alice', 1, 'razorpay'));
select throws_ok(format($$select public.mark_order_paid(%L, 'pay_x')$$, tests.id('o1')), '42501', null, 'customers cannot mark orders paid');
select throws_ok(format($$select public.mark_payment_failed(%L)$$, tests.id('o1')), '42501', null, 'customers cannot mark payments failed');
select throws_ok($$select public.mark_order_refunded('pay_x')$$, '42501', null, 'customers cannot mark refunds');
select throws_ok('select public.expire_unpaid_orders()', '42501', null, 'customers cannot run expiry');
select tests.login('staff');
select throws_ok(format($$select public.mark_order_paid(%L, 'pay_x')$$, tests.id('o1')), '42501', null, 'admins cannot mark orders paid either');
select tests.login('anon');
select throws_ok(format($$select public.mark_order_paid(%L, 'pay_x')$$, tests.id('o1')), '42501', null, 'anon cannot mark orders paid');

-- Paid on time, idempotent --------------------------------------------------

select tests.login('service');
select lives_ok(format($$select public.mark_payment_failed(%L)$$, tests.id('o1')), 'payment.failed recorded');
select results_eq($$select * from tests.order_row('o1')$$, $$values ('pending_payment', 'failed', null::text)$$, 'failed payment keeps the order payable');
select lives_ok(format($$select public.mark_order_paid(%L, 'pay_1')$$, tests.id('o1')), 'retry succeeds');
select results_eq($$select * from tests.order_row('o1')$$, $$values ('confirmed', 'paid', 'pay_1')$$, 'order confirmed and paid');
select is((select reserved_until from public.orders where id = tests.id('o1')), null, 'reservation cleared');
select lives_ok(format($$select public.mark_order_paid(%L, 'pay_1')$$, tests.id('o1')), 'second call is fine');
select lives_ok(format($$select public.mark_order_paid(%L, 'pay_other')$$, tests.id('o1')), 'call with another payment id is fine');
select results_eq($$select * from tests.order_row('o1')$$, $$values ('confirmed', 'paid', 'pay_1')$$, 'nothing changed');
select is((select count(*)::int from public.order_events where order_id = tests.id('o1')), 2, 'no duplicate events');
select lives_ok(format($$select public.mark_payment_failed(%L)$$, tests.id('o1')), 'late payment.failed is harmless');
select results_eq($$select * from tests.order_row('o1')$$, $$values ('confirmed', 'paid', 'pay_1')$$, 'still paid');
select is(tests.stock(), 4, 'stock taken once');
select throws_ok($$select public.mark_order_paid(gen_random_uuid(), 'pay_9')$$, 'P0001', 'NOT_FOUND', 'unknown order');

reset role;
select tests.keep('cod', tests.order_as('bob', 1, 'cod'));
select tests.login('service');
select throws_ok(format($$select public.mark_order_paid(%L, 'pay_cod')$$, tests.id('cod')), 'P0001', 'INVALID_TRANSITION', 'COD orders are not paid online');
-- stock now 3

-- Expiry ----------------------------------------------------------------------

reset role;
select tests.keep('o2', tests.order_as('alice', 1, 'razorpay'));
select tests.keep('o3', tests.order_as('alice', 1, 'razorpay'));
reset role;
update public.orders set reserved_until = now() - interval '1 minute' where id = tests.id('o2');
select is(tests.stock(), 1, 'two unpaid orders hold stock');
select tests.login('service');
select is(public.expire_unpaid_orders(), 1, 'one order expired');
select is((select status::text from public.orders where id = tests.id('o2')), 'cancelled', 'expired order cancelled');
select is((select status::text from public.orders where id = tests.id('o3')), 'pending_payment', 'unexpired order untouched');
select is(tests.stock(), 2, 'expiry releases stock');
select is((select note from public.order_events where order_id = tests.id('o2') order by id desc limit 1), 'Payment not received in time', 'expiry event');

-- Late payment, stock still there: order revived
select lives_ok(format($$select public.mark_order_paid(%L, 'pay_2')$$, tests.id('o2')), 'late payment accepted');
select results_eq($$select * from tests.order_row('o2')$$, $$values ('confirmed', 'paid', 'pay_2')$$, 'expired order revived');
select is(tests.stock(), 1, 'stock re-reserved');

-- Late payment, stock gone: cancelled + paid = needs refund
reset role;
update public.orders set reserved_until = now() - interval '1 minute' where id = tests.id('o3');
select tests.login('service');
select is(public.expire_unpaid_orders(), 1, 'second expiry');
reset role;
select tests.keep('bob2', tests.order_as('bob', 2, 'cod'));
select is(tests.stock(), 0, 'bob bought the rest');
select tests.login('service');
select lives_ok(format($$select public.mark_order_paid(%L, 'pay_3')$$, tests.id('o3')), 'late payment without stock accepted');
select results_eq($$select * from tests.order_row('o3')$$, $$values ('cancelled', 'paid', 'pay_3')$$, 'stays cancelled but paid');
select is(tests.stock(), 0, 'stock never goes negative');

-- Customer-cancelled, then paid: never revived even with stock
reset role;
update public.variants set stock = 1 where sku = 'T-PAY';
select tests.keep('o4', tests.order_as('alice', 1, 'razorpay'));
select public.cancel_order(tests.id('o4'));
select tests.login('service');
select lives_ok(format($$select public.mark_order_paid(%L, 'pay_4')$$, tests.id('o4')), 'payment after customer cancel accepted');
select results_eq($$select * from tests.order_row('o4')$$, $$values ('cancelled', 'paid', 'pay_4')$$, 'customer-cancelled order not revived');
select is(tests.stock(), 1, 'stock untouched');

select tests.login('staff');
select is((public.admin_dashboard() ->> 'needs_refund')::int, 2, 'dashboard lists both as needs refund');

-- Refunds ---------------------------------------------------------------------

select tests.login('service');
select lives_ok($$select public.mark_order_refunded('pay_3')$$, 'refund.processed recorded');
select lives_ok($$select public.mark_order_refunded('pay_3')$$, 'refund is idempotent');
select results_eq($$select * from tests.order_row('o3')$$, $$values ('cancelled', 'refunded', 'pay_3')$$, 'payment refunded');
select throws_ok($$select public.mark_order_refunded('pay_unknown')$$, 'P0001', 'NOT_FOUND', 'unknown payment');
select tests.login('staff');
select is((public.admin_dashboard() ->> 'needs_refund')::int, 1, 'refunded order leaves the needs-refund list');

-- Customer cancels a paid order: the timeline promises the refund ------------

select tests.login('alice');
select lives_ok(format('select public.cancel_order(%L)', tests.id('o1')), 'alice cancels her paid order');
select results_eq($$select * from tests.order_row('o1')$$, $$values ('cancelled', 'paid', 'pay_1')$$, 'paid cancel keeps payment for refund');
select matches((select note from public.order_events where order_id = tests.id('o1') order by id desc limit 1),
  '^Cancelled by you\. A full refund', 'paid cancel event tells the customer a refund is coming');
select tests.login('service');
select lives_ok($$select public.mark_order_refunded('pay_1')$$, 'refund for the paid cancel');
select matches((select note from public.order_events where order_id = tests.id('o1') order by id desc limit 1),
  '^Refund issued', 'refund event is customer-facing');

-- Cron --------------------------------------------------------------------------

reset role;
select results_eq($$select schedule, command from cron.job where jobname = 'expire-unpaid-orders'$$,
  $$values ('*/5 * * * *', 'select public.expire_unpaid_orders()')$$, 'expiry runs every 5 minutes');
select is((select schedule from cron.job where jobname = 'job-run-details-cleanup'), '0 3 * * *', 'cron run log is pruned nightly');

select * from finish();
rollback;
