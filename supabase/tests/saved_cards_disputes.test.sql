-- razorpay_customers and record_dispute (20261030000520_saved_cards_disputes.sql).
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

insert into auth.users (id, email) values
  ('7c000000-0000-0000-0000-000000000001', 'sd-asha@test.dev'),
  ('7c000000-0000-0000-0000-000000000003', 'sd-staff@test.dev');
insert into public.admins (user_id) values ('7c000000-0000-0000-0000-000000000003');
insert into public.orders (id, user_id, status, payment_method, payment_status, subtotal_paise, delivery_fee_paise, total_paise,
                           address, razorpay_payment_id) values
  ('7c0000e0-0000-0000-0000-000000000001', '7c000000-0000-0000-0000-000000000001', 'delivered', 'razorpay', 'paid', 2499900, 0, 2499900, '{}', 'pay_sd1');
insert into public.razorpay_customers (user_id, customer_id) values ('7c000000-0000-0000-0000-000000000001', 'cust_SD1');

create function pg_temp.as_role(p_role text, p_uid uuid default null) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', p_role)::text, true);
  perform set_config('role', p_role, true);
end $$;

-- Saved cards: server only, gone with the account ----------------------------------------------------------------------

select pg_temp.as_role('authenticated', '7c000000-0000-0000-0000-000000000001');
select throws_ok($$select customer_id from public.razorpay_customers$$, '42501', null, 'not even the account itself reads its customer id');
select throws_ok($$insert into public.razorpay_customers values ('7c000000-0000-0000-0000-000000000001', 'cust_EVIL')$$, '42501', null, 'nor writes one');
select pg_temp.as_role('anon');
select throws_ok($$select customer_id from public.razorpay_customers$$, '42501', null, 'anon neither');
reset role;
select throws_ok($$insert into public.razorpay_customers values ('7c000000-0000-0000-0000-000000000003', 'cust_SD1')$$,
  '23505', null, 'one Razorpay customer never serves two accounts');
select throws_ok($$insert into public.razorpay_customers values ('7c000000-0000-0000-0000-000000000003', 'not_a_customer')$$,
  '23514', null, 'only a cust_ id');
delete from auth.users where id = '7c000000-0000-0000-0000-000000000001'; -- what delete-account does last
select is((select count(*)::int from public.razorpay_customers), 0, 'deleting the account forgets its Razorpay customer');

-- Disputes ----------------------------------------------------------------------------------------------------------------

select pg_temp.as_role('authenticated', '7c000000-0000-0000-0000-000000000003');
select throws_ok($$select public.record_dispute('disp_1', 'pay_sd1', 2499900, 'open', 'chargeback', 'fraud', 'Card not present fraud', now())$$,
  '42501', null, 'only the webhook records disputes');
select pg_temp.as_role('service_role');
select lives_ok($$select public.record_dispute('disp_1', 'pay_sd1', 2499900, 'open', 'chargeback', 'fraudulent', 'Customer says they didn''t buy it',
                  '2026-11-06 18:29:00+00')$$, 'payment.dispute.created');
select results_eq($$select order_id, status, amount_paise from public.disputes where id = 'disp_1'$$,
  $$values ('7c0000e0-0000-0000-0000-000000000001'::uuid, 'open', 2499900)$$, 'linked to its order by the payment');
select is((select title from public.notifications where user_id = '7c000000-0000-0000-0000-000000000003' and kind = 'staff_dispute'
           order by created_at desc limit 1),
  'Dispute on ' || (select number from public.orders where id = '7c0000e0-0000-0000-0000-000000000001') || ': reply by 6 Nov',
  'staff get the respond-by date (IST)');
select is((select body from public.notifications where kind = 'staff_dispute' order by created_at desc limit 1),
  '₹24,999 · Customer says they didn''t buy it · Answer with the invoice, IMEI and delivery proof in the Razorpay dashboard.',
  'with the amount, reason and what to do');
select lives_ok($$select public.record_dispute('disp_1', 'pay_sd1', 2499900, 'won', null, null, null, null)$$, 'payment.dispute.won');
select results_eq($$select status, phase, reason is not null from public.disputes where id = 'disp_1'$$,
  $$values ('won', 'chargeback', true)$$, 'status moves on, earlier details stay');
select lives_ok($$select public.record_dispute('disp_2', 'pay_unknown', 100, 'open', null, null, null, null)$$,
  'a dispute on a payment the shop can''t match is still recorded');

reset role;
select * from finish();
rollback;
