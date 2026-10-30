-- A product photo beside the words (docs/SPEC.md, "Notifications"): notifications about an order show its main
-- item's photo, stock alerts the product's cover, feedback on an order or a product that order's or product's photo.
-- Repairs and offers have none (the app shows the kind's illustration). The push carries the path; the phone builds
-- the URL from its own Supabase URL and draws the notification itself (send-push sends data-only messages).

alter table public.notifications
  add column image_path text check (image_path ~ '^[A-Za-z0-9_-]{1,80}/[A-Za-z0-9_@-]{1,80}\.(webp|jpe?g|png)$'); -- product-images key

-- The order's priciest line with a photo (the one its summary names first), else the product's cover. Feedback
-- and stock notifications name their row in the link (/admin/feedback/<id>, /admin/products/<id>).
create function private.notification_image(p_order uuid, p_link text) returns text
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uuid constant text := '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
  v_product uuid;
begin
  if p_link ~ ('^/admin/feedback/' || v_uuid || '$') then
    select f.order_id, f.product_id into p_order, v_product from public.feedback f where f.id = substr(p_link, 17)::uuid;
  elsif p_link ~ ('^/admin/products/' || v_uuid || '$') then
    v_product := substr(p_link, 17)::uuid;
  end if;
  return coalesce(
    (select i.image_path from public.order_items i where i.order_id = p_order and i.image_path is not null
     order by i.unit_price_paise desc, i.id limit 1),
    (select pi.path from public.product_images pi where pi.product_id = v_product order by pi.sort, pi.id limit 1));
end $$;

-- Every new notification, whichever trigger wrote it (ours and the payment ones), gets its photo here. A photo is
-- never worth failing the order behind it: any error just leaves it out.
create function private.notification_image_before_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  begin
    new.image_path := coalesce(new.image_path, private.notification_image(new.order_id, new.link));
  exception when others then
    new.image_path := null;
  end;
  return new;
end $$;

create trigger notification_image before insert on public.notifications
for each row execute function private.notification_image_before_insert();

update public.notifications set image_path = private.notification_image(order_id, link) where image_path is null;

-- As before (20261030000400), plus the photo's path.
create or replace function private.push_notification() returns trigger
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
      'link', new.link, 'image_path', new.image_path, 'tokens', to_jsonb(v_tokens)),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', v_secret),
    timeout_milliseconds := 5000);
  return null;
exception when others then
  raise warning 'push for notification % skipped: %', new.id, sqlerrm;
  return null;
end $$;

revoke execute on function private.notification_image(uuid, text), private.notification_image_before_insert()
from public, anon, authenticated;
