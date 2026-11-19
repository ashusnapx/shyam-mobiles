-- Auto-apply offers (Campaign calendar): only a coded offer can auto-apply, staff save the flag, customers see it,
-- and pricing ignores it (the code still has to be sent and still has to win).
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users (id, email) values
  ('aa000000-0000-0000-0000-000000000001', 'aa-asha@test.dev'),
  ('aa000000-0000-0000-0000-000000000002', 'aa-staff@test.dev');
insert into public.admins (user_id) values ('aa000000-0000-0000-0000-000000000002');

create function pg_temp.as_user(p uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;

select col_default_is('public', 'promotions', 'auto_apply', 'false', 'off unless staff turn it on');
select throws_ok($$insert into public.promotions (title, kind, value, auto_apply) values ('Sale', 'percent', 5, true)$$,
  '23514', null, 'an automatic sale (no code) cannot auto-apply');

select pg_temp.as_user('aa000000-0000-0000-0000-000000000002');
select lives_ok($$select set_config('t.p', public.admin_save_promotion(json_build_object('title', 'Men''s Day sale',
  'code', 'men5', 'kind', 'percent', 'value', 5, 'auto_apply', true)::json)::text, true)$$, 'staff save an auto-apply code');
select is((select auto_apply from public.promotions where id = current_setting('t.p')::uuid), true, '... and the flag sticks');
select lives_ok($$select public.admin_save_promotion(json_build_object('id', current_setting('t.p'), 'title', 'Men''s Day sale')::json)$$,
  'an edit that leaves it out');
select is((select auto_apply from public.promotions where id = current_setting('t.p')::uuid), true, '... keeps it');
select throws_ok($$select public.admin_save_promotion(json_build_object('id', current_setting('t.p'), 'code', null)::json)$$,
  'P0001', 'INVALID_PROMOTION', 'dropping the code of an auto-apply offer is refused');

reset role;
select pg_temp.as_user('aa000000-0000-0000-0000-000000000001');
select ok((select bool_or((o ->> 'auto_apply')::boolean) from json_array_elements(public.available_offers()) o
  where o ->> 'code' = 'MEN5'), 'customers see that it auto-applies');

reset role;
select * from finish();
rollback;
