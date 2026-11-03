-- Phone + password sign-in (20261103000000): who the access token hook lets through, the temporary-password flag,
-- and the staff lookup behind reset-password.
begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

insert into private.password_sign_in_domains (domain) values ('pp-demo.test');
insert into auth.users (id, email, phone, raw_app_meta_data, raw_user_meta_data) values
  ('9a000000-0000-0000-0000-000000000001', null, '919876500001', '{"provider": "phone"}', '{"full_name": "Ravi Kumar"}'),
  ('9a000000-0000-0000-0000-000000000002', 'asha@gmail.com', null, '{"provider": "email"}', '{}'),
  ('9a000000-0000-0000-0000-000000000003', 'demo.customer@pp-demo.test', null, '{"provider": "email"}', '{}'),
  ('9a000000-0000-0000-0000-000000000004', 'x@pp-demo.test.evil.com', null, '{"provider": "email"}', '{}'),
  ('9a000000-0000-0000-0000-000000000005', null, '919876500005', '{"provider": "phone"}', '{"full_name": "Shop Owner"}');
insert into public.admins (user_id) values ('9a000000-0000-0000-0000-000000000005');

create function pg_temp.hook(p_uid uuid, p_amr text, p_method text) returns jsonb language sql as $$
  select private.custom_access_token_hook(jsonb_build_object('user_id', p_uid, 'authentication_method', p_method,
    'claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated',
      'amr', jsonb_build_array(jsonb_build_object('method', p_amr, 'timestamp', 1)))))
$$;

-- the hook ------------------------------------------------------------------------------------------------------

select ok(pg_temp.hook('9a000000-0000-0000-0000-000000000001', 'password', 'password') ? 'claims',
  'phone + password signs in');
select ok(pg_temp.hook('9a000000-0000-0000-0000-000000000001', 'password', 'token_refresh') ? 'claims',
  'and the session refreshes');
select is(pg_temp.hook('9a000000-0000-0000-0000-000000000002', 'password', 'password') #>> '{error,http_code}', '403',
  'email + password on any other domain is refused');
select ok(pg_temp.hook('9a000000-0000-0000-0000-000000000003', 'password', 'password') ? 'claims',
  'email + password on an allow-listed domain (demo, dev) signs in');
select is(pg_temp.hook('9a000000-0000-0000-0000-000000000004', 'password', 'password') #>> '{error,http_code}', '403',
  'a look-alike domain is not the allow-listed one');
select ok(pg_temp.hook('9a000000-0000-0000-0000-000000000002', 'otp', 'token_refresh') ? 'claims',
  'a session from the old code sign-in keeps refreshing');

-- the temporary-password flag -------------------------------------------------------------------------------------

update auth.users set encrypted_password = 'temp-hash' where id = '9a000000-0000-0000-0000-000000000001';
update auth.users set raw_app_meta_data = raw_app_meta_data || '{"must_change_password": true}'
where id = '9a000000-0000-0000-0000-000000000001';
select is((select raw_app_meta_data from auth.users where id = '9a000000-0000-0000-0000-000000000001'),
  '{"provider": "phone", "must_change_password": true}', 'the shop''s reset: password, then the flag');

update auth.users set raw_app_meta_data = raw_app_meta_data || '{"providers": ["phone"]}'
where id = '9a000000-0000-0000-0000-000000000001';
select ok((select raw_app_meta_data ? 'must_change_password' from auth.users where id = '9a000000-0000-0000-0000-000000000001'),
  'other app_metadata changes keep the flag');

update auth.users set encrypted_password = 'own-hash' where id = '9a000000-0000-0000-0000-000000000001';
select is((select raw_app_meta_data from auth.users where id = '9a000000-0000-0000-0000-000000000001'),
  '{"provider": "phone", "providers": ["phone"]}', 'the customer''s own new password clears the flag, nothing else');

update auth.users set encrypted_password = 'temp-hash-2', raw_app_meta_data = raw_app_meta_data || '{"must_change_password": true}'
where id = '9a000000-0000-0000-0000-000000000001';
select ok((select raw_app_meta_data ? 'must_change_password' from auth.users where id = '9a000000-0000-0000-0000-000000000001'),
  'a password and the flag set in one update keep the flag');

update auth.users set encrypted_password = 'own-hash-2' where id = '9a000000-0000-0000-0000-000000000002';
select is((select raw_app_meta_data from auth.users where id = '9a000000-0000-0000-0000-000000000002'),
  '{"provider": "email"}', 'unflagged accounts are untouched');

-- the staff lookup ------------------------------------------------------------------------------------------------

select is(public.account_by_phone('+919876500001') - 'created_at',
  '{"user_id": "9a000000-0000-0000-0000-000000000001", "full_name": "Ravi Kumar", "staff": false}', 'finds the customer by number');
select is(public.account_by_phone('+919876500005') ->> 'staff', 'true', 'says when the number is a staff account');
select is(public.account_by_phone('+919876500009'), null, 'null when no account uses the number');
select is(public.account_by_phone('919876500001'), null, 'only a +91 mobile number is looked up');
select ok(not has_function_privilege('anon', 'public.account_by_phone(text)', 'execute')
  and not has_function_privilege('authenticated', 'public.account_by_phone(text)', 'execute'),
  'apps cannot look accounts up by number');
select ok(has_function_privilege('service_role', 'public.account_by_phone(text)', 'execute'), 'reset-password can');

select * from finish();
rollback;
