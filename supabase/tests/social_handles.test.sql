-- The Follow buttons' usernames on store_settings: everyone reads them, only staff change them, and only bare handles.
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users (id, email) values
  ('5c000000-0000-0000-0000-000000000001', 'sh-asha@test.dev'),
  ('5c000000-0000-0000-0000-000000000002', 'sh-staff@test.dev');
insert into public.admins (user_id) values ('5c000000-0000-0000-0000-000000000002');
update public.store_settings set instagram_handle = 'ashusnapx', facebook_handle = 'ashusnapx';

create function pg_temp.as_user(p uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;

set local role anon;
select results_eq($$select instagram_handle, facebook_handle from public.store_settings$$,
  $$values ('ashusnapx'::text, 'ashusnapx'::text)$$, 'anon: reads the handles');
reset role;

select pg_temp.as_user('5c000000-0000-0000-0000-000000000001');
select is_empty($$update public.store_settings set instagram_handle = 'someone.else' returning 1$$, 'a customer cannot change them');

select pg_temp.as_user('5c000000-0000-0000-0000-000000000002');
select isnt_empty($$update public.store_settings set instagram_handle = 'shyam_mobiles.waidhan' returning 1$$, 'staff save an Instagram handle');
select isnt_empty($$update public.store_settings set facebook_handle = 'shyam.mobiles' returning 1$$, 'staff save a Facebook handle');
select lives_ok($$update public.store_settings set instagram_handle = null, facebook_handle = null$$, 'null clears both');
select throws_ok($$update public.store_settings set instagram_handle = 'https://instagram.com/x'$$, '23514', null,
  'a link is not a handle');
select throws_ok($$update public.store_settings set instagram_handle = 'a_very_long_handle_over_thirty_c'$$, '23514', null,
  'Instagram: 30 characters at most');
select throws_ok($$update public.store_settings set facebook_handle = 'shy_m'$$, '23514', null,
  'Facebook: letters, digits and dots only, 5 or more');

reset role;
select * from finish();
rollback;
