-- "For any phone" products (every active variant made to order) have no photo and no stock: shop lists, rails, deals,
-- search results and similar items must not show them. Same columns as before. The app reads them from variants
-- (Accessories for <model>), the product page from products, so neither needs this view.
create or replace view public.product_cards with (security_invoker = true) as
select
  p.id, p.slug, p.name, p.is_featured, p.created_at, p.search,
  p.category_id, c.slug as category_slug, c.kind as category_kind,
  p.brand_id, b.slug as brand_slug, b.name as brand_name,
  v.min_price_paise, v.mrp_paise, v.in_stock,
  (select pi.path from public.product_images pi
    where pi.product_id = p.id order by pi.sort, pi.id limit 1) as cover_path,
  v.made_to_order, v.lead_days
from public.products p
join public.categories c on c.id = p.category_id
join public.brands b on b.id = p.brand_id
join lateral (
  select
    min(price_paise) as min_price_paise,
    (array_agg(mrp_paise order by price_paise))[1] as mrp_paise, -- MRP of the cheapest variant
    coalesce(sum(stock), 0) > 0 or bool_or(made_to_order) as in_stock,
    bool_or(made_to_order) as made_to_order,
    min(lead_days) filter (where made_to_order) as lead_days,
    bool_and(made_to_order) as only_made_to_order
  from public.variants
  where product_id = p.id and is_active
) v on true
where p.is_active and v.min_price_paise is not null and not v.only_made_to_order;
