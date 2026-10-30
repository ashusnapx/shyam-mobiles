-- One offer per order, and never the worse one: a typed code that saves less than a running automatic sale gives way
-- to the sale. Before this a customer typing WELCOME100 on a Rs 74,999 phone paid Rs 1,900 more than not typing it.
-- The one pricing path (SPEC "Pricing"). p_lines: the caller's cart lines (variant ids), locked by place_order.
-- p_lock (place_order): lock the promotion rows before counting uses, so two checkouts can't both take the last use.
-- Returns {subtotal_paise, delivery_fee_paise, discount_paise, total_paise, promotion: {id, title, code, kind} | null,
-- coupon_error, coupon_error_detail, lines: [{variant_id, discount_paise}]}. A bad code sets coupon_error and falls
-- back to the best automatic sale; place_order raises it instead.
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
      where c.user_id = p_uid and c.variant_id = any(p_lines) and private.covers(v_promo.id, v.product_id)
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
