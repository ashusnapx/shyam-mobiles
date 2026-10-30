-- Staff close a "needs refund" order (a paid order that was cancelled) when the refund webhook doesn't.
begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

insert into auth.users (id, email) values
  ('7e000000-0000-0000-0000-000000000001', 'rb-asha@test.dev'),
  ('7e000000-0000-0000-0000-000000000003', 'rb-staff@test.dev');
insert into public.admins (user_id) values ('7e000000-0000-0000-0000-000000000003');
insert into public.orders (id, user_id, status, payment_method, payment_status, subtotal_paise, delivery_fee_paise, total_paise, address) values
  ('7e0000aa-0000-0000-0000-000000000001', '7e000000-0000-0000-0000-000000000001', 'cancelled', 'razorpay', 'paid', 100000, 0, 100000, '{}'),
  ('7e0000aa-0000-0000-0000-000000000002', '7e000000-0000-0000-0000-000000000001', 'cancelled', 'razorpay', 'pending', 100000, 0, 100000, '{}');

create function pg_temp.as_user(p uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;

select pg_temp.as_user('7e000000-0000-0000-0000-000000000001');
select throws_ok($$select public.admin_update_order('7e0000aa-0000-0000-0000-000000000001', 'refunded')$$, 'P0001', 'FORBIDDEN', 'customers cannot mark refunds');
select pg_temp.as_user('7e000000-0000-0000-0000-000000000003');
select throws_ok($$select public.admin_update_order('7e0000aa-0000-0000-0000-000000000002', 'refunded')$$, 'P0001', 'INVALID_TRANSITION', 'nothing to refund on an unpaid cancel');
select lives_ok($$select public.admin_update_order('7e0000aa-0000-0000-0000-000000000001', 'refunded')$$, 'staff mark the refund');
select results_eq($$select status::text, payment_status::text from public.orders where id = '7e0000aa-0000-0000-0000-000000000001'$$,
  $$values ('cancelled', 'refunded')$$, 'still cancelled (its coupon use stays given back), now refunded');
select is((select note from public.order_events where order_id = '7e0000aa-0000-0000-0000-000000000001' order by id desc limit 1),
  'Refund issued. Banks usually take 5–7 working days to show it.', 'the customer is told');
select is((select count(*)::int from public.orders where status = 'cancelled' and payment_status = 'paid'
           and id = '7e0000aa-0000-0000-0000-000000000001'), 0, 'off the needs-refund list');
select throws_ok($$select public.admin_update_order('7e0000aa-0000-0000-0000-000000000001', 'refunded')$$, 'P0001', 'INVALID_TRANSITION', 'not twice');

reset role;
select * from finish();
rollback;
