-- Staff can close a "needs refund" order themselves (docs/FLOWS.md). Until now only the refund.processed webhook
-- could, and it skips partial refunds and refunds made outside Razorpay (cash, UPI), so the dashboard's Needs refund
-- stayed red and the customer never saw Refunded. admin_update_order(cancelled → refunded) on a paid, cancelled order
-- now does what mark_order_refunded does: payment_status = refunded, the status stays cancelled (so its coupon use
-- stays given back), and a timeline note.
-- Also: fixing the courier or tracking number (p_status = the current status) now leaves a timeline note, so the
-- customer sees the change. Everything else is unchanged from 20261028000200_rpcs.sql.

create or replace function public.admin_update_order(
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

  if v_order.status = 'cancelled' and p_status = 'refunded' then
    if v_order.payment_status <> 'paid' then
      raise exception 'INVALID_TRANSITION' using detail = 'only a paid, cancelled order can be refunded';
    end if;
    update public.orders set payment_status = 'refunded' where id = p_order_id;
    insert into public.order_events (order_id, status, note) values (p_order_id, 'cancelled',
      coalesce(p_note, 'Refund issued. Banks usually take 5–7 working days to show it.'));
    return;
  end if;

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

  if p_status = v_order.status and p_note is null
     and (coalesce(p_courier, v_order.courier) is distinct from v_order.courier
          or coalesce(p_tracking_number, v_order.tracking_number) is distinct from v_order.tracking_number) then
    p_note := 'Courier and tracking updated: '
      || concat_ws(' · ', coalesce(p_courier, v_order.courier), coalesce(p_tracking_number, v_order.tracking_number));
  end if;

  if p_status = 'cancelled' and v_order.status <> 'cancelled' and v_order.payment_status = 'paid' then
    p_note := concat_ws(' ', coalesce(p_note, 'Cancelled by the store.'), 'A full refund to your original payment method is on its way; banks usually take 5–7 working days.');
  end if;

  if p_status <> v_order.status or p_note is not null then
    insert into public.order_events (order_id, status, note) values (p_order_id, p_status, p_note);
  end if;
end $$;
