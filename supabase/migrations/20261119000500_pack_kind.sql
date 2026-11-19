-- A phone pack offer (docs: Admin > Offers > New pack offer): its own migration because a new enum value can't be
-- used in the transaction that adds it.
alter type public.promotion_kind add value if not exists 'pack';
