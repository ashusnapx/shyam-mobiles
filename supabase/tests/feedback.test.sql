-- Feedback: ownership, one rating per order/repair, the daily cap, and who can read or change what.
begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

insert into auth.users (id, email) values
  ('fb000000-0000-0000-0000-000000000001', 'fb-amit@test.dev'),
  ('fb000000-0000-0000-0000-000000000002', 'fb-neha@test.dev'),
  ('fb000000-0000-0000-0000-000000000003', 'fb-staff@test.dev');
insert into public.admins (user_id) values ('fb000000-0000-0000-0000-000000000003');
insert into public.orders (id, user_id, status, payment_method, subtotal_paise, delivery_fee_paise, total_paise, address)
values ('fb0000aa-0000-0000-0000-000000000001', 'fb000000-0000-0000-0000-000000000001', 'delivered', 'cod', 100000, 0,
        100000, '{}');
insert into public.repair_bookings (id, user_id, device_brand, device_model, issue, preferred_date, slot, contact_phone)
values ('fb0000bb-0000-0000-0000-000000000001', 'fb000000-0000-0000-0000-000000000001', 'Samsung', 'Galaxy A56',
        'screen', current_date + 1, 'morning', '+919876543210');

create function pg_temp.as_user(p uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;

select pg_temp.as_user('fb000000-0000-0000-0000-000000000001');
select lives_ok($$ select public.send_feedback('order', 5, 'Fast delivery', 'fb0000aa-0000-0000-0000-000000000001') $$,
  'rate your own order');
select lives_ok($$ select public.send_feedback('order', 3, 'Box was dented', 'fb0000aa-0000-0000-0000-000000000001') $$,
  'rate it again');
select is((select rating || ' ' || message from public.feedback where order_id = 'fb0000aa-0000-0000-0000-000000000001'),
  '3 Box was dented', 'the second rating replaces the first');
select is((select count(*)::int from public.feedback where order_id = 'fb0000aa-0000-0000-0000-000000000001'), 1,
  'one row per order');
select lives_ok($$ select public.send_feedback('repair', 4, '', p_repair_id => 'fb0000bb-0000-0000-0000-000000000001') $$,
  'rate your own repair with stars only');
select lives_ok($$ select public.send_feedback('general', null, 'Please stock Nothing Phone (3)', p_screen => '/account') $$,
  'a comment with no rating');
select throws_ok($$ select public.send_feedback('general', null, '   ') $$, '23514', null, 'nothing to say is refused');
select throws_ok($$ select public.send_feedback('general', 6, 'x') $$, '23514', null, 'ratings are 1 to 5');
select throws_ok($$ select public.send_feedback('product', 2, 'Wrong colour shown') $$, 'P0001', 'BAD_REQUEST',
  'product feedback needs the product');

select pg_temp.as_user('fb000000-0000-0000-0000-000000000002');
select throws_ok($$ select public.send_feedback('order', 1, 'x', 'fb0000aa-0000-0000-0000-000000000001') $$, 'P0001',
  'NOT_FOUND', 'nobody can rate someone else''s order');
select is((select count(*)::int from public.feedback), 0, 'customers see only their own feedback');
select throws_ok($$ select public.send_feedback('general', 5, 'x') from generate_series(1, 11) $$, 'P0001',
  'FEEDBACK_LIMIT', 'at most 10 a day');
update public.feedback set status = 'resolved';
select is((select count(*)::int from public.feedback where status = 'resolved'), 0,
  'customers can''t change the status');

reset role;
select pg_temp.as_user('fb000000-0000-0000-0000-000000000003');
select is((select count(*)::int from public.feedback where user_id::text like 'fb000000-%'), 3,
  'the shop sees everyone''s feedback');
select lives_ok($$ update public.feedback set status = 'resolved', admin_note = 'Called the customer'
  where order_id = 'fb0000aa-0000-0000-0000-000000000001' $$, 'the shop marks it resolved');

reset role;
set local role anon;
select throws_ok($$ select public.send_feedback('general', 5, 'x') $$, '42501', null, 'signed-out callers can''t send');

reset role;
delete from public.orders where id = 'fb0000aa-0000-0000-0000-000000000001';
select is((select count(*)::int from public.feedback
  where user_id = 'fb000000-0000-0000-0000-000000000001' and kind = 'order' and order_id is null), 1,
  'deleting an order keeps its feedback, unlinked');

select * from finish();
rollback;
