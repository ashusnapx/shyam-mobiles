-- admin_catalogue: staff only, filters, search, sort, paging, and totals on the first page only.
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

insert into auth.users (id, email) values
  ('a1000000-0000-0000-0000-000000000001', 'cat-staff@test.dev'),
  ('a1000000-0000-0000-0000-000000000002', 'cat-buyer@test.dev');
insert into public.admins (user_id) values ('a1000000-0000-0000-0000-000000000001');
insert into public.categories (id, slug, name, kind) values ('c1000000-0000-0000-0000-000000000001', 'cat-test', 'Cat test', 'accessory');
insert into public.brands (id, slug, name) values ('b1000000-0000-0000-0000-000000000001', 'cat-brand', 'Catbrand');
insert into public.products (id, slug, name, brand_id, category_id, is_active) values
  ('e1000000-0000-0000-0000-000000000001', 'zz-alpha', 'Catbrand Alpha 100%', 'b1000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', true),
  ('e1000000-0000-0000-0000-000000000002', 'zz-beta', 'Catbrand Beta', 'b1000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', false);
insert into public.variants (product_id, sku, name, price_paise, mrp_paise, stock, is_active) values
  ('e1000000-0000-0000-0000-000000000001', 'ZZ-A1', 'One', 10000, 20000, 0, true),
  ('e1000000-0000-0000-0000-000000000001', 'ZZ-A2', 'Two', 30000, 30000, 2, true),
  ('e1000000-0000-0000-0000-000000000001', 'ZZ-A3', 'Three', 20000, 25000, 9, false),
  ('e1000000-0000-0000-0000-000000000002', 'ZZ-B1', 'One', 5000, 5000, 4, true);

create function pg_temp.as_user(p uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
create function pg_temp.skus(p json) returns text language sql as $$
  select string_agg(r ->> 'sku', ',' order by ord) from json_array_elements(p -> 'rows') with ordinality t(r, ord)
$$;
create function pg_temp.cat(p_query text default '', p_stock text default 'all', p_visibility text default 'all',
    p_sort text default 'name', p_offset int default 0, p_limit int default 50) returns json language sql as $$
  select public.admin_catalogue(p_query, 'c1000000-0000-0000-0000-000000000001', null, p_stock, p_visibility, p_sort, p_offset, p_limit)
$$;

select pg_temp.as_user('a1000000-0000-0000-0000-000000000002');
select throws_ok($$ select public.admin_catalogue() $$, 'P0001', 'FORBIDDEN', 'customers get nothing');
reset role;
select throws_ok($$ select public.admin_catalogue() $$, 'P0001', 'FORBIDDEN', 'no session gets nothing');

select pg_temp.as_user('a1000000-0000-0000-0000-000000000001');
select is(pg_temp.skus(pg_temp.cat()), 'ZZ-A1,ZZ-A3,ZZ-A2,ZZ-B1', 'by product name, then variant name');
select is(pg_temp.skus(pg_temp.cat(p_sort => 'stock')), 'ZZ-A1,ZZ-A2,ZZ-B1,ZZ-A3', 'stock, lowest first');
select is(pg_temp.skus(pg_temp.cat(p_sort => 'price')), 'ZZ-B1,ZZ-A1,ZZ-A3,ZZ-A2', 'price, lowest first');
select is(pg_temp.skus(pg_temp.cat(p_stock => 'low')), 'ZZ-A2', 'low = 1 to 3 left');
select is(pg_temp.skus(pg_temp.cat(p_stock => 'out')), 'ZZ-A1', 'out = none left');
select is(pg_temp.skus(pg_temp.cat(p_visibility => 'hidden')), 'ZZ-A3,ZZ-B1', 'hidden variant or hidden product');
select is(pg_temp.skus(pg_temp.cat('zz-a')), 'ZZ-A1,ZZ-A3,ZZ-A2', 'search matches SKU, any case');
select is(pg_temp.skus(pg_temp.cat('100%')), 'ZZ-A1,ZZ-A3,ZZ-A2', 'a % in the search is a plain character');
select is(pg_temp.skus(pg_temp.cat(p_offset => 1, p_limit => 2)), 'ZZ-A3,ZZ-A2', 'pages by offset and limit');
select is((pg_temp.cat() -> 'summary')::jsonb - 'total_skus',
  '{"skus":4,"units":15,"value_at_price_paise":260000,"value_at_mrp_paise":305000,"low":1,"out":1}'::jsonb,
  'totals over every matching row');
select ok((pg_temp.cat(p_offset => 2) ->> 'summary') is null, 'later pages skip the totals');
select throws_ok($$ select pg_temp.cat(p_sort => 'random()') $$, 'P0001', 'BAD_REQUEST', 'only the known sorts');

select * from finish();
rollback;
