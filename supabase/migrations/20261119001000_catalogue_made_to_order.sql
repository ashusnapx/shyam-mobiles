-- Made-to-order variants (stock 0 by design) no longer count as low or out of stock in the admin catalogue and the
-- dashboard alerts; rows carry made_to_order so the app can tag them "Arranged on order". Replaces 20261030000100.
create or replace function public.admin_catalogue(
  p_query text default '',
  p_category_id uuid default null,
  p_brand_id uuid default null,
  p_stock text default 'all',          -- all | low | out
  p_visibility text default 'all',     -- all | shown | hidden
  p_sort text default 'name',          -- name | stock | price | updated
  p_offset int default 0,
  p_limit int default 50
) returns json
language plpgsql stable security definer set search_path = '' as $$
declare
  v_q text := lower(btrim(coalesce(p_query, '')));
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  if p_stock not in ('all', 'low', 'out') or p_visibility not in ('all', 'shown', 'hidden')
     or p_sort not in ('name', 'stock', 'price', 'updated') or p_offset not between 0 and 1000000
     or p_limit not between 1 and 100 or char_length(v_q) > 100 then
    raise exception 'BAD_REQUEST';
  end if;
  return (
    with matching as (
      select v.id as variant_id, p.id as product_id, p.name as product_name, v.name as variant_name, v.sku,
        v.price_paise, v.mrp_paise, v.stock, v.made_to_order, v.is_active as variant_active, p.is_active as product_active,
        p.is_featured as featured, p.category_id, p.brand_id, greatest(v.updated_at, p.updated_at) as updated_at,
        (select pi.path from public.product_images pi where pi.product_id = p.id order by pi.sort, pi.id limit 1)
          as cover_path
      from public.variants v
      join public.products p on p.id = v.product_id
      -- position(), not LIKE: a typed % or _ is just a character
      where (v_q = '' or position(v_q in lower(p.name || ' ' || v.name || ' ' || v.sku)) > 0)
        and (p_category_id is null or p.category_id = p_category_id)
        and (p_brand_id is null or p.brand_id = p_brand_id)
        and case p_stock when 'low' then not v.made_to_order and v.stock between 1 and 3
                            when 'out' then not v.made_to_order and v.stock = 0 else true end
        and case p_visibility
              when 'shown' then v.is_active and p.is_active
              when 'hidden' then not (v.is_active and p.is_active)
              else true end
    ),
    page as (
      select m.*, row_number() over (order by
          case when p_sort = 'stock' then m.stock end,
          case when p_sort = 'price' then m.price_paise end,
          case when p_sort = 'updated' then m.updated_at end desc,
          lower(m.product_name), lower(m.variant_name), m.variant_id) as rn
      from matching m
    )
    select json_build_object(
      'rows', coalesce((select json_agg(to_jsonb(pg) - 'rn' order by pg.rn) from page pg
                        where pg.rn > p_offset and pg.rn <= p_offset + p_limit), '[]'::json),
      -- the totals cover every matching row, so they come with the first page only
      'summary', case when p_offset = 0 then (
        select json_build_object(
          'skus', count(*),
          'units', coalesce(sum(m.stock), 0),
          'value_at_price_paise', coalesce(sum(m.price_paise::bigint * m.stock), 0),
          'value_at_mrp_paise', coalesce(sum(m.mrp_paise::bigint * m.stock), 0),
          'low', count(*) filter (where not m.made_to_order and m.stock between 1 and 3),
          'out', count(*) filter (where not m.made_to_order and m.stock = 0),
          'total_skus', (select count(*) from public.variants))
        from matching m) end)
  );
end $$;
