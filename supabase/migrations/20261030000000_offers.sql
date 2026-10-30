-- Offers: coupons, automatic sales, product groups, referrals and banners (docs/SPEC.md, "Offers").
-- One promotion per order, priced by private.price_lines for both quote_order (preview) and place_order (charge).

create type public.promotion_kind as enum ('percent', 'flat', 'free_delivery');
create type public.promotion_scope as enum ('order', 'items');
create type public.promotion_target_type as enum ('product', 'category', 'brand', 'collection');
create type public.referral_status as enum ('pending', 'rewarded', 'void');

-- Tables --------------------------------------------------------------------

create table public.collections (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9-]{1,60}$'),
  name text not null check (char_length(name) between 2 and 60 and public.is_clean_text(name)),
  created_at timestamptz not null default now()
);

create table public.collection_products (
  collection_id uuid not null references public.collections on delete cascade,
  product_id uuid not null references public.products on delete cascade,
  primary key (collection_id, product_id)
);
create index collection_products_product_idx on public.collection_products (product_id); -- FK: product deletes cascade here

create table public.promotions (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 2 and 60 and public.is_clean_text(title)),
  description text not null default '' check (char_length(description) <= 300 and public.is_clean_text(description, true)),
  code text unique check (code ~ '^[A-Z0-9]{4,20}$'), -- null = automatic sale
  kind public.promotion_kind not null,
  value int not null default 0,
  max_discount_paise int,
  min_subtotal_paise int not null default 0 check (min_subtotal_paise >= 0), -- on eligible lines
  applies_to public.promotion_scope not null default 'order',
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  usage_limit int check (usage_limit >= 1),
  per_user_limit int default 1 check (per_user_limit >= 1),
  first_order_only boolean not null default false,
  online_only boolean not null default false,
  is_public boolean not null default true,
  user_id uuid references auth.users on delete cascade, -- a personal coupon (referrals)
  is_active boolean not null default true,
  show_banner boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint promotions_value_check check (case kind
    when 'percent' then value between 1 and 90 when 'flat' then value >= 100 else value = 0 end),
  constraint promotions_cap_check check (max_discount_paise is null or (kind = 'percent' and max_discount_paise >= 1)),
  constraint promotions_window_check check (ends_at > starts_at),
  constraint promotions_personal_check check (user_id is null or code is not null),
  -- a banner would print the code: never for hidden or personal ones
  constraint promotions_banner_check check (not show_banner or (is_public and user_id is null))
);
create index promotions_user_idx on public.promotions (user_id) where user_id is not null;

create table public.promotion_targets (
  promotion_id uuid not null references public.promotions on delete cascade,
  target_type public.promotion_target_type not null,
  target_id uuid not null, -- a product, category, brand or collection id (checked by admin_save_promotion)
  primary key (promotion_id, target_type, target_id)
);

create table public.promotion_redemptions (
  order_id uuid primary key references public.orders on delete cascade,
  promotion_id uuid not null references public.promotions on delete cascade,
  user_id uuid references auth.users on delete set null,
  discount_paise int not null check (discount_paise >= 0),
  created_at timestamptz not null default now()
);
create index promotion_redemptions_promotion_idx on public.promotion_redemptions (promotion_id);
create index promotion_redemptions_user_idx on public.promotion_redemptions (user_id);

-- failed code lookups, for COUPON_RATE_LIMIT; rows older than the window are pruned on the next failure
create table public.coupon_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users on delete cascade,
  at timestamptz not null default now()
);
create index coupon_attempts_user_idx on public.coupon_attempts (user_id, at);

alter table public.orders
  add column discount_paise int not null default 0 check (discount_paise >= 0),
  add column promotion_id uuid references public.promotions on delete set null,
  add column coupon_code text check (coupon_code ~ '^[A-Z0-9]{4,20}$'),
  -- an order always costs at least ₹1 before delivery
  add constraint orders_discount_floor_check check (discount_paise = 0 or discount_paise <= subtotal_paise - 100),
  drop constraint orders_check,
  -- bigint: subtotal + fee may pass int even when the discounted total fits
  add constraint orders_total_check check (total_paise = subtotal_paise::bigint + delivery_fee_paise - discount_paise);
create index orders_promotion_idx on public.orders (promotion_id) where promotion_id is not null;

alter table public.order_items
  add column discount_paise int not null default 0
    check (discount_paise >= 0 and discount_paise <= unit_price_paise::bigint * qty); -- this line's share

create table public.banners (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 2 and 60 and public.is_clean_text(title)),
  subtitle text not null default '' check (char_length(subtitle) <= 120 and public.is_clean_text(subtitle)),
  cta_label text not null default 'Shop now' check (char_length(cta_label) between 1 and 20 and public.is_clean_text(cta_label)),
  -- an app route, never a URL
  link text not null check (char_length(link) <= 200 and link ~ '^/(search|product/|offers|repairs)[A-Za-z0-9/?=&%._~+-]*$'),
  image_path text check (image_path ~ '^banners/[A-Za-z0-9_@-]{1,80}\.webp$'), -- in the product-images bucket
  tone int not null default 0 check (tone between 0 and 2), -- index into the app's heroGradients
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  sort int not null default 0,
  is_active boolean not null default true,
  promotion_id uuid unique references public.promotions on delete cascade, -- kept in sync by a trigger
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

alter table public.store_settings
  add column referral_enabled boolean not null default false,
  add column referral_friend_paise int not null default 20000 check (referral_friend_paise >= 100),
  add column referral_reward_paise int not null default 20000 check (referral_reward_paise >= 100),
  add column referral_min_order_paise int not null default 199900 check (referral_min_order_paise >= 0),
  add column referral_monthly_cap int not null default 10 check (referral_monthly_cap >= 0);

create table public.referral_codes (
  user_id uuid primary key references auth.users on delete cascade,
  code text not null unique check (code ~ '^[A-Z0-9]{6,10}$'),
  created_at timestamptz not null default now()
);

create table public.referrals (
  referee_id uuid primary key references auth.users on delete cascade,
  referrer_id uuid not null references auth.users on delete cascade,
  status public.referral_status not null default 'pending',
  created_at timestamptz not null default now(),
  rewarded_at timestamptz,
  check (referee_id <> referrer_id)
);
create index referrals_referrer_idx on public.referrals (referrer_id, status);

create trigger set_updated_at before update on public.promotions for each row execute function public.set_updated_at();
create trigger set_updated_at before update on public.banners for each row execute function public.set_updated_at();

alter table public.collections enable row level security;
alter table public.collection_products enable row level security;
alter table public.promotions enable row level security;
alter table public.promotion_targets enable row level security;
alter table public.promotion_redemptions enable row level security;
alter table public.coupon_attempts enable row level security;
alter table public.banners enable row level security;
alter table public.referral_codes enable row level security;
alter table public.referrals enable row level security;

-- Policies ------------------------------------------------------------------

create policy "public read" on public.collections for select to anon, authenticated using (true);
create policy "public read" on public.collection_products for select to anon, authenticated using (true);
create policy "public read" on public.banners for select to anon
  using (is_active and starts_at <= now() and (ends_at is null or ends_at > now()));
create policy "read" on public.banners for select to authenticated
  using ((is_active and starts_at <= now() and (ends_at is null or ends_at > now())) or (select public.is_admin()));

-- customers never read promotions: hidden and personal codes would be listable (they use the RPCs below)
create policy "admin read" on public.promotions for select to authenticated using ((select public.is_admin()));
create policy "admin read" on public.promotion_targets for select to authenticated using ((select public.is_admin()));
create policy "admin read" on public.promotion_redemptions for select to authenticated using ((select public.is_admin()));
create policy "admin read" on public.referral_codes for select to authenticated using ((select public.is_admin()));
create policy "admin read" on public.referrals for select to authenticated using ((select public.is_admin()));

do $$
declare t text;
begin
  foreach t in array array['collections', 'collection_products', 'promotions', 'promotion_targets', 'banners'] loop
    execute format('create policy "admin insert" on public.%I for insert to authenticated with check ((select public.is_admin()))', t);
    execute format('create policy "admin update" on public.%I for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()))', t);
    if t <> 'promotions' then
      execute format('create policy "admin delete" on public.%I for delete to authenticated using ((select public.is_admin()))', t);
    end if;
  end loop;
end $$;
-- a used offer stays for the records (orders point at it); pause or end it instead
create policy "admin delete" on public.promotions for delete to authenticated
  using ((select public.is_admin()) and not exists (
    select 1 from public.promotion_redemptions r join public.orders o on o.id = r.order_id
    where r.promotion_id = promotions.id and o.status <> 'cancelled'));

-- coupon_attempts: no policies, no client access.

-- Table privileges (see 20261028000300_grants.sql) ----------------------------

revoke all on public.collections, public.collection_products, public.promotions, public.promotion_targets,
  public.promotion_redemptions, public.coupon_attempts, public.banners, public.referral_codes, public.referrals
  from anon, authenticated, service_role;
revoke all on sequence public.coupon_attempts_id_seq from anon, authenticated;

grant select on public.collections, public.collection_products, public.banners to anon, authenticated;
grant insert, update, delete on public.collections, public.collection_products, public.banners to authenticated;
-- staff only (RLS: is_admin()); redemptions and referrals are written by the RPCs and triggers, never by clients
grant select, insert, update, delete on public.promotions, public.promotion_targets to authenticated;
grant select on public.promotion_redemptions, public.referral_codes, public.referrals to authenticated;

grant select, insert, update, delete on public.collections, public.collection_products, public.promotions,
  public.promotion_targets, public.promotion_redemptions, public.coupon_attempts, public.banners,
  public.referral_codes, public.referrals to service_role;

-- Pricing -------------------------------------------------------------------

-- Uses count orders that aren't cancelled: a cancelled or expired order gives its use back.
create function private.promotion_uses(p_promotion_id uuid, p_uid uuid default null) returns int
language sql stable set search_path = '' as $$
  select count(*)::int from public.promotion_redemptions r join public.orders o on o.id = r.order_id
  where r.promotion_id = p_promotion_id and o.status <> 'cancelled' and (p_uid is null or r.user_id = p_uid)
$$;

-- Whether a promotion covers a product: whole order, or the product, its category, its brand or a group with it.
create function private.covers(p_promotion_id uuid, p_product_id uuid) returns boolean
language sql stable set search_path = '' as $$
  select exists (
    select 1 from public.promotions pm join public.products pr on pr.id = p_product_id
    where pm.id = p_promotion_id and (pm.applies_to = 'order' or exists (
      select 1 from public.promotion_targets t
      where t.promotion_id = pm.id and case t.target_type
        when 'product' then t.target_id = pr.id
        when 'category' then t.target_id = pr.category_id
        when 'brand' then t.target_id = pr.brand_id
        when 'collection' then exists (select 1 from public.collection_products cp
                                       where cp.collection_id = t.target_id and cp.product_id = pr.id) end)))
$$;

-- Checks one promotion against the caller's lines (all but the lookup ones: active, owner) and prices it.
-- saving = what the order costs without it minus what it costs with it; a promotion only applies when saving > 0
-- (a discount can push the order under the free-delivery minimum and add the fee back).
create function private.evaluate_promotion(
  p public.promotions, p_uid uuid, p_lines uuid[], p_method public.payment_method,
  p_subtotal bigint, p_base_fee int, p_settings public.store_settings,
  out error text, out detail text, out discount bigint, out fee int, out saving bigint)
language plpgsql stable set search_path = '' as $$
declare
  v_eligible bigint;
  v_count int;
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

  select coalesce(sum(v.price_paise::bigint * c.qty), 0), count(*) into v_eligible, v_count
  from public.cart_items c join public.variants v on v.id = c.variant_id
  where c.user_id = p_uid and c.variant_id = any(p_lines) and private.covers(p.id, v.product_id);
  if v_count = 0 then error := 'COUPON_NOT_APPLICABLE'; return; end if;
  if v_eligible < p.min_subtotal_paise then error := 'COUPON_MIN_ORDER'; detail := p.min_subtotal_paise::text; return; end if;

  discount := case p.kind
    when 'percent' then least(v_eligible * p.value / 100, coalesce(p.max_discount_paise, v_eligible))
    when 'flat' then least(p.value, v_eligible)
    else 0 end;
  discount := greatest(0, least(discount, p_subtotal - 100));
  fee := case when p.kind = 'free_delivery' or p_subtotal - discount >= p_settings.free_delivery_min_paise then 0
              else p_settings.delivery_fee_paise end;
  saving := p_base_fee + discount - fee;
  if saving <= 0 then error := 'COUPON_NOT_APPLICABLE'; end if;
end $$;

-- The one pricing path (SPEC "Pricing"). p_lines: the caller's cart lines (variant ids), locked by place_order.
-- p_lock (place_order): lock the promotion rows before counting uses, so two checkouts can't both take the last use.
-- Returns {subtotal_paise, delivery_fee_paise, discount_paise, total_paise, promotion: {id, title, code, kind} | null,
-- coupon_error, coupon_error_detail, lines: [{variant_id, discount_paise}]}. A bad code sets coupon_error and falls
-- back to the best automatic sale; place_order raises it instead.
create function private.price_lines(p_uid uuid, p_lines uuid[], p_code text, p_method public.payment_method, p_lock boolean)
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
        select e.error, e.detail, e.discount, e.fee into v_error, v_detail, v_discount, v_fee
        from private.evaluate_promotion(v_promo, p_uid, p_lines, p_method, v_subtotal, v_base_fee, v_settings) e;
      end if;
    end if;
  end if;

  if v_code is null or v_error is not null then
    if p_lock then
      perform 1 from public.promotions
      where code is null and is_active and starts_at <= now() and (ends_at is null or ends_at > now())
      order by id for update;
    end if;
    -- best automatic sale: largest saving, then the one ending first
    select p.id, e.discount, e.fee into v_promo_id, v_discount, v_fee
    from public.promotions p
    cross join lateral private.evaluate_promotion(p, p_uid, p_lines, p_method, v_subtotal, v_base_fee, v_settings) e
    where p.code is null and p.is_active and e.error is null
    order by e.saving desc, p.ends_at nulls last, p.id
    limit 1;
    select * into v_promo from public.promotions where id = v_promo_id;
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

-- Offers the caller may use right now: running, theirs to see, uses left (and, signed in, theirs left).
create function private.offer_open(p public.promotions, p_uid uuid) returns boolean
language sql stable set search_path = '' as $$
  select p.is_active and p.starts_at <= now() and (p.ends_at is null or p.ends_at > now())
    and ((p.is_public and p.user_id is null) or p.user_id = p_uid)
    and (p.usage_limit is null or private.promotion_uses(p.id) < p.usage_limit)
    and (p_uid is null or (
      (p.per_user_limit is null or private.promotion_uses(p.id, p_uid) < p.per_user_limit)
      and not (p.first_order_only and exists (select 1 from public.orders o where o.user_id = p_uid and o.status <> 'cancelled'))))
$$;

create function private.offer_json(p public.promotions) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object('id', p.id, 'title', p.title, 'description', p.description, 'code', p.code, 'kind', p.kind,
    'value', p.value, 'max_discount_paise', p.max_discount_paise, 'min_subtotal_paise', p.min_subtotal_paise,
    'starts_at', p.starts_at, 'ends_at', p.ends_at, 'applies_to', p.applies_to, 'automatic', p.code is null,
    'online_only', p.online_only, 'first_order_only', p.first_order_only)
$$;

-- Triggers ------------------------------------------------------------------

-- One banner per promotion with show_banner, same window; off deletes it. Staff edits to its image, tone and sort stay.
create function private.sync_promotion_banner() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.show_banner then
    insert into public.banners (promotion_id, title, subtitle, cta_label, link, starts_at, ends_at, is_active)
    values (new.id, new.title, left(btrim(regexp_replace(new.description, '[[:space:]]+', ' ', 'g')), 120),
      case when new.code is null then 'Shop the sale'
           when char_length(new.code) <= 11 then 'Use code ' || new.code -- cta_label is at most 20
           else 'View offer' end,
      '/offers/' || new.id, new.starts_at, new.ends_at, new.is_active)
    on conflict (promotion_id) do update set title = excluded.title, subtitle = excluded.subtitle,
      cta_label = excluded.cta_label, link = excluded.link, starts_at = excluded.starts_at, ends_at = excluded.ends_at,
      is_active = excluded.is_active;
  else
    delete from public.banners where promotion_id = new.id;
  end if;
  return null;
end $$;

create trigger sync_promotion_banner after insert or update on public.promotions
for each row execute function private.sync_promotion_banner();

-- A pending referral pays the referrer once, when one of the referee's orders of at least the minimum is delivered,
-- unless the referrer already got referral_monthly_cap rewards this IST month (then it's void).
create function private.reward_referral() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_settings public.store_settings;
  v_referrer uuid;
begin
  select * into v_settings from public.store_settings;
  if new.subtotal_paise < v_settings.referral_min_order_paise then return null; end if;
  select referrer_id into v_referrer from public.referrals where referee_id = new.user_id and status = 'pending' for update;
  if not found then return null; end if;

  perform pg_advisory_xact_lock(hashtextextended('referrals:' || v_referrer, 0)); -- the monthly count
  if (select count(*) from public.referrals where referrer_id = v_referrer and status = 'rewarded'
      and rewarded_at >= date_trunc('month', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata')
     >= v_settings.referral_monthly_cap then
    update public.referrals set status = 'void' where referee_id = new.user_id;
    return null;
  end if;

  insert into public.promotions (title, code, kind, value, min_subtotal_paise, ends_at, usage_limit, per_user_limit, is_public, user_id)
  values ('Thanks for referring a friend', 'REWARD' || upper(substr(md5(gen_random_uuid()::text), 1, 10)), 'flat',
    v_settings.referral_reward_paise, v_settings.referral_min_order_paise, now() + interval '90 days', 1, 1, false, v_referrer);
  update public.referrals set status = 'rewarded', rewarded_at = now() where referee_id = new.user_id;
  return null;
end $$;

create trigger reward_referral after update of status on public.orders
for each row when (new.status = 'delivered' and old.status <> 'delivered' and new.user_id is not null)
execute function private.reward_referral();

-- Checkout ------------------------------------------------------------------

drop function public.place_order(uuid, public.payment_method);

create function public.place_order(p_address_id uuid, p_payment_method public.payment_method, p_coupon_code text default null)
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

  select string_agg(v.id::text, ',') into v_unavailable
  from public.cart_items c
  join public.variants v on v.id = c.variant_id
  join public.products p on p.id = v.product_id
  where c.user_id = v_uid and c.variant_id = any(v_lines) and (not v.is_active or not p.is_active or v.stock < c.qty);
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
    (order_id, variant_id, product_id, product_name, variant_name, image_path, unit_price_paise, qty, gst_rate, discount_paise)
  select v_order_id, v.id, p.id, p.name, v.name,
    (select pi.path from public.product_images pi where pi.product_id = p.id order by pi.sort, pi.id limit 1),
    v.price_paise, c.qty, p.gst_rate,
    coalesce((select (l ->> 'discount_paise')::int from jsonb_array_elements(v_price -> 'lines') l
              where (l ->> 'variant_id')::uuid = v.id), 0)
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
  where c.user_id = v_uid and c.variant_id = v.id and c.variant_id = any(v_lines);

  delete from public.cart_items where user_id = v_uid and variant_id = any(v_lines);

  insert into public.order_events (order_id, status) values (v_order_id, v_status);
  return v_order_id;
end $$;

-- Prices the caller's cart as place_order would, without placing anything (only a failed code lookup is recorded).
create function public.quote_order(p_coupon_code text default null, p_payment_method public.payment_method default null)
returns json
language plpgsql security definer set search_path = '' as $$
declare
  v_lines uuid[];
begin
  select array_agg(variant_id order by variant_id) into v_lines from public.cart_items where user_id = auth.uid();
  if v_lines is null then raise exception 'CART_EMPTY'; end if;
  return (private.price_lines(auth.uid(), v_lines, p_coupon_code, p_payment_method, false) - 'lines')::json;
end $$;

-- Offers --------------------------------------------------------------------

create function public.available_offers() returns json
language sql stable security definer set search_path = '' as $$
  select coalesce(json_agg(private.offer_json(p) order by p.user_id is null, p.ends_at nulls last, p.created_at desc, p.id), '[]')
  from public.promotions p
  where private.offer_open(p, auth.uid())
$$;

create function public.offers_for_product(p_product_id uuid) returns json
language sql stable security definer set search_path = '' as $$
  select coalesce(json_agg(private.offer_json(p) order by p.user_id is null, p.ends_at nulls last, p.created_at desc, p.id), '[]')
  from public.promotions p
  where private.offer_open(p, auth.uid()) and private.covers(p.id, p_product_id)
$$;

-- What /offers/:id lists. Hidden and personal offers show nothing to anyone but their owner (and staff).
create function public.offer_products(p_promotion_id uuid) returns setof public.product_cards
language sql stable security definer set search_path = '' as $$
  select c.* from public.product_cards c
  where exists (
      select 1 from public.promotions p
      where p.id = p_promotion_id and p.is_active and (p.ends_at is null or p.ends_at > now())
        and ((p.is_public and p.user_id is null) or p.user_id = auth.uid() or public.is_admin()))
    and private.covers(p_promotion_id, c.id)
$$;

-- Referrals -----------------------------------------------------------------

create function public.my_referral() returns json
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_settings public.store_settings;
  v_code text;
begin
  select * into v_settings from public.store_settings;
  select code into v_code from public.referral_codes where user_id = v_uid;
  while v_code is null loop -- a new random code; retried on the (rare) clash
    insert into public.referral_codes (user_id, code) values (v_uid, upper(substr(md5(gen_random_uuid()::text), 1, 8)))
    on conflict do nothing returning code into v_code;
    if v_code is null then select code into v_code from public.referral_codes where user_id = v_uid; end if;
  end loop;

  return json_build_object(
    'enabled', v_settings.referral_enabled,
    'code', v_code,
    'friend_paise', v_settings.referral_friend_paise,
    'reward_paise', v_settings.referral_reward_paise,
    'min_order_paise', v_settings.referral_min_order_paise,
    'joined', (select count(*) from public.referrals where referrer_id = v_uid),
    'rewarded', (select count(*) from public.referrals where referrer_id = v_uid and status = 'rewarded'),
    'can_enter_code', v_settings.referral_enabled
      and not exists (select 1 from public.referrals where referee_id = v_uid)
      and not exists (select 1 from public.orders where user_id = v_uid and status <> 'cancelled'));
end $$;

create function public.apply_referral_code(p_code text) returns json
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_settings public.store_settings;
  v_referrer uuid;
  v_promo public.promotions;
begin
  select * into v_settings from public.store_settings;
  if not v_settings.referral_enabled then raise exception 'REFERRAL_OFF'; end if;
  perform pg_advisory_xact_lock(hashtextextended('orders:' || v_uid, 0)); -- place_order's lock: no checkout slips in
  if exists (select 1 from public.referrals where referee_id = v_uid) then raise exception 'REFERRAL_USED'; end if;
  if exists (select 1 from public.orders where user_id = v_uid and status <> 'cancelled') then
    raise exception 'REFERRAL_TOO_LATE';
  end if;
  select user_id into v_referrer from public.referral_codes
  where code = upper(regexp_replace(coalesce(p_code, ''), '[[:space:]]', '', 'g'));
  if not found then raise exception 'REFERRAL_INVALID'; end if;
  if v_referrer = v_uid then raise exception 'REFERRAL_SELF'; end if;

  insert into public.referrals (referee_id, referrer_id) values (v_uid, v_referrer);
  insert into public.promotions (title, code, kind, value, min_subtotal_paise, ends_at, usage_limit, per_user_limit,
    first_order_only, is_public, user_id)
  values ('Welcome gift from a friend', 'FRIEND' || upper(substr(md5(gen_random_uuid()::text), 1, 10)), 'flat',
    v_settings.referral_friend_paise, v_settings.referral_min_order_paise, now() + interval '90 days', 1, 1, true, false, v_uid)
  returning * into v_promo;
  return private.offer_json(v_promo)::json;
end $$;

-- Admin ---------------------------------------------------------------------

-- p: promotion columns (id to update; keys left out keep their value, or the default on insert) plus optional
-- targets [{target_type, target_id}] (replaces the old ones when present). Rule breaks: INVALID_PROMOTION with the
-- rule (constraint or column) in details; a code in use: CODE_TAKEN.
create function public.admin_save_promotion(p json) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v jsonb := p::jsonb;
  v_row public.promotions;
  v_rule text;
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  if jsonb_typeof(v) is distinct from 'object' then raise exception 'INVALID_PROMOTION'; end if;
  begin
    if v ? 'code' then
      v := jsonb_set(v, '{code}', coalesce(to_jsonb(nullif(upper(btrim(v ->> 'code')), '')), 'null'));
    end if;
    if v ->> 'id' is null then
      insert into public.promotions (title, kind, value)
      values (v ->> 'title', (v ->> 'kind')::public.promotion_kind, coalesce((v ->> 'value')::int, 0))
      returning * into v_row;
    else
      select * into v_row from public.promotions where id = (v ->> 'id')::uuid for update;
      if not found then raise exception 'NOT_FOUND'; end if;
    end if;
    v_row := jsonb_populate_record(v_row, v - 'id' - 'created_at' - 'updated_at' - 'targets');
    update public.promotions set (title, description, code, kind, value, max_discount_paise, min_subtotal_paise,
      applies_to, starts_at, ends_at, usage_limit, per_user_limit, first_order_only, online_only, is_public, user_id,
      is_active, show_banner)
    = (v_row.title, v_row.description, v_row.code, v_row.kind, v_row.value, v_row.max_discount_paise,
      v_row.min_subtotal_paise, v_row.applies_to, v_row.starts_at, v_row.ends_at, v_row.usage_limit,
      v_row.per_user_limit, v_row.first_order_only, v_row.online_only, v_row.is_public, v_row.user_id,
      v_row.is_active, v_row.show_banner)
    where id = v_row.id;

    if v ? 'targets' or v_row.applies_to = 'order' then
      delete from public.promotion_targets where promotion_id = v_row.id;
    end if;
    if v ? 'targets' and v_row.applies_to = 'items' then
      insert into public.promotion_targets (promotion_id, target_type, target_id)
      select v_row.id, (t ->> 'target_type')::public.promotion_target_type, (t ->> 'target_id')::uuid
      from jsonb_array_elements(coalesce(v -> 'targets', '[]')) t
      on conflict do nothing;
    end if;
    if exists (select 1 from public.promotion_targets t where t.promotion_id = v_row.id and not case t.target_type
        when 'product' then exists (select 1 from public.products where id = t.target_id)
        when 'category' then exists (select 1 from public.categories where id = t.target_id)
        when 'brand' then exists (select 1 from public.brands where id = t.target_id)
        when 'collection' then exists (select 1 from public.collections where id = t.target_id) end) then
      raise exception using message = 'INVALID_PROMOTION', detail = 'unknown target';
    end if;
    if v_row.applies_to = 'items' and not exists (select 1 from public.promotion_targets where promotion_id = v_row.id) then
      raise exception using message = 'INVALID_PROMOTION', detail = 'items needs a target';
    end if;
  exception
    when unique_violation then raise exception 'CODE_TAKEN';
    when check_violation or not_null_violation or invalid_text_representation or invalid_parameter_value
      or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
      get stacked diagnostics v_rule = constraint_name;
      if v_rule = '' then get stacked diagnostics v_rule = column_name; end if;
      if v_rule = '' then get stacked diagnostics v_rule = message_text; end if;
      raise exception using message = 'INVALID_PROMOTION', detail = v_rule;
  end;
  return v_row.id;
end $$;

create function public.admin_promotions() returns json
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  return (
    select coalesce(json_agg(to_jsonb(p) || jsonb_build_object(
      'status', case when not p.is_active then 'paused' when p.ends_at <= now() then 'ended'
                     when p.starts_at > now() then 'scheduled' else 'running' end,
      'uses', private.promotion_uses(p.id),
      'discount_total_paise', (select coalesce(sum(r.discount_paise), 0) from public.promotion_redemptions r
                               join public.orders o on o.id = r.order_id where r.promotion_id = p.id and o.status <> 'cancelled'),
      'targets', (select coalesce(jsonb_agg(jsonb_build_object('target_type', t.target_type, 'target_id', t.target_id)
                                            order by t.target_type, t.target_id), '[]')
                  from public.promotion_targets t where t.promotion_id = p.id))
      order by p.created_at desc, p.id), '[]')
    from public.promotions p
  );
end $$;

-- Grants: Supabase grants execute on new functions to anon/authenticated by default; undo that.

revoke execute on all functions in schema private from public, anon, authenticated;

revoke execute on function
  public.place_order(uuid, public.payment_method, text),
  public.quote_order(text, public.payment_method),
  public.available_offers(),
  public.offers_for_product(uuid),
  public.offer_products(uuid),
  public.my_referral(),
  public.apply_referral_code(text),
  public.admin_save_promotion(json),
  public.admin_promotions()
from public, anon, authenticated, service_role;

-- admin_* check is_admin() inside
grant execute on function
  public.place_order(uuid, public.payment_method, text),
  public.quote_order(text, public.payment_method),
  public.my_referral(),
  public.apply_referral_code(text),
  public.admin_save_promotion(json),
  public.admin_promotions()
to authenticated;

grant execute on function
  public.available_offers(),
  public.offers_for_product(uuid),
  public.offer_products(uuid)
to anon, authenticated;
