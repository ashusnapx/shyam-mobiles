-- Customer feedback: a rating and/or a comment, about an order, a repair, a product listing, a bug, or anything.
-- Customers write through send_feedback() only (it checks ownership and a daily cap) and read their own rows; the
-- shop reads all of it and tracks each one new → seen → resolved.
create type public.feedback_kind as enum ('general', 'order', 'repair', 'product', 'bug');
create type public.feedback_status as enum ('new', 'seen', 'resolved');

create table public.feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users on delete set null,
  kind public.feedback_kind not null,
  rating int check (rating between 1 and 5),
  message text not null default '' check (char_length(message) <= 1000 and public.is_clean_text(message, true)),
  order_id uuid references public.orders on delete set null,
  repair_id uuid references public.repair_bookings on delete set null,
  product_id uuid references public.products on delete set null,
  screen text check (char_length(screen) <= 200 and screen ~ '^/[A-Za-z0-9/_?=&.%-]*$'), -- where it was sent from
  app_version text check (char_length(app_version) <= 40 and app_version ~ '^[0-9A-Za-z.+-]+$'),
  status public.feedback_status not null default 'new',
  admin_note text check (char_length(admin_note) <= 500 and public.is_clean_text(admin_note, true)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (rating is not null or char_length(btrim(message)) > 0),
  check (kind <> 'order' or order_id is not null),
  check (kind <> 'repair' or repair_id is not null),
  check (kind <> 'product' or product_id is not null)
);
create index feedback_status_idx on public.feedback (status, created_at desc);
create index feedback_user_idx on public.feedback (user_id, created_at desc);
-- one rating per order and per repair: rating again replaces it
create unique index feedback_order_once on public.feedback (order_id) where kind = 'order';
create unique index feedback_repair_once on public.feedback (repair_id) where kind = 'repair';
create trigger set_updated_at before update on public.feedback for each row execute function public.set_updated_at();

alter table public.feedback enable row level security;
create policy "own or admin read" on public.feedback for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy "admin update" on public.feedback for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

revoke all on public.feedback from public, anon, authenticated, service_role;
grant select on public.feedback to authenticated;
grant update (status, admin_note) on public.feedback to authenticated;
grant all on public.feedback to service_role;

create function public.send_feedback(
  p_kind public.feedback_kind,
  p_rating int default null,
  p_message text default '',
  p_order_id uuid default null,
  p_repair_id uuid default null,
  p_product_id uuid default null,
  p_screen text default null,
  p_app_version text default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
begin
  if v_uid is null then raise exception 'FORBIDDEN'; end if;
  -- the link must be the caller's own order or repair; a product just has to exist
  if p_order_id is not null and not exists (select 1 from public.orders where id = p_order_id and user_id = v_uid) then
    raise exception 'NOT_FOUND';
  end if;
  if p_repair_id is not null
     and not exists (select 1 from public.repair_bookings where id = p_repair_id and user_id = v_uid) then
    raise exception 'NOT_FOUND';
  end if;
  if p_product_id is not null and not exists (select 1 from public.products where id = p_product_id) then
    raise exception 'NOT_FOUND';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('feedback:' || v_uid, 0));
  if (select count(*) from public.feedback where user_id = v_uid and created_at > now() - interval '1 day') >= 10 then
    raise exception 'FEEDBACK_LIMIT';
  end if;

  if p_kind in ('order', 'repair') then
    -- rating the same order or repair again replaces the earlier rating, and the shop sees it as new
    update public.feedback set rating = p_rating, message = btrim(coalesce(p_message, '')), screen = p_screen,
        app_version = p_app_version, status = 'new'
      where kind = p_kind and user_id = v_uid
        and (order_id = p_order_id and p_kind = 'order' or repair_id = p_repair_id and p_kind = 'repair')
      returning id into v_id;
    if v_id is not null then return v_id; end if;
  end if;

  insert into public.feedback (user_id, kind, rating, message, order_id, repair_id, product_id, screen, app_version)
  values (v_uid, p_kind, p_rating, btrim(coalesce(p_message, '')), p_order_id, p_repair_id, p_product_id, p_screen,
          p_app_version)
  returning id into v_id;
  return v_id;
end $$;

revoke execute on function public.send_feedback(public.feedback_kind, int, text, uuid, uuid, uuid, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.send_feedback(public.feedback_kind, int, text, uuid, uuid, uuid, text, text)
  to authenticated;
