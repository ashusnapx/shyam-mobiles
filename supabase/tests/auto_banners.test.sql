-- Home's automatic banners on store_settings: on by default but Repairs, staff-only, known names only.
begin;
create extension if not exists pgtap with schema extensions;
select plan(4);

insert into auth.users (id, email) values
  ('ab000000-0000-0000-0000-000000000001', 'ab-asha@test.dev'),
  ('ab000000-0000-0000-0000-000000000002', 'ab-staff@test.dev');
insert into public.admins (user_id) values ('ab000000-0000-0000-0000-000000000002');

create function pg_temp.as_user(p uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;

select is((select auto_banners from public.store_settings), array['deal', 'newest', 'exchange'], 'on by default, Repairs off');
select pg_temp.as_user('ab000000-0000-0000-0000-000000000001');
select is_empty($$update public.store_settings set auto_banners = '{}' returning 1$$, 'a customer cannot change them');
select pg_temp.as_user('ab000000-0000-0000-0000-000000000002');
select isnt_empty($$update public.store_settings set auto_banners = '{deal,repairs}' returning 1$$, 'staff turn them on and off');
select throws_ok($$update public.store_settings set auto_banners = '{deal,popup}'$$, '23514', null, 'only known banners');

reset role;
select * from finish();
rollback;
