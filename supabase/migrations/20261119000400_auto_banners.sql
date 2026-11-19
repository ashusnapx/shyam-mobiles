-- Home's automatic banners (Admin > Banners turns each on or off), after the owner's own: deal of the day, newest
-- product, exchange, same-day repairs. Repairs starts off: only the owner can promise same-day.
alter table public.store_settings
  add column auto_banners text[] not null default '{deal,newest,exchange}'
    check (auto_banners <@ array['deal', 'newest', 'exchange', 'repairs']);
