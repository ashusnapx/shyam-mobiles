-- Notifications (docs/SPEC.md, "Notifications"): every order, payment, repair, coupon and feedback step writes a
-- short in-app notification for the customer it concerns and, where staff must act, one per admin. Only the
-- triggers below write them (nobody inserts from a client); people read, mark read and delete their own.
-- Push to phones is ready but off: device_tokens + the send-push Edge Function, called through pg_net once
-- scripts/launch.py stores its URL and secret in Vault. A push problem never fails the order or repair behind it.

create extension if not exists pg_net with schema extensions;

-- Tables ----------------------------------------------------------------------

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  kind text not null check (kind ~ '^[a-z_]{2,40}$'), -- picks the app's icon and colour (lib/features/notifications)
  title text not null check (char_length(title) between 1 and 80),
  body text not null default '' check (char_length(body) <= 300),
  -- an app route, never a URL (like banners.link)
  link text check (char_length(link) <= 200 and link ~
    '^/(orders/|repairs/|offers|product/|admin/orders/|admin/repairs/|admin/feedback/|admin/products/|admin/catalogue)[A-Za-z0-9/?=&%._~+-]*$'),
  order_id uuid references public.orders on delete cascade,
  repair_id uuid references public.repair_bookings on delete cascade,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);
create index notifications_unread_idx on public.notifications (user_id) where read_at is null;
create index notifications_order_idx on public.notifications (order_id) where order_id is not null; -- FK cascades
create index notifications_repair_idx on public.notifications (repair_id) where repair_id is not null;

-- One row per phone: whoever signed in last on it gets its pushes (register_device moves the token).
create table public.device_tokens (
  token text primary key check (char_length(token) between 20 and 1000 and token ~ '^[A-Za-z0-9_:-]+$'), -- an FCM token
  user_id uuid not null references auth.users on delete cascade,
  platform text not null default 'android' check (platform in ('android', 'ios')),
  updated_at timestamptz not null default now()
);
create index device_tokens_user_idx on public.device_tokens (user_id);

alter table public.notifications enable row level security;
alter table public.device_tokens enable row level security;
create policy "own read" on public.notifications for select to authenticated using (user_id = (select auth.uid()));
create policy "own update" on public.notifications for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "own delete" on public.notifications for delete to authenticated using (user_id = (select auth.uid()));
create policy "own read" on public.device_tokens for select to authenticated using (user_id = (select auth.uid()));
create policy "own delete" on public.device_tokens for delete to authenticated using (user_id = (select auth.uid()));

revoke all on public.notifications, public.device_tokens from public, anon, authenticated, service_role;
grant select, delete on public.notifications, public.device_tokens to authenticated;
grant update (read_at) on public.notifications to authenticated; -- marking read is the only change people make
grant all on public.notifications, public.device_tokens to service_role;

-- Copy helpers ------------------------------------------------------------------

-- ₹ in Indian grouping, as the app's formatInr: 12999900 → ₹1,29,999, 4950 → ₹49.50.
create function private.inr(p bigint) returns text
language sql immutable set search_path = '' as $$
  select '₹' || regexp_replace((p / 100)::text, '(\d)(?=(\d\d)+\d$)', '\1,', 'g')
    || case when p % 100 <> 0 then '.' || lpad((p % 100)::text, 2, '0') else '' end
$$;

-- one line, at most n characters (an ellipsis marks a cut)
create function private.clip(p text, n int) returns text
language sql immutable set search_path = '' as $$
  select case when char_length(v) <= n then v else left(v, n - 1) || '…' end
  from (select btrim(regexp_replace(coalesce(p, ''), '\s+', ' ', 'g')) as v) s
$$;

-- Created at the statement's start, so the order triggers can tell what this same RPC call already said.
create function private.notify(p_user uuid, p_kind text, p_title text, p_body text, p_link text,
  p_order uuid default null, p_repair uuid default null) returns void
language sql security definer set search_path = '' as $$
  insert into public.notifications (user_id, kind, title, body, link, order_id, repair_id, created_at)
  select p_user, p_kind, private.clip(p_title, 80), private.clip(p_body, 300), p_link, p_order, p_repair,
    statement_timestamp()
  where p_user is not null;
$$;

-- Every admin but whoever did it: staff aren't told about their own actions.
create function private.notify_staff(p_kind text, p_title text, p_body text, p_link text,
  p_order uuid default null, p_repair uuid default null) returns void
language sql security definer set search_path = '' as $$
  insert into public.notifications (user_id, kind, title, body, link, order_id, repair_id, created_at)
  select a.user_id, p_kind, private.clip(p_title, 80), private.clip(p_body, 300), p_link, p_order, p_repair,
    statement_timestamp()
  from public.admins a where a.user_id is distinct from (select auth.uid());
$$;

-- "₹1,29,999 · Cash on delivery · Samsung Galaxy S25 + 1 more · Waidhan", for staff
create function private.order_summary(o public.orders) returns text
language sql stable set search_path = '' as $$
  select concat_ws(' · ', private.inr(o.total_paise),
    case o.payment_method when 'cod' then 'Cash on delivery' else 'Paid online' end,
    (select (array_agg(i.product_name order by i.unit_price_paise desc, i.id))[1]
        || case when count(*) > 1 then ' + ' || (count(*) - 1) || ' more' else '' end
     from public.order_items i where i.order_id = o.id),
    o.address ->> 'city')
$$;

create function private.tracking_line(o public.orders) returns text
language sql immutable set search_path = '' as $$
  select case
    when nullif(btrim(o.courier), '') is not null and nullif(btrim(o.tracking_number), '') is not null
      then o.courier || ', tracking ' || o.tracking_number || '.'
    when nullif(btrim(o.tracking_number), '') is not null then 'Tracking ' || o.tracking_number || '.'
    when nullif(btrim(o.courier), '') is not null then 'With ' || o.courier || '.'
  end
$$;

-- "Screen"; lower-cased mid-sentence: "₹200 quote for your Galaxy A56 screen"
create function private.issue_words(p public.repair_issue) returns text
language sql immutable set search_path = '' as $$
  select case p when 'screen' then 'Screen' when 'battery' then 'Battery' when 'charging' then 'Charging port'
    when 'camera' then 'Camera' when 'audio' then 'Speaker or mic' when 'water_damage' then 'Water damage'
    when 'software' then 'Software' else 'Repair' end
$$;

-- "Tue 4 Nov, morning (10 am – 1 pm)", the slots as the app shows them
create function private.repair_when(b public.repair_bookings) returns text
language sql stable set search_path = '' as $$
  select to_char(b.preferred_date, 'Dy FMDD Mon') || ', ' || b.slot || ' (' || case b.slot
    when 'morning' then '10 am – 1 pm' when 'afternoon' then '1 pm – 5 pm' else '5 pm – 9 pm' end || ')'
$$;

-- Orders --------------------------------------------------------------------------

-- Payments, refunds and courier details, from the order row itself (mark_payment_failed writes no timeline event,
-- and a tracking fix may come with or without one).
create function private.notify_order_change() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_link text := '/orders/' || new.id;
  v_staff text := '/admin/orders/' || new.id;
begin
  if new.payment_status is distinct from old.payment_status then
    if new.payment_status = 'failed' then
      perform private.notify(new.user_id, 'payment_failed', 'Payment failed for ' || new.number,
        'Your items are still held for you. Try paying again before '
          || coalesce(to_char(new.reserved_until at time zone 'Asia/Kolkata', 'FMHH12:MI am'), 'the hold ends') || '.',
        v_link, new.id);
    elsif new.payment_status = 'paid' and new.payment_method = 'razorpay' and new.status = 'cancelled' then
      perform private.notify(new.user_id, 'order_late_payment', 'We got your payment for ' || new.number,
        'The order was already cancelled, so we’re refunding ' || private.inr(new.total_paise)
          || ' to your original payment method.', v_link, new.id);
      perform private.notify_staff('staff_refund_needed', 'Refund ' || private.inr(new.total_paise) || ' for ' || new.number,
        'The payment arrived after the order was cancelled.', v_staff, new.id);
    elsif new.payment_status = 'paid' and new.payment_method = 'razorpay' then
      perform private.notify(new.user_id, 'payment_received', 'Payment received for ' || new.number,
        private.inr(new.total_paise) || ' paid. Your order is confirmed.', v_link, new.id);
      perform private.notify_staff('staff_order_paid', 'Paid order ' || new.number, private.order_summary(new), v_staff,
        new.id);
    elsif new.payment_status = 'refunded' then
      perform private.notify(new.user_id, 'order_refunded',
        'Refund of ' || private.inr(new.total_paise) || ' for ' || new.number,
        'It’s on its way to your original payment method. Banks usually take 5–7 working days to show it.',
        v_link, new.id);
    end if;
  elsif new.status = old.status and new.status in ('packed', 'shipped', 'delivered')
        and (new.courier is distinct from old.courier or new.tracking_number is distinct from old.tracking_number) then
    perform private.notify(new.user_id, 'order_tracking', 'Tracking updated for ' || new.number,
      coalesce(private.tracking_line(new), 'The courier details were removed.'), v_link, new.id);
  end if;
  return null;
end $$;

create trigger notify_order_change after update of status, payment_status, courier, tracking_number on public.orders
for each row execute function private.notify_order_change();

-- Every timeline event: placed, packed, shipped, delivered, cancelled (by whom, with the note), staff notes.
create function private.notify_order_event() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  o public.orders;
  v_prev public.order_status;
  v_actor uuid := auth.uid();
  v_note text := nullif(btrim(new.note), '');
  v_link text := '/orders/' || new.order_id;
  v_staff text := '/admin/orders/' || new.order_id;
begin
  select * into o from public.orders where id = new.order_id;
  -- this RPC call already told the customer (payment, refund, tracking): its note joins that notification
  update public.notifications n
  set body = case when v_note is null then n.body
                  -- admin_update_order's own "Courier and tracking updated: …" note repeats the number: no need
                  when n.kind = 'order_tracking' and strpos(v_note, coalesce(o.tracking_number, o.courier, '')) = 0
                    then private.clip(n.body || ' ' || v_note, 300)
                  when n.kind = 'order_refunded' then private.clip(v_note, 300) -- "Refunded in cash at the store"
                  else n.body end
  where n.order_id = o.id and n.user_id = o.user_id and n.created_at = statement_timestamp();
  if found then return null; end if;

  select e.status into v_prev from public.order_events e
  where e.order_id = new.order_id and e.id < new.id order by e.id desc limit 1;

  if v_prev is null then -- placed
    if new.status = 'pending_payment' then
      perform private.notify(o.user_id, 'order_awaiting_payment', 'Finish paying for ' || o.number,
        private.inr(o.total_paise) || ' to pay online. We hold your items for 15 minutes.', v_link, o.id);
    else
      perform private.notify(o.user_id, 'order_confirmed', o.number || ' is confirmed',
        private.inr(o.total_paise) || ', cash on delivery. We’ll tell you when it’s packed.', v_link, o.id);
      perform private.notify_staff('staff_new_order', 'New order ' || o.number, private.order_summary(o), v_staff, o.id);
    end if;
  elsif new.status = v_prev then -- a note on the timeline
    if v_note is not null and public.is_admin() then
      perform private.notify(o.user_id, 'order_update', 'Update on ' || o.number, v_note, v_link, o.id);
    end if;
  elsif new.status = 'packed' then
    perform private.notify(o.user_id, 'order_packed', o.number || ' is packed',
      coalesce(v_note, 'It ships soon. We’ll tell you when it’s on the way.'), v_link, o.id);
  elsif new.status = 'shipped' then
    perform private.notify(o.user_id, 'order_shipped', o.number || ' is on its way',
      concat_ws(' ', coalesce(private.tracking_line(o), 'Out for delivery.'), v_note), v_link, o.id);
  elsif new.status = 'delivered' then
    perform private.notify(o.user_id, 'order_delivered', o.number || ' is delivered',
      'How was it? Tap to rate your order.', v_link, o.id);
  elsif new.status = 'cancelled' and v_actor is not null and v_actor = o.user_id then
    perform private.notify(o.user_id, 'order_cancelled', 'You cancelled ' || o.number,
      case when o.payment_status = 'paid'
        then 'A full refund of ' || private.inr(o.total_paise) || ' to your original payment method is on its way; banks usually take 5–7 working days.'
        else 'Nothing was charged.' end, v_link, o.id);
    if o.payment_status = 'paid' then
      perform private.notify_staff('staff_refund_needed', 'Refund ' || private.inr(o.total_paise) || ' for ' || o.number,
        'The customer cancelled a paid order. Its stock is back.', v_staff, o.id);
    elsif v_prev <> 'pending_payment' then -- staff never heard of an unpaid online order
      perform private.notify_staff('staff_order_cancelled', o.number || ' cancelled by the customer',
        'Stock is back: ' || private.order_summary(o), v_staff, o.id);
    end if;
  elsif new.status = 'cancelled' and v_actor is null then -- the 15-minute payment hold ran out
    perform private.notify(o.user_id, 'order_expired', o.number || ' was cancelled',
      'The payment didn’t come through in 15 minutes. Order again any time.', v_link, o.id);
  elsif new.status = 'cancelled' then
    perform private.notify(o.user_id, 'order_cancelled', o.number || ' was cancelled by the shop',
      coalesce(v_note, 'Cancelled by the store.'), v_link, o.id);
    if o.payment_status = 'paid' then
      perform private.notify_staff('staff_refund_needed', 'Refund ' || private.inr(o.total_paise) || ' for ' || o.number,
        'Staff cancelled a paid order. Refund it, then mark it refunded.', v_staff, o.id);
    end if;
  end if;
  return null;
end $$;

create trigger notify_order_event after insert on public.order_events
for each row execute function private.notify_order_event();

-- Repairs ---------------------------------------------------------------------------

-- Every repair timeline event: booked, each step, quotes and the answers, cancels, staff notes.
create function private.notify_repair_event() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  b public.repair_bookings;
  v_prev public.repair_status;
  v_by_customer boolean;
  v_note text := nullif(btrim(new.note), '');
  v_link text := '/repairs/' || new.booking_id;
  v_staff text := '/admin/repairs/' || new.booking_id;
  v_what text;
  v_amount text := private.inr(new.quote_paise);
begin
  select * into b from public.repair_bookings where id = new.booking_id;
  v_by_customer := auth.uid() is not null and auth.uid() = b.user_id;
  v_what := b.device_model || ' ' || lower(private.issue_words(b.issue)); -- "Galaxy A56 screen"
  select e.status into v_prev from public.repair_events e
  where e.booking_id = new.booking_id and e.id < new.id order by e.id desc limit 1;

  if new.quote_status = 'pending' then
    perform private.notify(b.user_id, 'repair_quote', case when b.status = 'in_progress'
        then 'New ' || v_amount || ' quote for your ' || v_what || ': approve to continue'
        else v_amount || ' quote for your ' || v_what || ': approve to start' end,
      coalesce(v_note, 'Work starts only after you approve this price.'), v_link, null, b.id);
  elsif new.quote_status = 'approved' and v_by_customer then
    perform private.notify_staff('staff_quote_approved', 'Quote approved for ' || b.number,
      v_amount || ' for the ' || b.device_brand || ' ' || v_what || '. You can start the repair.', v_staff, null, b.id);
  elsif new.quote_status = 'approved' then -- agreed at the counter or on the phone
    perform private.notify(b.user_id, 'repair_quote_agreed', v_amount || ' agreed for your ' || v_what,
      coalesce(v_note, 'Agreed with the store.'), v_link, null, b.id);
  elsif new.quote_status = 'declined' then
    perform private.notify_staff('staff_quote_declined', 'Quote declined for ' || b.number,
      v_amount || ' for the ' || b.device_brand || ' ' || v_what || '. '
        || coalesce('Reason: “' || v_note || '”.', 'No reason given.') || ' Quote again or cancel it.', v_staff, null, b.id);
  elsif v_prev is null then -- booked (a walk-in may start confirmed)
    perform private.notify(b.user_id, 'repair_booked', 'Repair booked for your ' || b.device_model,
      concat_ws(' ', private.issue_words(b.issue) || ' · ' || private.repair_when(b) || '.',
        case when b.status = 'requested' then 'We’ll confirm the time soon.' end), v_link, null, b.id);
    perform private.notify_staff('staff_new_repair', 'New repair ' || b.number || ': ' || b.device_brand || ' ' || b.device_model,
      concat_ws(' · ', private.issue_words(b.issue), private.repair_when(b), nullif(b.description, '')),
      v_staff, null, b.id);
  elsif new.status = v_prev then -- a note on the timeline
    if v_note is not null and public.is_admin() then
      perform private.notify(b.user_id, 'repair_update', 'Update on your ' || b.device_model || ' repair', v_note,
        v_link, null, b.id);
    end if;
  elsif new.status = 'confirmed' then
    perform private.notify(b.user_id, 'repair_confirmed', 'Repair confirmed for ' || private.repair_when(b),
      concat_ws(' ', 'Bring your ' || b.device_model || ' to the store then.', v_note), v_link, null, b.id);
  elsif new.status = 'in_progress' then
    perform private.notify(b.user_id, 'repair_started', 'Work has started on your ' || b.device_model,
      coalesce(v_note, 'We’ll tell you when it’s ready.'), v_link, null, b.id);
  elsif new.status = 'ready' then
    perform private.notify(b.user_id, 'repair_ready', 'Your ' || b.device_model || ' is ready for pickup',
      coalesce(nullif(concat_ws(' ', 'Pay ' || private.inr(b.quote_paise) || ' when you collect it.', v_note), ''),
               'Collect it from the store.'), v_link, null, b.id);
  elsif new.status = 'completed' then
    perform private.notify(b.user_id, 'repair_completed', 'Your ' || b.device_model || ' repair is complete',
      'How did we do? Tap to rate the repair.', v_link, null, b.id);
  elsif new.status = 'cancelled' and v_by_customer then -- their own cancel isn't news to them
    perform private.notify_staff('staff_repair_cancelled', b.number || ' cancelled by the customer',
      concat_ws(' · ', b.device_brand || ' ' || b.device_model, private.issue_words(b.issue), private.repair_when(b)),
      v_staff, null, b.id);
  elsif new.status = 'cancelled' then
    perform private.notify(b.user_id, 'repair_cancelled', 'Your ' || b.device_model || ' repair was cancelled',
      coalesce(v_note, 'Cancelled by the store.'), v_link, null, b.id);
  end if;
  return null;
end $$;

create trigger notify_repair_event after insert on public.repair_events
for each row execute function private.notify_repair_event();

-- Coupons, feedback, stock --------------------------------------------------------------

-- A personal coupon (referral welcome gift, referral reward, or one staff made for someone).
create function private.notify_personal_coupon() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_value text := case new.kind when 'flat' then private.inr(new.value) when 'percent' then new.value || '%'
    else 'free delivery' end;
begin
  if new.user_id is null or tg_op = 'UPDATE' and new.user_id is not distinct from old.user_id then return null; end if;
  perform private.notify(new.user_id,
    case when new.code like 'REWARD%' then 'referral_reward' when new.code like 'FRIEND%' then 'referral_welcome' else 'coupon' end,
    case when new.code like 'REWARD%' then 'You earned a ' || v_value || ' coupon for referring a friend'
         when new.code like 'FRIEND%' then 'Your welcome gift: ' || v_value || ' off your first order'
         else 'A coupon just for you: ' || new.title end,
    'Use code ' || new.code
      || case when new.min_subtotal_paise > 0 then ' on an order of ' || private.inr(new.min_subtotal_paise) || ' or more' else '' end
      || coalesce(' by ' || to_char(new.ends_at at time zone 'Asia/Kolkata', 'FMDD Mon'), '') || '.',
    '/offers/' || new.id);
  return null;
end $$;

create trigger notify_personal_coupon after insert or update of user_id on public.promotions
for each row execute function private.notify_personal_coupon();

-- New feedback, and a re-rating (send_feedback updates the row); staff changing status or their note is not news.
create function private.notify_feedback() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_about text;
  v_stars text := new.rating || case when new.rating = 1 then ' star' else ' stars' end;
begin
  if tg_op = 'UPDATE' and new.rating is not distinct from old.rating and new.message = old.message then return null; end if;
  v_about := case new.kind
    when 'order' then 'order ' || (select number from public.orders where id = new.order_id)
    when 'repair' then 'repair ' || (select number from public.repair_bookings where id = new.repair_id)
    when 'product' then (select name from public.products where id = new.product_id) end;
  perform private.notify_staff(
    case when new.rating <= 2 then 'staff_feedback_low' else 'staff_feedback' end,
    case when new.rating <= 2 then 'Low rating: ' || v_stars || coalesce(' for ' || v_about, '')
         when new.rating is not null then 'New rating: ' || v_stars || coalesce(' for ' || v_about, '')
         when new.kind = 'bug' then 'New problem report'
         else 'New feedback' || coalesce(' on ' || v_about, '') end,
    coalesce(nullif(btrim(new.message), ''), 'No comment.'),
    '/admin/feedback/' || new.id);
  return null;
end $$;

create trigger notify_feedback after insert or update of rating, message on public.feedback
for each row execute function private.notify_feedback();

-- A sale takes a live variant to 3 or fewer, or to none: once per crossing (the next sale below 3 says nothing).
-- Staff edits aren't sales: whoever lowers stock by hand knows.
create function private.notify_low_stock() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_product public.products;
begin
  if public.is_admin() or not new.is_active then return null; end if;
  select * into v_product from public.products where id = new.product_id;
  if not v_product.is_active then return null; end if;
  if new.stock = 0 then
    perform private.notify_staff('staff_out_of_stock', 'Out of stock: ' || v_product.name,
      new.name || ' (' || new.sku || ') just sold out. Restock it or hide it.', '/admin/products/' || v_product.id);
  elsif old.stock > 3 then
    perform private.notify_staff('staff_low_stock', 'Low stock: ' || v_product.name,
      new.name || ' (' || new.sku || '): only ' || new.stock || ' left.', '/admin/products/' || v_product.id);
  end if;
  return null;
end $$;

create trigger notify_low_stock after update of stock on public.variants
for each row when (new.stock < old.stock and new.stock <= 3 and (old.stock > 3 or new.stock = 0))
execute function private.notify_low_stock();

-- Push ------------------------------------------------------------------------------

-- Hands each new notification to the send-push Edge Function for the user's phones. Off until scripts/launch.py
-- puts push_url and push_secret in Vault; pg_net sends after commit, so a slow FCM never holds the transaction.
-- Any error here is logged and swallowed: a push must never fail the order, payment or repair behind it.
create function private.push_notification() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_tokens text[];
  v_url text;
  v_secret text;
begin
  select array_agg(token) into v_tokens from public.device_tokens where user_id = new.user_id;
  if v_tokens is null then return null; end if;
  select max(decrypted_secret) filter (where name = 'push_url'), max(decrypted_secret) filter (where name = 'push_secret')
  into v_url, v_secret from vault.decrypted_secrets where name in ('push_url', 'push_secret');
  if v_url is null or v_secret is null then return null; end if;
  perform net.http_post(
    url := v_url,
    body := jsonb_build_object('id', new.id, 'kind', new.kind, 'title', new.title, 'body', new.body,
      'link', new.link, 'tokens', to_jsonb(v_tokens)),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', v_secret),
    timeout_milliseconds := 5000);
  return null;
exception when others then
  raise warning 'push for notification % skipped: %', new.id, sqlerrm;
  return null;
end $$;

create trigger push_notification after insert on public.notifications
for each row execute function private.push_notification();

-- RPCs --------------------------------------------------------------------------------

create function public.unread_notifications() returns int
language sql stable set search_path = '' as $$
  select count(*)::int from public.notifications where user_id = (select auth.uid()) and read_at is null
$$;

-- p_ids null: all of mine
create function public.mark_notifications_read(p_ids uuid[] default null) returns void
language sql set search_path = '' as $$
  update public.notifications set read_at = now()
  where user_id = (select auth.uid()) and read_at is null and (p_ids is null or id = any(p_ids))
$$;

-- The phone's FCM token, after sign-in: it moves to this user if someone else had it. Newest 10 phones each.
create function public.register_device(p_token text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'FORBIDDEN'; end if;
  if p_token is null or char_length(p_token) not between 20 and 1000 or p_token !~ '^[A-Za-z0-9_:-]+$' then
    raise exception 'BAD_REQUEST';
  end if;
  insert into public.device_tokens (token, user_id) values (p_token, v_uid)
  on conflict (token) do update set user_id = excluded.user_id, updated_at = now();
  delete from public.device_tokens where token in (
    select token from public.device_tokens where user_id = v_uid order by updated_at desc offset 10);
end $$;

-- Housekeeping: 90 days of notifications; FCM forgets a token after 270 days without the app.
select cron.schedule('notifications-cleanup', '30 3 * * *', $$
  with gone as (delete from public.notifications where created_at < now() - interval '90 days')
  delete from public.device_tokens where updated_at < now() - interval '270 days'
$$);

-- Grants: Supabase grants execute on new functions to anon/authenticated by default; undo that.

revoke execute on function
  private.inr(bigint), private.clip(text, int),
  private.notify(uuid, text, text, text, text, uuid, uuid), private.notify_staff(text, text, text, text, uuid, uuid),
  private.order_summary(public.orders), private.tracking_line(public.orders), private.issue_words(public.repair_issue),
  private.repair_when(public.repair_bookings),
  private.notify_order_change(), private.notify_order_event(), private.notify_repair_event(),
  private.notify_personal_coupon(), private.notify_feedback(), private.notify_low_stock(), private.push_notification()
from public, anon, authenticated;

revoke execute on function
  public.unread_notifications(), public.mark_notifications_read(uuid[]), public.register_device(text)
from public, anon, authenticated, service_role;
grant execute on function
  public.unread_notifications(), public.mark_notifications_read(uuid[]), public.register_device(text)
to authenticated;
