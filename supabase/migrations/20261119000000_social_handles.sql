-- The shop's Instagram and Facebook usernames (Admin > Settings) for Home's and Account's Follow buttons; null hides
-- a button. Bare handles only: the app builds https://instagram.com/<h> and https://facebook.com/<h> itself, so a
-- saved value can never point anywhere else. Staff update them through the existing "admin update" policy.
alter table public.store_settings
  add column instagram_handle text check (instagram_handle ~ '^[A-Za-z0-9._]{1,30}$'),
  add column facebook_handle text check (facebook_handle ~ '^[A-Za-z0-9.]{5,50}$');

-- A banner photo's JPEG copy (banners/<millis>.jpg, uploaded beside its WebP): Instagram and Facebook posts take no
-- WebP. Null for banners saved before the copy existed.
alter table public.banners
  add column social_image_path text check (social_image_path ~ '^banners/[A-Za-z0-9_@-]{1,80}\.jpg$');
