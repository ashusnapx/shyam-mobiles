-- Refunds from the admin screen (docs/SPEC.md, "Payments: refunds, payment links, saved cards, disputes").
-- The refund-payment Edge Function asks admin_start_refund what to refund (amounts from the order rows, never from
-- the phone), calls Razorpay's Refunds API with the refund's id as its idempotency key, and records the reply with
-- settle_refund; the refund.processed / refund.failed webhooks settle it the same way. Refunds made in the Razorpay
-- dashboard still reach mark_order_refunded (full ones only), and staff can still "Mark refunded" by hand.

create type public.refund_status as enum ('pending', 'processed', 'failed');

create table public.refunds (
  id uuid primary key default gen_random_uuid(), -- also the Razorpay idempotency key and receipt
  order_id uuid not null references public.orders on delete cascade,
  amount_paise int not null check (amount_paise >= 100), -- Razorpay's minimum refund is ₹1
  full_refund boolean not null, -- everything not yet refunded, delivery included; else the lines pointing here
  restock boolean not null default false, -- staff's call: those lines go back into stock once it's processed
  instant boolean not null default false, -- Razorpay's speed "optimum": minutes instead of days, for a fee
  status public.refund_status not null default 'pending',
  razorpay_refund_id text unique check (razorpay_refund_id ~ '^[A-Za-z0-9_]{1,64}$'),
  speed_processed text check (speed_processed in ('instant', 'normal')),
  failure text check (char_length(failure) <= 300),
  created_by uuid references auth.users on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index refunds_order_idx on public.refunds (order_id, created_at);
create index refunds_created_by_idx on public.refunds (created_by) where created_by is not null; -- FK
-- One refund in flight per order: a retry after a timeout reuses it (and its key) instead of paying out twice.
create unique index refunds_one_pending on public.refunds (order_id) where status = 'pending';
create trigger set_updated_at before update on public.refunds for each row execute function public.set_updated_at();

-- The refund that pays this line back (pending or processed); cleared again if that refund fails.
alter table public.order_items add column refund_id uuid references public.refunds on delete set null;
create index order_items_refund_idx on public.order_items (refund_id) where refund_id is not null;

alter table public.refunds enable row level security;
-- the subquery is itself filtered by the orders policy: the customer's own orders, or any for staff
create policy "own or admin read" on public.refunds for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id));
revoke all on public.refunds from public, anon, authenticated, service_role;
grant select on public.refunds to authenticated;
grant select, insert, update, delete on public.refunds to service_role;

-- What to refund, from the database. p_items null: everything not yet refunded, delivery included, and only on a
-- cancelled or delivered order (one still being fulfilled is cancelled first). Otherwise those lines at what was paid
-- for them (price × qty − their share of the discount), on an order that isn't cancelled. A pending refund that
-- Razorpay never answered (timeout) is handed back as it was, so the retry reuses its idempotency key.
create function public.admin_start_refund(p_staff uuid, p_order_id uuid, p_items uuid[] default null,
  p_restock boolean default false, p_instant boolean default false) returns json
language plpgsql security definer set search_path = '' as $$
declare
  o public.orders;
  r public.refunds;
  v_left bigint;
  v_amount bigint;
  v_lines uuid[];
begin
  if p_staff is null or not exists (select 1 from public.admins where user_id = p_staff) then
    raise exception 'FORBIDDEN';
  end if;
  select * into o from public.orders where id = p_order_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;

  select * into r from public.refunds where order_id = o.id and status = 'pending';
  if found and r.razorpay_refund_id is null then
    return json_build_object('refund_id', r.id, 'amount_paise', r.amount_paise, 'payment_id', o.razorpay_payment_id,
      'instant', r.instant, 'order_number', o.number, 'retry', true);
  elsif found then
    raise exception 'REFUND_IN_PROGRESS';
  end if;

  if o.payment_method <> 'razorpay' or o.payment_status <> 'paid' or o.razorpay_payment_id is null then
    raise exception 'REFUND_NOT_ALLOWED' using detail = 'Only an order paid online, and not yet refunded, can be refunded here.';
  end if;
  v_left := o.total_paise - coalesce((select sum(f.amount_paise) from public.refunds f
                                      where f.order_id = o.id and f.status = 'processed'), 0);

  if p_items is null then
    if o.status not in ('cancelled', 'delivered') then
      raise exception 'REFUND_NOT_ALLOWED' using detail = 'Cancel the order first, or refund single items.';
    end if;
    v_amount := v_left;
    select coalesce(array_agg(i.id), '{}') into v_lines from public.order_items i
    where i.order_id = o.id and i.refund_id is null;
  else
    if o.status = 'cancelled' then
      raise exception 'REFUND_NOT_ALLOWED' using detail = 'A cancelled order is refunded in full.';
    end if;
    select array_agg(i.id), sum(i.unit_price_paise::bigint * i.qty - i.discount_paise) into v_lines, v_amount
    from public.order_items i
    where i.order_id = o.id and i.id = any(p_items) and i.refund_id is null;
    if v_lines is null or cardinality(v_lines) <> (select count(distinct x) from unnest(p_items) x) then
      raise exception 'BAD_REQUEST' using detail = 'Pick items of this order that aren’t refunded yet.';
    end if;
  end if;
  if v_amount < 100 or v_amount > v_left then
    raise exception 'REFUND_NOT_ALLOWED' using detail = 'There’s nothing left to refund on this order.';
  end if;

  insert into public.refunds (order_id, amount_paise, full_refund, restock, instant, created_by)
  values (o.id, v_amount, p_items is null, p_restock and o.status <> 'cancelled', -- a cancel already restocked
          coalesce(p_instant, false), p_staff)
  returning * into r;
  update public.order_items set refund_id = r.id where id = any(v_lines);
  return json_build_object('refund_id', r.id, 'amount_paise', r.amount_paise, 'payment_id', o.razorpay_payment_id,
    'instant', r.instant, 'order_number', o.number, 'retry', false);
end $$;

-- Razorpay's answer for one of our refunds: refund-payment's create reply (or a definite refusal), and the
-- refund.processed / refund.failed webhooks (found by our id in its notes, else by Razorpay's id). Idempotent: a
-- settled refund stays as it is. Processed: restock if staff chose it, the timeline note (which is the customer's
-- notification), and once everything is paid back payment_status = refunded (a delivered order becomes refunded).
-- Failed: the lines are free to refund again and staff are told. Returns the refund's status.
create function public.settle_refund(p_refund_id uuid, p_razorpay_refund_id text, p_status public.refund_status,
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
    where v.id in (select i.variant_id from public.order_items i where i.refund_id = r.id)
    order by v.id for update;
    update public.variants v set stock = v.stock + i.qty
    from public.order_items i
    where i.refund_id = r.id and v.id = i.variant_id;
  end if;

  v_note := 'Refund of ' || private.inr(r.amount_paise)
    || case when r.full_refund then '' else ' for '
         || (select string_agg(i.product_name, ', ' order by i.unit_price_paise desc, i.id)
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

revoke execute on function
  public.admin_start_refund(uuid, uuid, uuid[], boolean, boolean),
  public.settle_refund(uuid, text, public.refund_status, text, text)
from public, anon, authenticated;

-- service_role only: the refund-payment and razorpay-webhook Edge Functions (refund-payment checks staff first)
grant execute on function
  public.admin_start_refund(uuid, uuid, uuid[], boolean, boolean),
  public.settle_refund(uuid, text, public.refund_status, text, text)
to service_role;
