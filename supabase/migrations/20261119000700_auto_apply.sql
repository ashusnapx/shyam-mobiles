-- Campaign calendar (docs/GROWTH.md): a coded offer staff mark "auto-apply" is filled in for the customer in the cart
-- and at checkout while it runs, when no code is typed. Pricing doesn't change: quote_order and place_order still
-- validate the code and the one-offer best-offer rule still decides. Only a coded offer can auto-apply.
-- Below: the newest admin_save_promotion and offer_json (20261030000000_offers.sql, 20261030000000_offers.sql) plus auto_apply.
alter table public.promotions
  add column auto_apply boolean not null default false,
  add constraint promotions_auto_apply_check check (not auto_apply or code is not null);

-- The customer's offer JSON (available_offers, offers_for_product, apply_referral_code) says it.
create or replace function private.offer_json(p public.promotions) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object('id', p.id, 'title', p.title, 'description', p.description, 'code', p.code, 'kind', p.kind,
    'value', p.value, 'max_discount_paise', p.max_discount_paise, 'min_subtotal_paise', p.min_subtotal_paise,
    'starts_at', p.starts_at, 'ends_at', p.ends_at, 'applies_to', p.applies_to, 'automatic', p.code is null,
    'online_only', p.online_only, 'first_order_only', p.first_order_only, 'auto_apply', p.auto_apply)
$$;

-- admin_save_promotion saves it like the other columns (grants survive create or replace).
create or replace function public.admin_save_promotion(p json) returns uuid
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
      is_active, show_banner, auto_apply)
    = (v_row.title, v_row.description, v_row.code, v_row.kind, v_row.value, v_row.max_discount_paise,
      v_row.min_subtotal_paise, v_row.applies_to, v_row.starts_at, v_row.ends_at, v_row.usage_limit,
      v_row.per_user_limit, v_row.first_order_only, v_row.online_only, v_row.is_public, v_row.user_id,
      v_row.is_active, v_row.show_banner, v_row.auto_apply)
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
