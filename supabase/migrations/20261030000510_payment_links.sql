-- Payment links on WhatsApp (docs/SPEC.md, "Payments: refunds, payment links, saved cards, disputes"): staff make a
-- Razorpay Payment Link for an order (its total, from the database) or for an amount they type (wholesale and phone
-- orders), and send it on WhatsApp. The payment-link Edge Function creates and cancels them; the payment_link.paid
-- webhook marks the link paid and, for an order, the order paid (mark_order_paid's rules); payment_link.cancelled and
-- payment_link.expired close it.

create table public.payment_links (
  id uuid primary key default gen_random_uuid(), -- also the link's reference_id at Razorpay (unique per link)
  order_id uuid references public.orders on delete set null,
  amount_paise int not null check (amount_paise between 100 and 500000000), -- ₹1 to ₹50 lakh
  description text not null check (char_length(description) between 1 and 200 and public.is_clean_text(description)),
  customer_name text check (char_length(customer_name) between 1 and 60 and public.is_clean_text(customer_name)),
  customer_phone public.in_phone not null,
  status text not null default 'created' check (status in ('created', 'paid', 'cancelled', 'expired')),
  razorpay_link_id text unique check (razorpay_link_id ~ '^[A-Za-z0-9_]{1,64}$'),
  short_url text check (char_length(short_url) <= 200 and short_url ~ '^https://[A-Za-z0-9./_-]+$'),
  razorpay_payment_id text check (razorpay_payment_id ~ '^[A-Za-z0-9_]{1,64}$'),
  expires_at timestamptz not null,
  created_by uuid references auth.users on delete set null,
  created_at timestamptz not null default now(),
  paid_at timestamptz
);
create index payment_links_created_idx on public.payment_links (created_at desc);
create index payment_links_created_by_idx on public.payment_links (created_by) where created_by is not null; -- FK
-- one open link per order: making another sends the same one again
create unique index payment_links_one_open on public.payment_links (order_id) where status = 'created';
create index payment_links_order_idx on public.payment_links (order_id) where order_id is not null;

alter table public.payment_links enable row level security;
create policy "admin read" on public.payment_links for select to authenticated using ((select public.is_admin()));
revoke all on public.payment_links from public, anon, authenticated, service_role;
grant select on public.payment_links to authenticated;
grant select, insert, update, delete on public.payment_links to service_role;

-- A new link row (the Edge Function then creates it at Razorpay and stores its id and URL). For an order: its total,
-- the delivery name and phone, while it's unpaid and not cancelled; an open link for it is returned instead
-- (`reused`), after closing one whose time ran out. Otherwise p_amount_paise, p_phone, p_name and p_description.
create function public.admin_new_payment_link(p_staff uuid, p_order_id uuid default null, p_amount_paise int default null,
  p_phone text default null, p_name text default null, p_description text default null) returns json
language plpgsql security definer set search_path = '' as $$
declare
  o public.orders;
  l public.payment_links;
  v_reused boolean := false;
begin
  if p_staff is null or not exists (select 1 from public.admins where user_id = p_staff) then
    raise exception 'FORBIDDEN';
  end if;

  if p_order_id is not null then
    select * into o from public.orders where id = p_order_id for update;
    if not found then raise exception 'NOT_FOUND'; end if;
    if o.payment_status not in ('pending', 'failed') or o.status in ('cancelled', 'refunded') then
      raise exception 'LINK_NOT_ALLOWED' using detail = 'This order is already paid or cancelled.';
    end if;
    update public.payment_links set status = 'expired'
    where order_id = o.id and status = 'created' and expires_at <= now();
    select * into l from public.payment_links where order_id = o.id and status = 'created';
    v_reused := found;
    if not found then
      insert into public.payment_links (order_id, amount_paise, description, customer_name, customer_phone, expires_at, created_by)
      values (o.id, o.total_paise, 'Shyam Mobiles order ' || o.number, private.clip(o.address ->> 'name', 60),
              o.address ->> 'phone', now() + interval '3 days', p_staff)
      returning * into l;
    end if;
  else
    if p_amount_paise is null or p_phone is null or nullif(btrim(p_description), '') is null then
      raise exception 'BAD_REQUEST' using detail = 'Add the amount, the customer’s mobile number and what it’s for.';
    end if;
    insert into public.payment_links (amount_paise, description, customer_name, customer_phone, expires_at, created_by)
    values (p_amount_paise, btrim(p_description), nullif(btrim(p_name), ''), p_phone, now() + interval '3 days', p_staff)
    returning * into l;
  end if;

  return json_build_object('id', l.id, 'order_id', l.order_id, 'amount_paise', l.amount_paise,
    'description', l.description, 'customer_name', l.customer_name, 'customer_phone', l.customer_phone,
    'status', l.status, 'short_url', l.short_url, 'expires_at', l.expires_at, 'reused', v_reused);
end $$;

-- payment_link.paid. Idempotent. The amount must be the link's. For an order: an online order goes through
-- mark_order_paid (a late payment revives an expired order if stock allows, else it needs a refund); a cash-on-delivery
-- order becomes paid online (a cancelled one then needs a refund); an order paid some other way meanwhile is left as
-- it is and staff are told to refund the second payment.
create function public.mark_link_paid(p_razorpay_link_id text, p_razorpay_payment_id text, p_amount_paise int) returns void
language plpgsql security definer set search_path = '' as $$
declare
  l public.payment_links;
  o public.orders;
begin
  select * into l from public.payment_links where razorpay_link_id = p_razorpay_link_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if l.status = 'paid' then return; end if;
  if p_amount_paise is distinct from l.amount_paise then raise exception 'AMOUNT_MISMATCH'; end if;

  update public.payment_links set status = 'paid', razorpay_payment_id = p_razorpay_payment_id, paid_at = now()
  where id = l.id;

  if l.order_id is null then
    perform private.notify_staff('staff_link_paid', private.inr(l.amount_paise) || ' paid by payment link',
      concat_ws(' · ', l.customer_name, l.customer_phone, l.description), null);
    return;
  end if;

  select * into o from public.orders where id = l.order_id for update;
  if o.payment_status in ('paid', 'refunded') then
    perform private.notify_staff('staff_refund_needed', 'Second payment for ' || o.number,
      private.inr(l.amount_paise) || ' came by payment link after the order was paid. Refund payment '
        || p_razorpay_payment_id || ' in the Razorpay dashboard.', '/admin/orders/' || o.id, o.id);
  elsif o.payment_method = 'razorpay' then
    perform public.mark_order_paid(o.id, p_razorpay_payment_id);
  else
    update public.orders set payment_method = 'razorpay', payment_status = 'paid', razorpay_payment_id = p_razorpay_payment_id
    where id = o.id;
    insert into public.order_events (order_id, status, note) values (o.id, o.status,
      case when o.status = 'cancelled' then 'Payment received after cancellation. A refund is due.'
           else 'Paid online with a payment link.' end);
  end if;
end $$;

-- payment_link.cancelled / payment_link.expired (and the Edge Function's cancel): only an open link closes.
create function public.close_payment_link(p_razorpay_link_id text, p_status text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_status not in ('cancelled', 'expired') then raise exception 'BAD_REQUEST'; end if;
  update public.payment_links set status = p_status where razorpay_link_id = p_razorpay_link_id and status = 'created';
end $$;

revoke execute on function
  public.admin_new_payment_link(uuid, uuid, int, text, text, text),
  public.mark_link_paid(text, text, int),
  public.close_payment_link(text, text)
from public, anon, authenticated;

-- service_role only: the payment-link and razorpay-webhook Edge Functions (payment-link checks staff first)
grant execute on function
  public.admin_new_payment_link(uuid, uuid, int, text, text, text),
  public.mark_link_paid(text, text, int),
  public.close_payment_link(text, text)
to service_role;
