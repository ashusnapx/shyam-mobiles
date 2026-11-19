-- Phone packs: buy a phone with its glass, case, lens guard, charger or earphones together and get X% off, set up by
-- the owner (Admin > Offers > New pack offer). An automatic sale that competes under the one-offer-per-order rule
-- like any other (the bigger saving wins, never stacks). Mirrored by firebase/functions/src/orders/pricing.ts.
-- value: the percent (1..50); targets: the phone categories; pack_types: the accessory types the cart must hold for
-- that phone; pack_whole: the discount covers the phone too (default: the accessories only).

alter table public.promotions
  add column pack_types text[] not null default '{}'
    check (pack_types <@ array['glass', 'case', 'lens', 'charger', 'earphones']),
  add column pack_whole boolean not null default false,
  drop constraint promotions_value_check,
  add constraint promotions_value_check check (case kind
    when 'percent' then value between 1 and 90 when 'flat' then value >= 100 when 'pack' then value between 1 and 50
    else value = 0 end),
  drop constraint promotions_cap_check,
  add constraint promotions_cap_check check (max_discount_paise is null or (kind in ('percent', 'pack') and max_discount_paise >= 1)),
  add constraint promotions_pack_check check (case when kind = 'pack'
    then code is null
    else cardinality(pack_types) = 0 and not pack_whole end);

-- The accessory type a pack asks for, from the category and the name ("Camera lens guard" is a lens guard even in
-- Screen guards). Same rule in pricing.ts and the app's pack card.
create function private.accessory_type(p_category_slug text, p_name text) returns text
language sql immutable set search_path = '' as $$
  select case
    when lower(p_name) like '%lens%' then 'lens'
    when p_category_slug = 'screen-guards' or lower(p_name) ~ '(glass|screen guard|screen protector)' then 'glass'
    when p_category_slug = 'cases-covers' or lower(p_name) ~ '(case|cover)' then 'case'
    when lower(p_name) ~ '(charger|adapter)' then 'charger'
    when p_category_slug = 'earbuds-headphones' or lower(p_name) ~ '(earphone|earbud|buds|headphone|airpods)' then 'earphones'
  end
$$;

-- The variant ids a pack discounts in the caller's lines, or null when the cart isn't a pack. The phone: the dearest
-- line in one of the pack's phone categories that has, for every required type, another line of that type that fits
-- it (its "Fits" spec names the phone, or a made-to-order line for that phone; chargers and earphones fit any phone).
-- The lines: every fitting accessory of a required type, plus the phone when pack_whole.
create function private.pack_lines(p public.promotions, p_uid uuid, p_lines uuid[]) returns uuid[]
language sql stable set search_path = '' as $$
  with l as (
    select v.id, v.price_paise, v.made_to_order, c.for_model, pr.name, pr.specs, pr.category_id, cat.kind,
      private.accessory_type(cat.slug, pr.name) as type,
      case when char_length(pr.name) > char_length(b.name) + 1 and lower(pr.name) like lower(b.name) || ' %'
        then substr(pr.name, char_length(b.name) + 2) else pr.name end as short
    from public.cart_items c
    join public.variants v on v.id = c.variant_id
    join public.products pr on pr.id = v.product_id
    join public.categories cat on cat.id = pr.category_id
    join public.brands b on b.id = pr.brand_id
    where c.user_id = p_uid and c.variant_id = any(p_lines)
  ), phones as (
    select l.* from l
    where l.kind = 'phone' and exists (select 1 from public.promotion_targets t
      where t.promotion_id = p.id and t.target_type = 'category' and t.target_id = l.category_id)
  ), fit as (
    select ph.id as phone_id, a.id, a.type
    from phones ph join l a on a.id <> ph.id and a.type = any(p.pack_types)
    where a.type in ('charger', 'earphones')
      or exists (select 1 from jsonb_array_elements(case when jsonb_typeof(a.specs) = 'array' then a.specs else '[]' end) s
                 where s ->> 'label' = 'Fits' and s ->> 'value' in (ph.name, ph.short))
      or (a.made_to_order and lower(replace(a.for_model, ' ', '')) in
          (lower(replace(ph.name, ' ', '')), lower(replace(ph.short, ' ', ''))))
  ), best as (
    select ph.id from phones ph
    where (select count(distinct f.type) from fit f where f.phone_id = ph.id) = (select count(distinct t) from unnest(p.pack_types) t)
    order by ph.price_paise desc, ph.id
    limit 1
  )
  select array_agg(x) from (
    select f.id as x from fit f join best on f.phone_id = best.id
    union
    select best.id from best where p.pack_whole
  ) u
$$;

create or replace function private.evaluate_promotion(
  p public.promotions, p_uid uuid, p_lines uuid[], p_method public.payment_method,
  p_subtotal bigint, p_base_fee int, p_settings public.store_settings,
  out error text, out detail text, out discount bigint, out fee int, out saving bigint)
language plpgsql stable set search_path = '' as $$
declare
  v_eligible bigint;
  v_count int;
  v_pack uuid[];
begin
  if p.starts_at > now() then error := 'COUPON_NOT_STARTED'; return; end if;
  if p.ends_at <= now() then error := 'COUPON_EXPIRED'; return; end if;
  if p.usage_limit is not null and private.promotion_uses(p.id) >= p.usage_limit then error := 'COUPON_USED_UP'; return; end if;
  if p.per_user_limit is not null and private.promotion_uses(p.id, p_uid) >= p.per_user_limit then
    error := 'COUPON_LIMIT_REACHED'; return;
  end if;
  if p.first_order_only and exists (select 1 from public.orders where user_id = p_uid and status <> 'cancelled') then
    error := 'COUPON_FIRST_ORDER'; return;
  end if;
  if p.online_only and p_method = 'cod' then error := 'COUPON_ONLINE_ONLY'; return; end if;

  if p.kind = 'pack' then
    v_pack := private.pack_lines(p, p_uid, p_lines);
    select coalesce(sum(v.price_paise::bigint * c.qty), 0), count(*) into v_eligible, v_count
    from public.cart_items c join public.variants v on v.id = c.variant_id
    where c.user_id = p_uid and c.variant_id = any(p_lines) and v.id = any(v_pack);
  else
    select coalesce(sum(v.price_paise::bigint * c.qty), 0), count(*) into v_eligible, v_count
    from public.cart_items c join public.variants v on v.id = c.variant_id
    where c.user_id = p_uid and c.variant_id = any(p_lines) and private.covers(p.id, v.product_id);
  end if;
  if v_count = 0 then error := 'COUPON_NOT_APPLICABLE'; return; end if;
  if v_eligible < p.min_subtotal_paise then error := 'COUPON_MIN_ORDER'; detail := p.min_subtotal_paise::text; return; end if;

  discount := case p.kind
    when 'percent' then least(v_eligible * p.value / 100, coalesce(p.max_discount_paise, v_eligible))
    when 'pack' then least(v_eligible * p.value / 100, coalesce(p.max_discount_paise, v_eligible))
    when 'flat' then least(p.value, v_eligible)
    else 0 end;
  discount := greatest(0, least(discount, p_subtotal - 100));
  fee := case when p.kind = 'free_delivery' or p_subtotal - discount >= p_settings.free_delivery_min_paise then 0
              else p_settings.delivery_fee_paise end;
  saving := p_base_fee + discount - fee;
  if saving <= 0 then error := 'COUPON_NOT_APPLICABLE'; end if;
end $$;

create or replace function private.price_lines(p_uid uuid, p_lines uuid[], p_code text, p_method public.payment_method, p_lock boolean)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_settings public.store_settings;
  v_code text := nullif(upper(regexp_replace(coalesce(p_code, ''), '[[:space:]]', '', 'g')), '');
  v_subtotal bigint;
  v_base_fee int;
  v_promo public.promotions;
  v_promo_id uuid;
  v_discount bigint;
  v_fee int;
  v_error text;
  v_detail text;
  v_lines jsonb := '[]';
  v_code_saving bigint;
  v_auto_discount bigint;
  v_auto_fee int;
  v_auto_saving bigint;
begin
  select * into v_settings from public.store_settings;
  select coalesce(sum(v.price_paise::bigint * c.qty), 0) into v_subtotal
  from public.cart_items c join public.variants v on v.id = c.variant_id
  where c.user_id = p_uid and c.variant_id = any(p_lines);
  v_base_fee := case when v_subtotal >= v_settings.free_delivery_min_paise then 0 else v_settings.delivery_fee_paise end;

  if v_code is not null then
    if (select count(*) from public.coupon_attempts where user_id = p_uid and at > now() - interval '10 minutes') >= 10 then
      v_error := 'COUPON_RATE_LIMIT';
    else
      if p_lock then perform 1 from public.promotions where code = v_code for update; end if;
      -- paused and other people's personal codes look exactly like unknown ones
      select * into v_promo from public.promotions
      where code = v_code and is_active and (user_id is null or user_id = p_uid);
      if not found then
        v_error := 'COUPON_NOT_FOUND';
        -- shortcut: place_order raises this error, which rolls the attempt back, so only quote_order lookups count
        -- toward COUPON_RATE_LIMIT; hidden codes rely on length. Upgrade: an autonomous write (dblink) if guessing shows up.
        delete from public.coupon_attempts where user_id = p_uid and at <= now() - interval '10 minutes';
        insert into public.coupon_attempts (user_id) values (p_uid);
      else
        select e.error, e.detail, e.discount, e.fee, e.saving into v_error, v_detail, v_discount, v_fee, v_code_saving
        from private.evaluate_promotion(v_promo, p_uid, p_lines, p_method, v_subtotal, v_base_fee, v_settings) e;
      end if;
    end if;
  end if;

  if p_lock then
    perform 1 from public.promotions
    where code is null and is_active and starts_at <= now() and (ends_at is null or ends_at > now())
    order by id for update;
  end if;
  -- best automatic sale: largest saving, then the one ending first
  select p.id, e.discount, e.fee, e.saving into v_promo_id, v_auto_discount, v_auto_fee, v_auto_saving
  from public.promotions p
  cross join lateral private.evaluate_promotion(p, p_uid, p_lines, p_method, v_subtotal, v_base_fee, v_settings) e
  where p.code is null and p.is_active and e.error is null
  order by e.saving desc, p.ends_at nulls last, p.id
  limit 1;

  if v_code is null or v_error is not null then
    v_discount := v_auto_discount;
    v_fee := v_auto_fee;
    select * into v_promo from public.promotions where id = v_promo_id;
  elsif v_promo_id is not null and v_auto_saving > v_code_saving then
    -- a running sale saves more than the typed code: the customer gets the sale and keeps the code for later
    -- (quote_order says so with COUPON_BETTER_OFFER; place_order just charges the lower price)
    v_discount := v_auto_discount;
    v_fee := v_auto_fee;
    select * into v_promo from public.promotions where id = v_promo_id;
    v_error := case when p_lock then null else 'COUPON_BETTER_OFFER' end;
  end if;

  if v_promo.id is null then
    v_discount := 0;
    v_fee := v_base_fee;
  elsif v_discount > 0 then
    -- split over the eligible lines by line total, rounding down; the remainder goes to the largest line (ties: lowest
    -- variant id), spilling to the next only if it would pass that line's total
    with el as (
      select v.id, v.price_paise::bigint * c.qty as lt
      from public.cart_items c join public.variants v on v.id = c.variant_id
      where c.user_id = p_uid and c.variant_id = any(p_lines) and case when v_promo.kind = 'pack'
        then v.id = any(private.pack_lines(v_promo, p_uid, p_lines)) else private.covers(v_promo.id, v.product_id) end
    ), base as (
      select id, lt, div(v_discount::numeric * lt, sum(lt) over ())::bigint as share,
        row_number() over (order by lt desc, id) as rn
      from el
    ), spread as (
      select id, lt, share, v_discount - sum(share) over () as rest,
        coalesce(sum(lt - share) over (order by rn rows between unbounded preceding and 1 preceding), 0) as room_before
      from base
    )
    select jsonb_agg(jsonb_build_object('variant_id', id,
      'discount_paise', share + least(lt - share, greatest(0, rest - room_before))))
    into v_lines from spread;
  end if;

  return jsonb_build_object(
    'subtotal_paise', v_subtotal,
    'delivery_fee_paise', v_fee,
    'discount_paise', v_discount,
    'total_paise', v_subtotal + v_fee - v_discount,
    'promotion', case when v_promo.id is not null then
      jsonb_build_object('id', v_promo.id, 'title', v_promo.title, 'code', v_promo.code, 'kind', v_promo.kind) end,
    'coupon_error', v_error,
    'coupon_error_detail', v_detail,
    'lines', v_lines);
end $$;

-- Saves a pack offer: admin_save_promotion does the shared fields, the phone-category targets and their checks, then
-- the pack's own two. p: admin_save_promotion's json plus pack_types (text[]) and pack_whole. INVALID_PROMOTION when
-- it isn't a valid pack (kind pack, no code, at least one type, phone categories as targets).
create function public.admin_save_pack(p json) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v jsonb := p::jsonb;
  v_id uuid;
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  if v ->> 'kind' is distinct from 'pack' or nullif(btrim(v ->> 'code'), '') is not null or v ->> 'applies_to' is distinct from 'items'
     or jsonb_typeof(v -> 'pack_types') is distinct from 'array' or jsonb_array_length(v -> 'pack_types') = 0 then
    raise exception using message = 'INVALID_PROMOTION', detail = 'promotions_pack_check';
  end if;
  v_id := public.admin_save_promotion(p);
  begin
    update public.promotions set
      pack_types = array(select distinct jsonb_array_elements_text(v -> 'pack_types') order by 1),
      pack_whole = coalesce((v ->> 'pack_whole')::boolean, false)
    where id = v_id;
  exception when check_violation or invalid_text_representation then
    raise exception using message = 'INVALID_PROMOTION', detail = 'pack_types';
  end;
  if exists (select 1 from public.promotion_targets t where t.promotion_id = v_id and (t.target_type <> 'category'
      or not exists (select 1 from public.categories c where c.id = t.target_id and c.kind = 'phone'))) then
    raise exception using message = 'INVALID_PROMOTION', detail = 'phone categories only';
  end if;
  return v_id;
end $$;

-- The running pack offers, for the "Complete your pack" card on phone pages and in the cart.
create function public.pack_offers() returns json
language sql stable security definer set search_path = '' as $$
  select coalesce(json_agg(json_build_object('id', p.id, 'title', p.title, 'value', p.value,
      'max_discount_paise', p.max_discount_paise, 'pack_types', p.pack_types, 'pack_whole', p.pack_whole,
      'ends_at', p.ends_at,
      'categories', (select coalesce(json_agg(t.target_id order by t.target_id), '[]') from public.promotion_targets t
                     where t.promotion_id = p.id and t.target_type = 'category'))
    order by p.value desc, p.id), '[]')
  from public.promotions p
  where p.kind = 'pack' and private.offer_open(p, auth.uid())
$$;

revoke execute on function public.admin_save_pack(json), public.pack_offers() from public, anon, authenticated, service_role;
grant execute on function public.admin_save_pack(json) to authenticated;
grant execute on function public.pack_offers() to anon, authenticated;
revoke execute on all functions in schema private from public, anon, authenticated;
