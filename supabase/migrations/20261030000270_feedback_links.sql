-- The order, repair or product a feedback row is about may be deleted later (the links are on delete set null), so
-- the table can't require them: deleting an order with feedback failed on these checks. send_feedback checks the
-- link when the feedback is sent instead, and the row keeps its rating and words afterwards.
alter table public.feedback
  drop constraint feedback_check1,
  drop constraint feedback_check2,
  drop constraint feedback_check3;

create or replace function public.send_feedback(
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
  if p_kind = 'order' and p_order_id is null or p_kind = 'repair' and p_repair_id is null
     or p_kind = 'product' and p_product_id is null then
    raise exception 'BAD_REQUEST' using detail = p_kind || ' feedback needs its ' || p_kind;
  end if;
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
