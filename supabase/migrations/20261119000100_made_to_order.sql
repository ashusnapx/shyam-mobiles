-- Made-to-order accessories: covers, glass and guards the shop arranges for ANY phone model, even one launched today
-- and unknown to the catalog. Such a variant has no stock: the customer names their phone on the cart line
-- (for_model), checkout skips the stock check and decrement, and cancels/refunds never put it back (keyed off the
-- order line's for_model, so flipping the variant's flag later can't mint stock). Pricing is unchanged.

alter table public.variants
  add column made_to_order boolean not null default false,
  add column lead_days int not null default 2 check (lead_days between 1 and 30); -- "ready in N days"

-- The phone model as the customer typed it, tidied by the app: single spaces, no edge spaces, plain characters.
alter table public.cart_items add column for_model text check (char_length(for_model) between 2 and 60
  and for_model ~ '^[A-Za-z0-9][A-Za-z0-9 +()./''-]*$' and for_model !~ '  ' and for_model = btrim(for_model));
-- Set only on made-to-order lines: staff arrange the item for this phone.
alter table public.order_items add column for_model text check (char_length(for_model) between 2 and 60);

-- Same columns, plus made_to_order / lead_days at the end; a made-to-order product counts as available.
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
    min(lead_days) filter (where made_to_order) as lead_days
  from public.variants
  where product_id = p.id and is_active
) v on true
where p.is_active and v.min_price_paise is not null;

-- Comma-separated ids of the caller's made-to-order lines that don't name a phone yet, or null.
create function private.missing_models(p_uid uuid, p_lines uuid[]) returns text
language sql stable set search_path = '' as $$
  select string_agg(v.id::text, ',' order by v.id)
  from public.cart_items c join public.variants v on v.id = c.variant_id
  where c.user_id = p_uid and c.variant_id = any(p_lines) and v.made_to_order and c.for_model is null
$$;

create or replace function public.restock_order(p_order_id uuid) returns void
language plpgsql set search_path = '' as $$
begin
  perform 1 from public.variants v
  where v.id in (select i.variant_id from public.order_items i where i.order_id = p_order_id and i.for_model is null)
  order by v.id for update;
  update public.variants v set stock = v.stock + i.qty
  from public.order_items i
  where i.order_id = p_order_id and v.id = i.variant_id and i.for_model is null;
end $$;

create or replace function public.place_order(p_address_id uuid, p_payment_method public.payment_method, p_coupon_code text default null)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_address public.addresses;
  v_settings public.store_settings;
  v_unavailable text;
  v_price jsonb;
  v_subtotal bigint; -- int lines can sum past int; checked below (ORDER_TOO_LARGE)
  v_fee bigint;
  v_discount bigint;
  v_promotion_id uuid;
  v_status public.order_status;
  v_order_id uuid;
  v_lines uuid[];
begin
  perform pg_advisory_xact_lock(hashtextextended('orders:' || v_uid, 0)); -- one checkout per user at a time (PENDING_LIMIT, per-user coupon uses)
  -- lock the cart lines and their variants in id order so concurrent checkouts can't deadlock. Every later
  -- statement reads only these locked lines: a line added mid-checkout must not land in the order unpriced.
  select array_agg(id) into v_lines from (
    select v.id from public.cart_items c join public.variants v on v.id = c.variant_id
    where c.user_id = v_uid order by v.id for update
  ) locked;
  if v_lines is null then raise exception 'CART_EMPTY'; end if;
  if cardinality(v_lines) > 10 then raise exception 'CART_LIMIT' using detail = 'at most 10 lines per order'; end if;

  select * into v_address from public.addresses where id = p_address_id and user_id = v_uid;
  if not found then raise exception 'ADDRESS_NOT_FOUND'; end if;

  -- unpaid online orders hold stock for 15 minutes: cap them so one account can't lock up the shop
  if p_payment_method = 'razorpay' and (select count(*) from public.orders
      where user_id = v_uid and status = 'pending_payment' and reserved_until > now()) >= 2 then
    raise exception 'PENDING_LIMIT';
  end if;

  v_unavailable := private.missing_models(v_uid, v_lines);
  if v_unavailable is not null then raise exception 'MODEL_REQUIRED' using detail = v_unavailable; end if;

  select string_agg(v.id::text, ',') into v_unavailable
  from public.cart_items c
  join public.variants v on v.id = c.variant_id
  join public.products p on p.id = v.product_id
  where c.user_id = v_uid and c.variant_id = any(v_lines)
    and (not v.is_active or not p.is_active or (not v.made_to_order and v.stock < c.qty));
  if v_unavailable is not null then
    raise exception 'OUT_OF_STOCK' using detail = v_unavailable; -- comma-separated variant ids
  end if;

  v_price := private.price_lines(v_uid, v_lines, p_coupon_code, p_payment_method, true);
  if v_price ->> 'coupon_error_detail' is not null then
    raise exception using message = v_price ->> 'coupon_error', detail = v_price ->> 'coupon_error_detail';
  elsif v_price ->> 'coupon_error' is not null then
    raise exception using message = v_price ->> 'coupon_error';
  end if;
  v_subtotal := (v_price ->> 'subtotal_paise')::bigint;
  v_fee := (v_price ->> 'delivery_fee_paise')::bigint;
  v_discount := (v_price ->> 'discount_paise')::bigint;
  v_promotion_id := (v_price #>> '{promotion,id}')::uuid;
  if v_subtotal + v_fee > 2147483647 then raise exception 'ORDER_TOO_LARGE'; end if; -- orders store int paise

  select * into v_settings from public.store_settings;
  if p_payment_method = 'cod'
     and (not v_settings.cod_enabled or v_subtotal + v_fee - v_discount > v_settings.cod_max_paise) then
    raise exception 'COD_UNAVAILABLE';
  end if;

  v_status := case p_payment_method when 'cod' then 'confirmed'::public.order_status else 'pending_payment' end;

  insert into public.orders
    (user_id, status, payment_method, subtotal_paise, delivery_fee_paise, discount_paise, total_paise, promotion_id,
     coupon_code, address, reserved_until)
  values (
    v_uid, v_status, p_payment_method, v_subtotal, v_fee, v_discount, v_subtotal + v_fee - v_discount, v_promotion_id,
    v_price #>> '{promotion,code}',
    jsonb_build_object(
      'name', v_address.name, 'phone', v_address.phone, 'line1', v_address.line1, 'line2', v_address.line2,
      'landmark', v_address.landmark, 'city', v_address.city, 'district', v_address.district, 'state', v_address.state,
      'pincode', v_address.pincode),
    case p_payment_method when 'razorpay' then now() + interval '15 minutes' end
  )
  returning id into v_order_id;

  insert into public.order_items
    (order_id, variant_id, product_id, product_name, variant_name, image_path, unit_price_paise, qty, gst_rate, discount_paise,
     for_model)
  select v_order_id, v.id, p.id, p.name, v.name,
    (select pi.path from public.product_images pi where pi.product_id = p.id order by pi.sort, pi.id limit 1),
    v.price_paise, c.qty, p.gst_rate,
    coalesce((select (l ->> 'discount_paise')::int from jsonb_array_elements(v_price -> 'lines') l
              where (l ->> 'variant_id')::uuid = v.id), 0),
    case when v.made_to_order then c.for_model end
  from public.cart_items c
  join public.variants v on v.id = c.variant_id
  join public.products p on p.id = v.product_id
  where c.user_id = v_uid and c.variant_id = any(v_lines);

  if v_promotion_id is not null then
    insert into public.promotion_redemptions (order_id, promotion_id, user_id, discount_paise)
    values (v_order_id, v_promotion_id, v_uid, v_discount);
  end if;

  update public.variants v set stock = v.stock - c.qty
  from public.cart_items c
  where c.user_id = v_uid and c.variant_id = v.id and c.variant_id = any(v_lines) and not v.made_to_order;

  delete from public.cart_items where user_id = v_uid and variant_id = any(v_lines);

  insert into public.order_events (order_id, status) values (v_order_id, v_status);
  return v_order_id;
end $$;

create or replace function public.quote_order(p_coupon_code text default null, p_payment_method public.payment_method default null)
returns json
language plpgsql security definer set search_path = '' as $$
declare
  v_lines uuid[];
  v_missing text;
begin
  select array_agg(variant_id order by variant_id) into v_lines from public.cart_items where user_id = auth.uid();
  if v_lines is null then raise exception 'CART_EMPTY'; end if;
  v_missing := private.missing_models(auth.uid(), v_lines);
  if v_missing is not null then raise exception 'MODEL_REQUIRED' using detail = v_missing; end if;
  return (private.price_lines(auth.uid(), v_lines, p_coupon_code, p_payment_method, false) - 'lines')::json;
end $$;

-- As before; a late payment revives the order without re-taking stock for made-to-order lines.
create or replace function public.mark_order_paid(p_order_id uuid, p_razorpay_payment_id text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_order public.orders;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  -- idempotent: verify-payment and both webhooks (payment.captured, order.paid) all land here
  -- shortcut: a second, different payment on an already-paid order is ignored; refund it from the Razorpay dashboard
  if v_order.payment_status in ('paid', 'refunded') then return; end if;
  if v_order.payment_method <> 'razorpay' then raise exception 'INVALID_TRANSITION'; end if;

  if v_order.status = 'cancelled' then
    -- reserved_until survives only an expiry; customer/admin cancels clear it and are never revived
    perform 1 from public.variants v
    where v.id in (select i.variant_id from public.order_items i where i.order_id = p_order_id)
    order by v.id for update;

    if v_order.reserved_until is null or exists (
      select 1 from public.order_items i left join public.variants v on v.id = i.variant_id
      where i.order_id = p_order_id and (v.id is null or (i.for_model is null and v.stock < i.qty))
    ) then
      update public.orders set payment_status = 'paid', razorpay_payment_id = p_razorpay_payment_id
      where id = p_order_id;
      insert into public.order_events (order_id, status, note)
      values (p_order_id, 'cancelled', 'Payment received after cancellation. A refund is due.');
      return;
    end if;

    update public.variants v set stock = v.stock - i.qty
    from public.order_items i
    where i.order_id = p_order_id and v.id = i.variant_id and i.for_model is null;
  elsif v_order.status <> 'pending_payment' then
    raise exception 'INVALID_TRANSITION';
  end if;

  update public.orders
  set status = 'confirmed', payment_status = 'paid', razorpay_payment_id = p_razorpay_payment_id, reserved_until = null
  where id = p_order_id;
  insert into public.order_events (order_id, status, note) values (p_order_id, 'confirmed', 'Payment received');
end $$;

-- As before; a refund's restock skips made-to-order lines and its note names the phone they were for.
create or replace function public.settle_refund(p_refund_id uuid, p_razorpay_refund_id text, p_status public.refund_status,
  p_speed text default null, p_failure text default null) returns text
language plpgsql security definer set search_path = '' as $$
declare
  r public.refunds;
  o public.orders;
  v_note text;
begin
  if p_refund_id is not null then
    select * into r from public.refunds where id = p_refund_id for update;
  else
    select * into r from public.refunds where razorpay_refund_id = p_razorpay_refund_id for update;
  end if;
  if not found then raise exception 'NOT_FOUND'; end if;
  if r.status <> 'pending' then return r.status; end if;

  update public.refunds set
    razorpay_refund_id = coalesce(razorpay_refund_id, p_razorpay_refund_id),
    speed_processed = coalesce(case when p_speed in ('instant', 'normal') then p_speed end, speed_processed),
    status = p_status,
    failure = case when p_status = 'failed' then left(coalesce(nullif(btrim(p_failure), ''), 'Razorpay couldn’t complete it.'), 300) end
  where id = r.id
  returning * into r;
  if r.status = 'pending' then return 'pending'; end if;

  select * into o from public.orders where id = r.order_id for update;
  if r.status = 'failed' then
    update public.order_items set refund_id = null where refund_id = r.id;
    perform private.notify_staff('staff_refund_failed', 'Refund failed for ' || o.number,
      private.inr(r.amount_paise) || ': ' || r.failure || ' Try again, or refund it another way and tap Mark refunded.',
      '/admin/orders/' || o.id, o.id);
    return 'failed';
  end if;

  if r.restock then
    perform 1 from public.variants v
    where v.id in (select i.variant_id from public.order_items i where i.refund_id = r.id and i.for_model is null)
    order by v.id for update;
    update public.variants v set stock = v.stock + i.qty
    from public.order_items i
    where i.refund_id = r.id and v.id = i.variant_id and i.for_model is null;
  end if;

  v_note := 'Refund of ' || private.inr(r.amount_paise)
    || case when r.full_refund then '' else ' for '
         || (select string_agg(i.product_name || coalesce(' for ' || i.for_model, ''), ', ' order by i.unit_price_paise desc, i.id)
             from public.order_items i where i.refund_id = r.id) end
    || case when r.speed_processed = 'instant'
         then ' sent instantly. It should show in your account within minutes.'
         else ' issued to your original payment method. Banks usually take 5–7 working days to show it.' end;

  if (select sum(f.amount_paise) from public.refunds f where f.order_id = o.id and f.status = 'processed') >= o.total_paise then
    -- the payment_status change notifies the customer; the note below becomes that notification's text
    update public.orders set payment_status = 'refunded',
      status = case when status = 'delivered' then 'refunded'::public.order_status else status end
    where id = o.id
    returning * into o;
  else
    -- service-role timeline notes don't notify by themselves (notify_order_event), so say it here
    perform private.notify(o.user_id, 'order_refunded', 'Refund of ' || private.inr(r.amount_paise) || ' for ' || o.number,
      v_note, '/orders/' || o.id, o.id);
  end if;
  insert into public.order_events (order_id, status, note) values (o.id, o.status, private.clip(v_note, 500));
  return 'processed';
end $$;

-- "₹249 · Cash on delivery · Back cover for Galaxy A15 + 1 more · Waidhan", for staff
create or replace function private.order_summary(o public.orders) returns text
language sql stable set search_path = '' as $$
  select concat_ws(' · ', private.inr(o.total_paise),
    case o.payment_method when 'cod' then 'Cash on delivery' else 'Paid online' end,
    (select (array_agg(i.product_name || coalesce(' for ' || i.for_model, '') order by i.unit_price_paise desc, i.id))[1]
        || case when count(*) > 1 then ' + ' || (count(*) - 1) || ' more' else '' end
     from public.order_items i where i.order_id = o.id),
    o.address ->> 'city')
$$;

-- Model suggestions for the product page, learned with no owner work: the catalog's phone names, then the models
-- customers ordered for (orders the shop took on, newest first), deduped ignoring case and spaces.
-- shortcut: scans every made-to-order line; add an index on order_items (for_model) past ~100k lines.
create function public.phone_models() returns json
language sql stable security definer set search_path = '' as $$
  select coalesce(json_agg(name order by rank, at desc), '[]') from (
    select name, rank, at from (
      select distinct on (lower(replace(name, ' ', ''))) name, rank, at from (
        select p.name, 0 as rank, p.created_at as at
        from public.products p join public.categories c on c.id = p.category_id
        where p.is_active and c.kind = 'phone'
        union all
        select i.for_model, 1, o.created_at
        from public.order_items i join public.orders o on o.id = i.order_id
        where i.for_model is not null and o.status not in ('pending_payment', 'cancelled')
      ) s
      order by lower(replace(name, ' ', '')), rank, at desc
    ) d
    order by rank, at desc
    limit 300
  ) t
$$;

revoke execute on function private.missing_models(uuid, uuid[]) from public, anon, authenticated;
revoke execute on function public.phone_models() from public, anon, authenticated, service_role;
grant execute on function public.phone_models() to anon, authenticated;
