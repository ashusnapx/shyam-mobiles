-- Notification photos: an order's main item photo, the product cover for stock and product feedback, the order's for
-- order feedback, none for repairs and coupons; the push carries the path; a photo never fails what triggered it.
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

delete from public.admins;
delete from public.promotions;
update public.store_settings set delivery_fee_paise = 0, cod_enabled = true, cod_max_paise = 2500000;
insert into auth.users (id, email) values
  ('ac000000-0000-0000-0000-000000000001', 'ni-asha@test.dev'),
  ('ac000000-0000-0000-0000-000000000011', 'ni-staff@test.dev');
insert into public.admins (user_id) values ('ac000000-0000-0000-0000-000000000011');
insert into public.categories (id, slug, name, kind) values ('ac0000c0-0000-0000-0000-000000000001', 'ni-cat', 'Ni cat', 'phone');
insert into public.brands (id, slug, name) values ('ac0000b0-0000-0000-0000-000000000001', 'ni-brand', 'Ni');
insert into public.products (id, slug, name, brand_id, category_id) values
  ('ac0000a0-0000-0000-0000-000000000001', 'ni-phone', 'Photo Phone', 'ac0000b0-0000-0000-0000-000000000001', 'ac0000c0-0000-0000-0000-000000000001'),
  ('ac0000a0-0000-0000-0000-000000000002', 'ni-case', 'Plain Case', 'ac0000b0-0000-0000-0000-000000000001', 'ac0000c0-0000-0000-0000-000000000001');
insert into public.product_images (product_id, path, sort) values
  ('ac0000a0-0000-0000-0000-000000000001', 'ni-phone/2000.webp', 1),
  ('ac0000a0-0000-0000-0000-000000000001', 'ni-phone/1000.webp', 0);
insert into public.variants (id, product_id, sku, name, price_paise, mrp_paise, stock) values
  ('ac0000d0-0000-0000-0000-000000000001', 'ac0000a0-0000-0000-0000-000000000001', 'NI-1', '8 GB', 90000, 90000, 4),
  ('ac0000d0-0000-0000-0000-000000000002', 'ac0000a0-0000-0000-0000-000000000002', 'NI-2', 'Black', 20000, 20000, 50);
insert into public.addresses (user_id, name, phone, line1, city, state, pincode) values
  ('ac000000-0000-0000-0000-000000000001', 'Asha', '+919876543210', '1 Main Road', 'Waidhan', 'Madhya Pradesh', '486886');

create function pg_temp.as_user(p uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
create function pg_temp.photo(p_kind text) returns text language sql security definer as $$
  select coalesce(image_path, '-') from public.notifications where kind = p_kind order by created_at desc limit 1 $$;

-- an order with the photo phone (priciest) and a case with no photo, taking the phone from 4 to 3 (low stock)
select pg_temp.as_user('ac000000-0000-0000-0000-000000000001');
insert into public.cart_items (user_id, variant_id, qty) values
  (auth.uid(), 'ac0000d0-0000-0000-0000-000000000001', 1), (auth.uid(), 'ac0000d0-0000-0000-0000-000000000002', 1);
select set_config('ni.order', public.place_order((select id from public.addresses where user_id = auth.uid()), 'cod')::text, true);
reset role;
select is(pg_temp.photo('order_confirmed'), 'ni-phone/1000.webp', 'an order shows its main item''s photo (the cover at order time)');
select is(pg_temp.photo('staff_new_order'), 'ni-phone/1000.webp', 'staff see it too');
select is(pg_temp.photo('staff_low_stock'), 'ni-phone/1000.webp', 'stock alerts show the product''s cover');

select pg_temp.as_user('ac000000-0000-0000-0000-000000000011');
select public.admin_update_order(current_setting('ni.order')::uuid, 'packed');
reset role;
select is(pg_temp.photo('order_packed'), 'ni-phone/1000.webp', 'every step of the order');

select pg_temp.as_user('ac000000-0000-0000-0000-000000000001');
select public.send_feedback('order', 2, 'Box was dented', current_setting('ni.order')::uuid);
reset role;
select is(pg_temp.photo('staff_feedback_low'), 'ni-phone/1000.webp', 'feedback on an order: that order''s photo');
select pg_temp.as_user('ac000000-0000-0000-0000-000000000001');
select public.send_feedback('product', 4, 'Nice', p_product_id => 'ac0000a0-0000-0000-0000-000000000001');
reset role;
select is(pg_temp.photo('staff_feedback'), 'ni-phone/1000.webp', 'feedback on a product: its cover');
select pg_temp.as_user('ac000000-0000-0000-0000-000000000001');
select public.send_feedback('general', null, 'Open on Sunday?');
reset role;
select is(pg_temp.photo('staff_feedback'), '-', 'general feedback: no photo');

select pg_temp.as_user('ac000000-0000-0000-0000-000000000001');
insert into public.repair_bookings (user_id, device_brand, device_model, issue, preferred_date, slot, contact_phone)
values (auth.uid(), 'Samsung', 'Galaxy A56', 'screen', (now() at time zone 'Asia/Kolkata')::date + 1, 'morning', '+919876543210');
reset role;
select is(pg_temp.photo('repair_booked'), '-', 'repairs: the illustration, no photo');
insert into public.promotions (title, code, kind, value, is_public, user_id)
values ('Wholesale buyer', 'NIBULK01', 'percent', 5, false, 'ac000000-0000-0000-0000-000000000001');
select is(pg_temp.photo('coupon'), '-', 'coupons: no photo');

select lives_ok($$select private.notify('ac000000-0000-0000-0000-000000000001', 'staff_feedback', 'x', 'y',
  '/admin/feedback/00000000-0000-0000-0000-00000000000z')$$, 'an odd link never fails the notification');

insert into public.device_tokens (token, user_id) values ('niTokenAAAAAAAAAAAAAAAAAAAA:1', 'ac000000-0000-0000-0000-000000000001');
delete from vault.secrets where name in ('push_url', 'push_secret'); -- the local stack may have push set up
select vault.create_secret('http://127.0.0.1:54321/functions/v1/send-push-ni', 'push_url');
select vault.create_secret('ni-secret', 'push_secret');
select pg_temp.as_user('ac000000-0000-0000-0000-000000000011');
select public.admin_update_order(current_setting('ni.order')::uuid, 'shipped');
reset role;
select is((select convert_from(body, 'UTF8')::jsonb ->> 'image_path' from net.http_request_queue
           where url = 'http://127.0.0.1:54321/functions/v1/send-push-ni' order by id desc limit 1),
  'ni-phone/1000.webp', 'the push carries the photo''s path');

select throws_ok($$insert into public.notifications (user_id, kind, title, image_path)
  values ('ac000000-0000-0000-0000-000000000001', 'order_update', 'x', 'https://evil.example/x.png')$$, '23514', null,
  'only product-images keys, never a URL');

select * from finish();
rollback;
