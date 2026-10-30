-- Saved cards and dispute alerts (docs/SPEC.md, "Payments: refunds, payment links, saved cards, disputes").

-- One Razorpay customer per account, made by create-payment on the first online payment and passed to Checkout, so a
-- returning buyer sees their saved cards (the card tokens stay with Razorpay, under RBI's tokenisation rules).
-- Server-only: no client role can read it. Deleting the account deletes the row; delete-account first deletes the
-- saved cards at Razorpay (Razorpay has no API to delete the customer itself).
create table public.razorpay_customers (
  user_id uuid primary key references auth.users on delete cascade,
  customer_id text not null unique check (customer_id ~ '^cust_[A-Za-z0-9]{1,59}$'),
  created_at timestamptz not null default now()
);
alter table public.razorpay_customers enable row level security; -- no policies: no client access
revoke all on public.razorpay_customers from public, anon, authenticated, service_role;
grant select, insert, update, delete on public.razorpay_customers to service_role;

-- Chargebacks and other disputes, from the payment.dispute.* webhooks. Staff get a notification for each event with
-- the respond-by date; they answer with evidence (invoice, IMEI, delivery proof) in the Razorpay dashboard.
create table public.disputes (
  id text primary key check (id ~ '^[A-Za-z0-9_]{1,64}$'), -- Razorpay's disp_… id
  order_id uuid references public.orders on delete set null,
  razorpay_payment_id text not null check (razorpay_payment_id ~ '^[A-Za-z0-9_]{1,64}$'),
  amount_paise int not null check (amount_paise >= 0),
  status text not null check (status ~ '^[a-z_]{1,30}$'), -- open, under_review, won, lost, closed
  phase text check (phase ~ '^[a-z_]{1,30}$'), -- fraud, retrieval, chargeback, pre_arbitration, arbitration
  reason_code text check (char_length(reason_code) <= 100),
  reason text check (char_length(reason) <= 500),
  respond_by timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index disputes_order_idx on public.disputes (order_id) where order_id is not null;
create trigger set_updated_at before update on public.disputes for each row execute function public.set_updated_at();

alter table public.disputes enable row level security;
create policy "admin read" on public.disputes for select to authenticated using ((select public.is_admin()));
revoke all on public.disputes from public, anon, authenticated, service_role;
grant select on public.disputes to authenticated;
grant select, insert, update, delete on public.disputes to service_role;

-- Every payment.dispute.* event: upsert the dispute (its order from the payment, an order's or a payment link's) and
-- tell staff. Replays never get here (the webhook dedupes on the event id).
create function public.record_dispute(p_id text, p_payment_id text, p_amount_paise int, p_status text, p_phase text,
  p_reason_code text, p_reason text, p_respond_by timestamptz) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_order uuid := coalesce(
    (select o.id from public.orders o where o.razorpay_payment_id = p_payment_id),
    (select l.order_id from public.payment_links l where l.razorpay_payment_id = p_payment_id));
  v_number text := (select o.number from public.orders o where o.id = v_order);
  v_what text := coalesce(v_number, 'payment ' || p_payment_id);
  v_status text := lower(coalesce(p_status, 'open'));
begin
  insert into public.disputes (id, order_id, razorpay_payment_id, amount_paise, status, phase, reason_code, reason, respond_by)
  values (p_id, v_order, p_payment_id, greatest(coalesce(p_amount_paise, 0), 0), v_status, lower(p_phase),
          left(p_reason_code, 100), left(p_reason, 500), p_respond_by)
  on conflict (id) do update set
    status = excluded.status, phase = coalesce(excluded.phase, public.disputes.phase),
    amount_paise = excluded.amount_paise, reason_code = coalesce(excluded.reason_code, public.disputes.reason_code),
    reason = coalesce(excluded.reason, public.disputes.reason), respond_by = coalesce(excluded.respond_by, public.disputes.respond_by),
    order_id = coalesce(public.disputes.order_id, excluded.order_id);

  perform private.notify_staff('staff_dispute',
    case v_status
      when 'won' then 'Dispute won on ' || v_what
      when 'lost' then 'Dispute lost on ' || v_what
      when 'closed' then 'Dispute closed on ' || v_what
      when 'under_review' then 'Dispute on ' || v_what || ' is under review'
      else 'Dispute on ' || v_what || coalesce(': reply by '
        || to_char(p_respond_by at time zone 'Asia/Kolkata', 'FMDD Mon'), '') end,
    concat_ws(' · ', private.inr(greatest(coalesce(p_amount_paise, 0), 0)), nullif(left(p_reason, 120), ''),
      case when v_status in ('open', 'action_required')
        then 'Answer with the invoice, IMEI and delivery proof in the Razorpay dashboard.' end),
    case when v_order is not null then '/admin/orders/' || v_order end, v_order);
end $$;

revoke execute on function public.record_dispute(text, text, int, text, text, text, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.record_dispute(text, text, int, text, text, text, text, timestamptz) to service_role;
