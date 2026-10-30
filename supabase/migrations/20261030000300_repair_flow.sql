-- Repairs end to end (docs/SPEC.md, "State machines"): the customer approves or declines the quote in the app,
-- every step lands in a timeline (repair_events, like order_events), and staff move a booking only through
-- admin_update_repair / admin_set_repair_quote, which enforce the steps. Staff lose the direct UPDATE on
-- repair_bookings, so no client can skip a step or start work on a price nobody agreed to.
-- Also: admin_dashboard counts quotes waiting for the customer, and low stock counts products (the list it opens).

create type public.repair_quote_status as enum ('none', 'pending', 'approved', 'declined');

alter table public.repair_bookings
  add column quote_status public.repair_quote_status not null default 'none',
  add column quote_decided_at timestamptz; -- when the customer (or staff, for them) said yes or no

-- Quotes from before this: work already started means the customer agreed (on WhatsApp); otherwise they still can.
update public.repair_bookings
set quote_status = case when status in ('in_progress', 'ready', 'completed') then 'approved' else 'pending' end::public.repair_quote_status
where quote_paise is not null;

alter table public.repair_bookings
  add constraint repair_bookings_quote_check check ((quote_paise is null) = (quote_status = 'none'));
comment on column public.repair_bookings.admin_note is 'Legacy: notes now go to repair_events (copied there by 20261030000300).';

create table public.repair_events (
  id bigint generated always as identity primary key,
  booking_id uuid not null references public.repair_bookings on delete cascade,
  status public.repair_status not null, -- the booking's status after this event
  quote_status public.repair_quote_status check (quote_status <> 'none'), -- set on quote events only: sent, approved, declined
  quote_paise int check (quote_paise >= 0), -- the amount that quote event was about
  note text check (char_length(note) <= 500 and public.is_clean_text(note, true)), -- staff's note, or the customer's decline reason
  created_at timestamptz not null default now(),
  check ((quote_status is null) = (quote_paise is null))
);
create index repair_events_booking_idx on public.repair_events (booking_id, created_at);

-- A timeline for every booking that already exists: booked, then where it is now with the old note.
insert into public.repair_events (booking_id, status, created_at)
select id, 'requested', created_at from public.repair_bookings;
insert into public.repair_events (booking_id, status, note, created_at)
select id, status, admin_note, updated_at from public.repair_bookings where status <> 'requested' or admin_note is not null;

alter table public.repair_events enable row level security;
-- the subquery is itself filtered by the repair_bookings policy (own or staff)
create policy "own or admin read" on public.repair_events for select to authenticated
  using (exists (select 1 from public.repair_bookings b where b.id = booking_id));

revoke all on public.repair_events from anon, authenticated, service_role;
revoke all on sequence public.repair_events_id_seq from anon, authenticated;
grant select on public.repair_events to authenticated; -- written by the RPCs and triggers below, never by clients
grant select, insert, update, delete on public.repair_events to service_role;

-- No more direct staff writes: every change goes through the RPCs below.
drop policy "admin update" on public.repair_bookings;
revoke update on public.repair_bookings from authenticated;

-- New bookings ------------------------------------------------------------------

-- A quote given at booking time (staff, walk-ins) waits for the customer like any other. Clients can't set
-- quote_status (no column grant); fixtures and service code may.
create function private.repair_booking_quote() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.quote_status := case when new.quote_paise is null then 'none'
                           when new.quote_status = 'none' then 'pending' else new.quote_status end;
  return new;
end $$;

create trigger repair_booking_quote before insert on public.repair_bookings
for each row execute function private.repair_booking_quote();

-- The first timeline entries: booked (or confirmed, for a walk-in), and the quote if there is one.
create function private.repair_booking_first_events() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.repair_events (booking_id, status, note) values (new.id, new.status, new.admin_note);
  if new.quote_paise is not null then
    insert into public.repair_events (booking_id, status, quote_status, quote_paise)
    values (new.id, new.status, new.quote_status, new.quote_paise);
  end if;
  return null;
end $$;

create trigger repair_booking_first_events after insert on public.repair_bookings
for each row execute function private.repair_booking_first_events();

-- Customer ------------------------------------------------------------------

-- p_quote_paise is the price the customer saw: a quote changed meanwhile has to be read before it can be approved.
create function public.approve_repair_quote(p_booking_id uuid, p_quote_paise int) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v public.repair_bookings;
begin
  select * into v from public.repair_bookings where id = p_booking_id and user_id = auth.uid() for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if v.quote_status <> 'pending' or v.status not in ('requested', 'confirmed', 'in_progress') then
    raise exception 'INVALID_TRANSITION';
  end if;
  if p_quote_paise is distinct from v.quote_paise then raise exception 'QUOTE_CHANGED'; end if;

  update public.repair_bookings set quote_status = 'approved', quote_decided_at = now() where id = p_booking_id;
  insert into public.repair_events (booking_id, status, quote_status, quote_paise)
  values (p_booking_id, v.status, 'approved', v.quote_paise);
end $$;

-- Saying no is safe whatever the amount, so no price check. The store can quote again, or either side cancels.
create function public.decline_repair_quote(p_booking_id uuid, p_reason text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v public.repair_bookings;
begin
  select * into v from public.repair_bookings where id = p_booking_id and user_id = auth.uid() for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if v.quote_status <> 'pending' or v.status not in ('requested', 'confirmed', 'in_progress') then
    raise exception 'INVALID_TRANSITION';
  end if;

  update public.repair_bookings set quote_status = 'declined', quote_decided_at = now() where id = p_booking_id;
  insert into public.repair_events (booking_id, status, quote_status, quote_paise, note)
  values (p_booking_id, v.status, 'declined', v.quote_paise, nullif(btrim(p_reason), ''));
end $$;

-- Same rule as before (requested or confirmed: the phone isn't opened yet), now on the timeline too.
create or replace function public.cancel_repair(p_booking_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_status public.repair_status;
begin
  select status into v_status from public.repair_bookings
  where id = p_booking_id and user_id = auth.uid() for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if v_status not in ('requested', 'confirmed') then raise exception 'INVALID_TRANSITION'; end if;

  update public.repair_bookings set status = 'cancelled' where id = p_booking_id;
  insert into public.repair_events (booking_id, status, note) values (p_booking_id, 'cancelled', 'Cancelled by you.');
end $$;

-- Staff ---------------------------------------------------------------------

-- One step forward (requested → confirmed → in_progress → ready → completed) or cancel any open booking.
-- p_status = the current status only adds p_note to the timeline. Starting the repair and marking it ready need
-- the customer's yes to the current quote (QUOTE_NOT_APPROVED), so a price changed mid-repair is agreed first.
create function public.admin_update_repair(p_booking_id uuid, p_status public.repair_status, p_note text default null)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v public.repair_bookings;
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  select * into v from public.repair_bookings where id = p_booking_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  p_note := nullif(btrim(p_note), '');

  if p_status = v.status then
    if p_note is null then return; end if;
  elsif (v.status, p_status) not in (
    ('requested', 'confirmed'), ('confirmed', 'in_progress'), ('in_progress', 'ready'), ('ready', 'completed'),
    ('requested', 'cancelled'), ('confirmed', 'cancelled'), ('in_progress', 'cancelled'), ('ready', 'cancelled')
  ) then
    raise exception 'INVALID_TRANSITION' using detail = v.status || ' -> ' || p_status;
  elsif p_status in ('in_progress', 'ready') and v.quote_status <> 'approved' then
    raise exception 'QUOTE_NOT_APPROVED' using detail = v.quote_status::text;
  end if;

  if p_status <> v.status then
    update public.repair_bookings set status = p_status where id = p_booking_id;
  end if;
  insert into public.repair_events (booking_id, status, note)
  values (p_booking_id, p_status, coalesce(p_note, case when p_status = 'cancelled' then 'Cancelled by the store.' end));
end $$;

-- Sends or changes the quote while the booking is requested, confirmed or in repair; it waits for the customer
-- again. p_approved: the customer said yes at the counter or on the phone (shown to them as agreed with the store).
create function public.admin_set_repair_quote(
  p_booking_id uuid, p_quote_paise int, p_note text default null, p_approved boolean default false
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v public.repair_bookings;
  v_quote public.repair_quote_status := case when p_approved then 'approved' else 'pending' end;
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  -- ₹10,00,000, the app's cap on every amount
  if p_quote_paise is null or p_quote_paise not between 0 and 100000000 or p_approved is null then
    raise exception 'BAD_REQUEST';
  end if;
  select * into v from public.repair_bookings where id = p_booking_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if v.status not in ('requested', 'confirmed', 'in_progress') then
    raise exception 'INVALID_TRANSITION' using detail = 'no quotes once ' || v.status;
  end if;

  update public.repair_bookings
  set quote_paise = p_quote_paise, quote_status = v_quote, quote_decided_at = case when p_approved then now() end
  where id = p_booking_id;
  insert into public.repair_events (booking_id, status, quote_status, quote_paise, note)
  values (p_booking_id, v.status, v_quote, p_quote_paise,
          coalesce(nullif(btrim(p_note), ''), case when p_approved then 'Agreed with the store.' end));
end $$;

-- admin_dashboard: + repairs_awaiting_approval; low_stock counts products, as the Products list it opens shows them.
create or replace function public.admin_dashboard() returns json
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
      'low_stock', (select count(distinct p.id) from public.variants v join public.products p on p.id = v.product_id
                    where v.is_active and p.is_active and v.stock <= 3),
      'open_repairs', (select count(*) from public.repair_bookings r where r.status not in ('completed', 'cancelled')),
      'repairs_awaiting_approval', (select count(*) from public.repair_bookings r
                                    where r.status not in ('completed', 'cancelled') and r.quote_status = 'pending')
    )
    from public.orders o
  );
end $$;

-- Grants: Supabase grants execute on new functions to anon/authenticated by default; undo that.

revoke execute on function private.repair_booking_quote(), private.repair_booking_first_events()
  from public, anon, authenticated;

revoke execute on function
  public.approve_repair_quote(uuid, int),
  public.decline_repair_quote(uuid, text),
  public.admin_update_repair(uuid, public.repair_status, text),
  public.admin_set_repair_quote(uuid, int, text, boolean)
from public, anon, authenticated, service_role;

-- admin_* check is_admin() inside
grant execute on function
  public.approve_repair_quote(uuid, int),
  public.decline_repair_quote(uuid, text),
  public.admin_update_repair(uuid, public.repair_status, text),
  public.admin_set_repair_quote(uuid, int, text, boolean)
to authenticated;
