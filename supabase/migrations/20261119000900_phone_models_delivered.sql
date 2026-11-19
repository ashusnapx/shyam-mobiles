-- Model suggestions no longer echo whatever a customer typed: the catalog's phone names plus the models on orders that
-- reached delivered, normalised (spaces collapsed), only letters/digits/spaces/+-. and at most 60 chars, deduped
-- ignoring case and spaces. Replaces the body from 20261119000100.
create or replace function public.phone_models() returns json
language sql stable security definer set search_path = '' as $$
  select coalesce(json_agg(name order by rank, at desc), '[]') from (
    select name, rank, at from (
      select distinct on (lower(replace(name, ' ', ''))) name, rank, at from (
        select n as name, rank, at from (
          select btrim(regexp_replace(p.name, '\s+', ' ', 'g')) as n, 0 as rank, p.created_at as at
          from public.products p join public.categories c on c.id = p.category_id
          where p.is_active and c.kind = 'phone'
          union all
          select btrim(regexp_replace(i.for_model, '\s+', ' ', 'g')), 1, o.created_at
          from public.order_items i join public.orders o on o.id = i.order_id
          where i.for_model is not null and o.status = 'delivered'
        ) raw
        where n ~ '^[A-Za-z0-9][A-Za-z0-9 +.-]*$' and length(n) <= 60
      ) s
      order by lower(replace(name, ' ', '')), rank, at desc
    ) d
    order by rank, at desc
    limit 300
  ) t
$$;
