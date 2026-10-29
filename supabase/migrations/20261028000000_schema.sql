-- Shyam Mobiles v1 schema: tables, enums, views. RLS is enabled here (deny-all);
-- policies, RPCs, triggers and cron jobs live in later migrations.

create type public.category_kind as enum ('phone', 'accessory');
create type public.order_status as enum ('pending_payment', 'confirmed', 'packed', 'shipped', 'delivered', 'cancelled', 'refunded');
create type public.payment_method as enum ('razorpay', 'cod');
create type public.payment_status as enum ('pending', 'paid', 'failed', 'refunded');
create type public.repair_status as enum ('requested', 'confirmed', 'in_progress', 'ready', 'completed', 'cancelled');
create type public.repair_slot as enum ('morning', 'afternoon', 'evening');
create type public.repair_issue as enum ('screen', 'battery', 'charging', 'camera', 'audio', 'water_damage', 'software', 'other');

-- Indian mobile numbers are stored as E.164: +91XXXXXXXXXX
create domain public.in_phone as text check (value ~ '^\+91[6-9][0-9]{9}$');

-- Input rules live here, not only in the app (anyone can call the API directly). Text people type: no control or
-- invisible formatting characters (zero-width space, LRM/RLM, bidi overrides and isolates, word joiner, BOM, soft
-- hyphen) that could hide or reorder what staff read, and not whitespace-only ('' is fine where allowed).
-- Newlines and tabs only where p_multiline. ZWJ/ZWNJ stay allowed: Hindi typing uses them.
create function public.is_clean_text(p text, p_multiline boolean default false) returns boolean
language sql immutable set search_path = '' as $$
  select (p = '' or p ~ '[^[:space:]]') and p !~ case when p_multiline
    then '[\x01-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f\u00ad\u200b\u200e\u200f\u202a-\u202e\u2060-\u2064\u2066-\u2069\ufeff]'
    else '[\x01-\x1f\x7f-\x9f\u00ad\u200b\u200e\u200f\u202a-\u202e\u2060-\u2064\u2066-\u2069\ufeff]' end
$$;
-- a person's or place's name: clean, one line, and at least one letter in any script (so not "😀😀" or "...")
create function public.is_name(p text) returns boolean
language sql immutable set search_path = '' as $$ select public.is_clean_text(p) and p ~ '[[:alpha:]]' $$;
-- order line IMEIs: a flat list of distinct 15-digit values
create function public.is_imei_list(p text[]) returns boolean
language sql immutable set search_path = '' as $$
  select coalesce(array_ndims(p), 1) = 1
    and not exists (select 1 from unnest(p) v where v is null or v !~ '^[0-9]{15}$')
    and cardinality(p) = (select count(distinct v) from unnest(p) v)
$$;
-- shop photo keys: store/<millis>.<ext>
create function public.is_store_photo_list(p text[]) returns boolean
language sql immutable set search_path = '' as $$
  select not exists (select 1 from unnest(p) v where v is null or v !~ '^store/[0-9]{1,15}\.(webp|jpe?g|png)$')
$$;

create function public.set_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- People ------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  full_name text check (char_length(full_name) <= 80 and public.is_name(full_name)),
  phone public.in_phone,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.admins (
  user_id uuid primary key references auth.users on delete cascade,
  created_at timestamptz not null default now()
);

-- Catalog -----------------------------------------------------------------

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9-]{1,160}$'),
  name text not null check (char_length(name) between 2 and 40 and public.is_clean_text(name)),
  kind public.category_kind not null,
  sort int not null default 0
);

create table public.brands (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9-]{1,160}$'),
  name text not null check (char_length(name) between 1 and 40 and public.is_clean_text(name))
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9-]{1,160}$'), -- ASCII only: no Unicode look-alikes
  -- convention: name starts with the brand ("Samsung Galaxy S25") so search matches brand words
  name text not null check (char_length(name) between 2 and 120 and public.is_clean_text(name)),
  brand_id uuid not null references public.brands,
  category_id uuid not null references public.categories,
  description text not null default '' check (char_length(description) <= 5000 and public.is_clean_text(description, true)),
  specs jsonb not null default '[]' check (jsonb_typeof(specs) = 'array' and octet_length(specs::text) <= 20000), -- ordered [{"label": "Display", "value": "6.2in AMOLED"}]
  gst_rate numeric(4, 2) not null default 18 check (gst_rate between 0 and 28),
  is_active boolean not null default true,
  is_featured boolean not null default false,
  search tsvector generated always as (to_tsvector('simple'::regconfig, name || ' ' || description)) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index products_search_idx on public.products using gin (search);
create index products_category_idx on public.products (category_id);
create index products_brand_idx on public.products (brand_id);

create table public.product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products on delete cascade,
  path text not null check (path ~ '^[A-Za-z0-9_-]{1,80}/[A-Za-z0-9_@-]{1,80}\.(webp|jpe?g|png)$'), -- object key in the public `product-images` bucket
  sort int not null default 0
);
create index product_images_product_idx on public.product_images (product_id, sort);

create table public.variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products on delete cascade,
  sku text not null unique check (sku ~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,59}$'), -- ASCII only: no look-alikes
  name text not null check (char_length(name) between 1 and 80 and public.is_clean_text(name)), -- "8 GB · 256 GB · Black"
  attributes jsonb not null default '{}' check (jsonb_typeof(attributes) = 'object' and octet_length(attributes::text) <= 1000
    and coalesce(attributes ->> 'color_hex' ~ '^#[0-9a-fA-F]{6}$', true)), -- {ram, storage, color, color_hex}
  price_paise int not null check (price_paise > 0),
  mrp_paise int not null,
  stock int not null default 0 check (stock between 0 and 1000000), -- the cap keeps restocks far from int overflow
  is_active boolean not null default true,
  sort int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (mrp_paise >= price_paise)
);
create index variants_product_idx on public.variants (product_id, sort);

-- Listing contract: one row per sellable product.
create view public.product_cards with (security_invoker = true) as
select
  p.id, p.slug, p.name, p.is_featured, p.created_at, p.search,
  p.category_id, c.slug as category_slug, c.kind as category_kind,
  p.brand_id, b.slug as brand_slug, b.name as brand_name,
  v.min_price_paise, v.mrp_paise, v.in_stock,
  (select pi.path from public.product_images pi
    where pi.product_id = p.id order by pi.sort, pi.id limit 1) as cover_path
from public.products p
join public.categories c on c.id = p.category_id
join public.brands b on b.id = p.brand_id
join lateral (
  select
    min(price_paise) as min_price_paise,
    (array_agg(mrp_paise order by price_paise))[1] as mrp_paise, -- MRP of the cheapest variant
    coalesce(sum(stock), 0) > 0 as in_stock
  from public.variants
  where product_id = p.id and is_active
) v on true
where p.is_active and v.min_price_paise is not null;

-- Shopping ----------------------------------------------------------------

create table public.wishlist (
  user_id uuid not null references auth.users on delete cascade,
  product_id uuid not null references public.products on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, product_id)
);
create index wishlist_product_idx on public.wishlist (product_id); -- FK: product deletes cascade here

create table public.cart_items (
  user_id uuid not null references auth.users on delete cascade,
  variant_id uuid not null references public.variants on delete cascade,
  qty int not null check (qty between 1 and 5),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, variant_id)
);
create index cart_items_variant_idx on public.cart_items (variant_id); -- FK: variant deletes cascade here

create table public.addresses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  name text not null check (char_length(name) between 2 and 80 and public.is_name(name)),
  phone public.in_phone not null,
  line1 text not null check (char_length(line1) between 3 and 120 and public.is_clean_text(line1)),
  line2 text check (char_length(line2) <= 120 and public.is_clean_text(line2)),
  landmark text check (char_length(landmark) <= 80 and public.is_clean_text(landmark)),
  city text not null check (char_length(city) between 2 and 60 and public.is_name(city)),
  district text check (char_length(district) <= 60 and public.is_name(district)),
  state text not null check (char_length(state) between 2 and 60 and public.is_name(state)),
  pincode text not null check (pincode ~ '^[1-9][0-9]{5}$'),
  label text not null default 'home' check (label in ('home', 'work', 'other')),
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index addresses_one_default on public.addresses (user_id) where is_default;

create sequence public.order_number_seq start 100001;

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  number text not null unique default 'SM' || nextval('public.order_number_seq'),
  user_id uuid references auth.users on delete set null, -- kept for tax records after account deletion
  status public.order_status not null,
  payment_method public.payment_method not null,
  payment_status public.payment_status not null default 'pending',
  subtotal_paise int not null check (subtotal_paise > 0),
  delivery_fee_paise int not null default 0 check (delivery_fee_paise >= 0),
  total_paise int not null,
  address jsonb not null, -- snapshot of the address row at order time
  razorpay_order_id text unique check (razorpay_order_id ~ '^[A-Za-z0-9_]{1,64}$'),
  razorpay_payment_id text unique check (razorpay_payment_id ~ '^[A-Za-z0-9_]{1,64}$'),
  courier text check (char_length(courier) <= 60 and public.is_clean_text(courier)),
  tracking_number text check (char_length(tracking_number) <= 60 and public.is_clean_text(tracking_number)),
  reserved_until timestamptz, -- stock hold for unpaid Razorpay orders
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (total_paise = subtotal_paise + delivery_fee_paise)
);
create index orders_user_idx on public.orders (user_id, created_at desc);
create index orders_status_idx on public.orders (status, created_at desc);
create index orders_expiry_idx on public.orders (reserved_until) where status = 'pending_payment';

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders on delete cascade,
  variant_id uuid references public.variants on delete set null,
  product_id uuid references public.products on delete set null,
  product_name text not null,
  variant_name text not null,
  image_path text,
  unit_price_paise int not null check (unit_price_paise > 0),
  qty int not null check (qty between 1 and 5),
  gst_rate numeric(4, 2) not null,
  imeis text[] not null default '{}' check (cardinality(imeis) in (0, qty) and public.is_imei_list(imeis))
);
create index order_items_order_idx on public.order_items (order_id);
create index order_items_variant_idx on public.order_items (variant_id); -- FKs: catalog deletes set these null
create index order_items_product_idx on public.order_items (product_id);

create table public.order_events (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.orders on delete cascade,
  status public.order_status not null,
  note text check (char_length(note) <= 500 and public.is_clean_text(note, true)),
  created_at timestamptz not null default now()
);
create index order_events_order_idx on public.order_events (order_id, created_at);

create table public.payment_events (
  id bigint generated always as identity primary key,
  razorpay_event_id text not null unique check (char_length(razorpay_event_id) <= 100), -- header, not signed
  type text not null check (char_length(type) <= 100),
  payload jsonb not null,
  received_at timestamptz not null default now()
);

-- Repairs -----------------------------------------------------------------

create sequence public.repair_number_seq start 100001;

create table public.repair_bookings (
  id uuid primary key default gen_random_uuid(),
  number text not null unique default 'RP' || nextval('public.repair_number_seq'),
  user_id uuid references auth.users on delete set null,
  device_brand text not null check (char_length(device_brand) between 1 and 40 and public.is_clean_text(device_brand)),
  device_model text not null check (char_length(device_model) between 1 and 60 and public.is_clean_text(device_model)),
  issue public.repair_issue not null,
  description text not null default '' check (char_length(description) <= 500 and public.is_clean_text(description, true)),
  preferred_date date not null,
  slot public.repair_slot not null,
  contact_phone public.in_phone not null,
  status public.repair_status not null default 'requested',
  quote_paise int check (quote_paise >= 0),
  admin_note text check (char_length(admin_note) <= 500 and public.is_clean_text(admin_note, true)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index repair_bookings_user_idx on public.repair_bookings (user_id, created_at desc);
create index repair_bookings_status_idx on public.repair_bookings (status, preferred_date);

-- Settings ----------------------------------------------------------------

create table public.store_settings (
  id boolean primary key default true check (id), -- single row
  delivery_fee_paise int not null default 4900 check (delivery_fee_paise >= 0),
  free_delivery_min_paise int not null default 99900 check (free_delivery_min_paise >= 0),
  cod_enabled boolean not null default true,
  cod_max_paise int not null default 2500000 check (cod_max_paise >= 0),
  store_phone public.in_phone not null default '+919999999999',
  store_address text not null default '' check (char_length(store_address) <= 300 and public.is_clean_text(store_address, true)),
  -- the shop's map pin (directions go here); both or neither
  store_lat double precision check (store_lat between -90 and 90),
  store_lng double precision check (store_lng between -180 and 180),
  constraint store_pin_complete check ((store_lat is null) = (store_lng is null)),
  -- the Google Maps listing, linked to for photos, reviews and hours; never fetched
  store_maps_url text check (char_length(store_maps_url) <= 500 and store_maps_url like 'https://%'),
  -- object keys in the product-images bucket (store/<millis>.<ext>), in display order
  store_photos text[] not null default '{}' check (cardinality(store_photos) <= 8 and public.is_store_photo_list(store_photos)),
  store_hours text not null default '10 am – 9 pm' check (char_length(store_hours) <= 60 and public.is_clean_text(store_hours)),
  repair_note text not null default 'Final price is confirmed after inspection at the store.'
    check (char_length(repair_note) <= 300 and public.is_clean_text(repair_note, true)),
  -- placeholder policy: the owner must review and edit it in Admin → Settings before launch
  returns_policy text not null default 'Unopened items can be returned within 7 days of delivery for a full refund. Phones are covered by the brand''s warranty, and we help you claim it at the store. Got a damaged or wrong item? Tell us within 48 hours of delivery and share an unboxing video.'
    check (char_length(returns_policy) <= 2000 and public.is_clean_text(returns_policy, true)),
  updated_at timestamptz not null default now()
);
insert into public.store_settings default values;

-- updated_at triggers -------------------------------------------------------

create trigger set_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger set_updated_at before update on public.products for each row execute function public.set_updated_at();
create trigger set_updated_at before update on public.variants for each row execute function public.set_updated_at();
create trigger set_updated_at before update on public.cart_items for each row execute function public.set_updated_at();
create trigger set_updated_at before update on public.addresses for each row execute function public.set_updated_at();
create trigger set_updated_at before update on public.orders for each row execute function public.set_updated_at();
create trigger set_updated_at before update on public.repair_bookings for each row execute function public.set_updated_at();
create trigger set_updated_at before update on public.store_settings for each row execute function public.set_updated_at();

-- Deny everything until policies say otherwise ------------------------------

alter table public.profiles enable row level security;
alter table public.admins enable row level security;
alter table public.categories enable row level security;
alter table public.brands enable row level security;
alter table public.products enable row level security;
alter table public.product_images enable row level security;
alter table public.variants enable row level security;
alter table public.wishlist enable row level security;
alter table public.cart_items enable row level security;
alter table public.addresses enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.order_events enable row level security;
alter table public.payment_events enable row level security;
alter table public.repair_bookings enable row level security;
alter table public.store_settings enable row level security;
