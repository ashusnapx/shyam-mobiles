-- Order, repair, payment and admin RPCs, plus the unpaid-order expiry job.
-- Errors are raised with message = a bare code (errcode P0001); details go in DETAIL.
-- Lock order everywhere: orders first, then variants in id order.

-- Internal: put an order's items back into stock.
create function public.restock_order(p_order_id uuid) returns void
language plpgsql set search_path = '' as $$
begin
  perform 1 from public.variants v
  where v.id in (select i.variant_id from public.order_items i where i.order_id = p_order_id)
  order by v.id for update;
  update public.variants v set stock = v.stock + i.qty
  from public.order_items i
  where i.order_id = p_order_id and v.id = i.variant_id;
end $$;

-- Customer ------------------------------------------------------------------

create function public.place_order(p_address_id uuid, p_payment_method public.payment_method)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_address public.addresses;
  v_settings public.store_settings;
  v_unavailable text;
  v_subtotal int;
  v_fee int;
  v_status public.order_status;
  v_order_id uuid;
  v_lines uuid[];
begin
  -- lock the cart lines and their variants in id order so concurrent checkouts can't deadlock. Every later
  -- statement reads only these locked lines: a line added mid-checkout must not land in the order unpriced.
  select array_agg(id) into v_lines from (
    select v.id from public.cart_items c join public.variants v on v.id = c.variant_id
    where c.user_id = v_uid order by v.id for update
  ) locked;
  if v_lines is null then raise exception 'CART_EMPTY'; end if;

  select * into v_address from public.addresses where id = p_address_id and user_id = v_uid;
  if not found then raise exception 'ADDRESS_NOT_FOUND'; end if;

  select string_agg(v.id::text, ',') into v_unavailable
  from public.cart_items c
  join public.variants v on v.id = c.variant_id
  join public.products p on p.id = v.product_id
  where c.user_id = v_uid and c.variant_id = any(v_lines) and (not v.is_active or not p.is_active or v.stock < c.qty);
  if v_unavailable is not null then
    raise exception 'OUT_OF_STOCK' using detail = v_unavailable; -- comma-separated variant ids
  end if;

  select sum(v.price_paise * c.qty) into v_subtotal
  from public.cart_items c join public.variants v on v.id = c.variant_id
  where c.user_id = v_uid and c.variant_id = any(v_lines);

  select * into v_settings from public.store_settings;
  v_fee := case when v_subtotal >= v_settings.free_delivery_min_paise then 0 else v_settings.delivery_fee_paise end;

  if p_payment_method = 'cod'
     and (not v_settings.cod_enabled or v_subtotal + v_fee > v_settings.cod_max_paise) then
    raise exception 'COD_UNAVAILABLE';
  end if;

  v_status := case p_payment_method when 'cod' then 'confirmed'::public.order_status else 'pending_payment' end;

  insert into public.orders
    (user_id, status, payment_method, subtotal_paise, delivery_fee_paise, total_paise, address, reserved_until)
  values (
    v_uid, v_status, p_payment_method, v_subtotal, v_fee, v_subtotal + v_fee,
    jsonb_build_object(
      'name', v_address.name, 'phone', v_address.phone, 'line1', v_address.line1, 'line2', v_address.line2,
      'landmark', v_address.landmark, 'city', v_address.city, 'district', v_address.district, 'state', v_address.state,
      'pincode', v_address.pincode),
    case p_payment_method when 'razorpay' then now() + interval '15 minutes' end
  )
  returning id into v_order_id;

  insert into public.order_items
    (order_id, variant_id, product_id, product_name, variant_name, image_path, unit_price_paise, qty, gst_rate)
  select v_order_id, v.id, p.id, p.name, v.name,
    (select pi.path from public.product_images pi where pi.product_id = p.id order by pi.sort, pi.id limit 1),
    v.price_paise, c.qty, p.gst_rate
  from public.cart_items c
  join public.variants v on v.id = c.variant_id
  join public.products p on p.id = v.product_id
  where c.user_id = v_uid and c.variant_id = any(v_lines);

  update public.variants v set stock = v.stock - c.qty
  from public.cart_items c
  where c.user_id = v_uid and c.variant_id = v.id and c.variant_id = any(v_lines);

  delete from public.cart_items where user_id = v_uid and variant_id = any(v_lines);

  insert into public.order_events (order_id, status) values (v_order_id, v_status);
  return v_order_id;
end $$;

create function public.cancel_order(p_order_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_status public.order_status;
  v_paid boolean;
begin
  select status, payment_status = 'paid' into v_status, v_paid from public.orders
  where id = p_order_id and user_id = auth.uid() for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if v_status not in ('pending_payment', 'confirmed') then raise exception 'INVALID_TRANSITION'; end if;

  perform public.restock_order(p_order_id);
  -- reserved_until = null marks a deliberate cancel: a late payment won't revive it (see mark_order_paid)
  update public.orders set status = 'cancelled', reserved_until = null where id = p_order_id;
  insert into public.order_events (order_id, status, note) values (p_order_id, 'cancelled',
    case when v_paid then 'Cancelled by you. A full refund to your original payment method is on its way; banks usually take 5–7 working days.' else 'Cancelled by you.' end);
end $$;

create function public.cancel_repair(p_booking_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_status public.repair_status;
begin
  select status into v_status from public.repair_bookings
  where id = p_booking_id and user_id = auth.uid() for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if v_status not in ('requested', 'confirmed') then raise exception 'INVALID_TRANSITION'; end if;

  update public.repair_bookings set status = 'cancelled' where id = p_booking_id;
end $$;

-- Admin ---------------------------------------------------------------------

-- p_status = current status only edits courier/tracking (and adds a timeline note if given).
create function public.admin_update_order(
  p_order_id uuid, p_status public.order_status,
  p_note text default null, p_courier text default null, p_tracking_number text default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_order public.orders;
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;

  if p_status <> v_order.status and (v_order.status, p_status) not in (
    ('pending_payment', 'cancelled'),
    ('confirmed', 'packed'), ('confirmed', 'cancelled'),
    ('packed', 'shipped'), ('packed', 'cancelled'),
    ('shipped', 'delivered'),
    ('delivered', 'refunded')
  ) then
    raise exception 'INVALID_TRANSITION' using detail = v_order.status || ' -> ' || p_status;
  end if;

  if p_status = 'cancelled' and v_order.status <> 'cancelled' then
    perform public.restock_order(p_order_id);
  end if;

  update public.orders set
    status = p_status,
    payment_status = case
      when p_status = 'delivered' and payment_method = 'cod' then 'paid'
      when p_status = 'refunded' then 'refunded'
      else payment_status end,
    reserved_until = case when p_status = 'cancelled' then null else reserved_until end,
    courier = coalesce(p_courier, courier),
    tracking_number = coalesce(p_tracking_number, tracking_number)
  where id = p_order_id;

  if p_status = 'cancelled' and v_order.status <> 'cancelled' and v_order.payment_status = 'paid' then
    p_note := concat_ws(' ', coalesce(p_note, 'Cancelled by the store.'), 'A full refund to your original payment method is on its way; banks usually take 5–7 working days.');
  end if;

  if p_status <> v_order.status or p_note is not null then
    insert into public.order_events (order_id, status, note) values (p_order_id, p_status, p_note);
  end if;
end $$;

create function public.admin_set_imeis(p_order_item_id uuid, p_imeis text[]) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_qty int;
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;

  select qty into v_qty from public.order_items where id = p_order_item_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;

  if cardinality(p_imeis) is distinct from v_qty or array_ndims(p_imeis) <> 1
     or exists (select 1 from unnest(p_imeis) x where x is null or x !~ '^[0-9]{15}$')
     or (select count(distinct x) from unnest(p_imeis) x) <> v_qty then
    raise exception 'INVALID_IMEIS' using detail = 'need ' || v_qty || ' distinct 15-digit IMEIs';
  end if;

  update public.order_items set imeis = p_imeis where id = p_order_item_id;
end $$;

create function public.admin_dashboard() returns json
language plpgsql stable security definer set search_path = '' as $$
declare
  v_today timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;

  return (
    select json_build_object(
      'orders_today', count(*) filter (where o.created_at >= v_today and o.status in ('confirmed', 'packed', 'shipped', 'delivered')),
      'revenue_today_paise', coalesce(sum(o.total_paise) filter (where o.created_at >= v_today and o.status in ('confirmed', 'packed', 'shipped', 'delivered')), 0),
      'open_orders', count(*) filter (where o.status in ('confirmed', 'packed', 'shipped')),
      'needs_refund', count(*) filter (where o.status = 'cancelled' and o.payment_status = 'paid'),
      'low_stock', (select count(*) from public.variants v join public.products p on p.id = v.product_id
                    where v.is_active and p.is_active and v.stock <= 3),
      'open_repairs', (select count(*) from public.repair_bookings r where r.status not in ('completed', 'cancelled'))
    )
    from public.orders o
  );
end $$;

-- Payments (service_role only: called by Edge Functions) --------------------

create function public.mark_order_paid(p_order_id uuid, p_razorpay_payment_id text) returns void
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
      where i.order_id = p_order_id and (v.id is null or v.stock < i.qty)
    ) then
      update public.orders set payment_status = 'paid', razorpay_payment_id = p_razorpay_payment_id
      where id = p_order_id;
      insert into public.order_events (order_id, status, note)
      values (p_order_id, 'cancelled', 'Payment received after cancellation. A refund is due.');
      return;
    end if;

    update public.variants v set stock = v.stock - i.qty
    from public.order_items i
    where i.order_id = p_order_id and v.id = i.variant_id;
  elsif v_order.status <> 'pending_payment' then
    raise exception 'INVALID_TRANSITION';
  end if;

  update public.orders
  set status = 'confirmed', payment_status = 'paid', razorpay_payment_id = p_razorpay_payment_id, reserved_until = null
  where id = p_order_id;
  insert into public.order_events (order_id, status, note) values (p_order_id, 'confirmed', 'Payment received');
end $$;

-- payment.failed webhook: the order stays payable (retry) until it expires.
create function public.mark_payment_failed(p_order_id uuid) returns void
language sql security definer set search_path = '' as $$
  update public.orders set payment_status = 'failed'
  where id = p_order_id and status = 'pending_payment' and payment_status = 'pending';
$$;

create function public.mark_order_refunded(p_razorpay_payment_id text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_status public.order_status;
begin
  update public.orders set payment_status = 'refunded'
  where razorpay_payment_id = p_razorpay_payment_id and payment_status = 'paid'
  returning id, status into v_id, v_status;

  if found then
    insert into public.order_events (order_id, status, note) values (v_id, v_status, 'Refund issued. Banks usually take 5–7 working days to show it.');
  elsif not exists (select 1 from public.orders where razorpay_payment_id = p_razorpay_payment_id) then
    raise exception 'NOT_FOUND';
  end if;
end $$;

-- Expiry --------------------------------------------------------------------

create function public.expire_unpaid_orders() returns int
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_count int := 0;
begin
  for v_id in
    select id from public.orders
    where status = 'pending_payment' and reserved_until < now()
    for update skip locked
  loop
    perform public.restock_order(v_id);
    update public.orders set status = 'cancelled' where id = v_id; -- keeps reserved_until: marks an expiry
    insert into public.order_events (order_id, status, note) values (v_id, 'cancelled', 'Payment not received in time');
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

-- https://supabase.com/docs/guides/cron
create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule('expire-unpaid-orders', '*/5 * * * *', 'select public.expire_unpaid_orders()');
-- pg_cron never prunes its run log (288 rows a day from the job above)
select cron.schedule('job-run-details-cleanup', '0 3 * * *',
  $$delete from cron.job_run_details where end_time < now() - interval '7 days'$$);

-- Grants: Supabase grants execute on new functions to anon/authenticated by default; undo that.

revoke execute on function
  public.restock_order(uuid),
  public.place_order(uuid, public.payment_method),
  public.cancel_order(uuid),
  public.cancel_repair(uuid),
  public.admin_update_order(uuid, public.order_status, text, text, text),
  public.admin_set_imeis(uuid, text[]),
  public.admin_dashboard(),
  public.mark_order_paid(uuid, text),
  public.mark_payment_failed(uuid),
  public.mark_order_refunded(text),
  public.expire_unpaid_orders()
from public, anon, authenticated, service_role;

-- admin_* check is_admin() inside
grant execute on function
  public.place_order(uuid, public.payment_method),
  public.cancel_order(uuid),
  public.cancel_repair(uuid),
  public.admin_update_order(uuid, public.order_status, text, text, text),
  public.admin_set_imeis(uuid, text[]),
  public.admin_dashboard()
to authenticated;

grant execute on function
  public.mark_order_paid(uuid, text),
  public.mark_payment_failed(uuid),
  public.mark_order_refunded(text),
  public.expire_unpaid_orders()
to service_role;
