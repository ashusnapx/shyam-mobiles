-- Repairs end to end: every staff step and illegal jump, quote approval (owner only, only while pending, the price
-- the customer saw), approval before work starts, cancels, the timeline, and no direct writes.
begin;
create extension if not exists pgtap with schema extensions;
select plan(65);

delete from public.repair_bookings; -- deterministic dashboard counts (rolled back at the end)
insert into auth.users (id, email) values
  ('7f000000-0000-0000-0000-000000000001', 'rf-asha@test.dev'),
  ('7f000000-0000-0000-0000-000000000002', 'rf-ravi@test.dev'),
  ('7f000000-0000-0000-0000-000000000003', 'rf-staff@test.dev');
insert into public.admins (user_id) values ('7f000000-0000-0000-0000-000000000003');

create function pg_temp.as_user(p uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
create function pg_temp.asha() returns void language sql as $$ select pg_temp.as_user('7f000000-0000-0000-0000-000000000001') $$;
create function pg_temp.ravi() returns void language sql as $$ select pg_temp.as_user('7f000000-0000-0000-0000-000000000002') $$;
create function pg_temp.staff() returns void language sql as $$ select pg_temp.as_user('7f000000-0000-0000-0000-000000000003') $$;
-- the booking's timeline as "status/quote_status ..." (read as superuser)
create function pg_temp.timeline(p uuid) returns text language sql as $$
  select string_agg(status || coalesce('/' || quote_status, ''), ' ' order by id) from public.repair_events where booking_id = p $$;

-- Booking ---------------------------------------------------------------------

-- the booking the main walk-through follows (clients can't choose ids, so it's made here)
insert into public.repair_bookings (id, user_id, device_brand, device_model, issue, preferred_date, slot, contact_phone)
values ('7fb00000-0000-0000-0000-000000000001', '7f000000-0000-0000-0000-000000000001', 'Vivo', 'Y20', 'battery',
        current_date, 'evening', '+919876543210');
select pg_temp.asha();
select lives_ok($$insert into public.repair_bookings (user_id, device_brand, device_model, issue, preferred_date, slot, contact_phone)
  values ('7f000000-0000-0000-0000-000000000001', 'Vivo', 'Y21', 'battery',
          (now() at time zone 'Asia/Kolkata')::date, 'evening', '+919876543210')$$, 'asha books a repair');
select is((select quote_status::text from public.repair_bookings where device_model = 'Y21'), 'none', 'no quote yet');
select is((select count(*)::int from public.repair_events e join public.repair_bookings b on b.id = e.booking_id
           where b.device_model = 'Y21' and e.status = 'requested'), 1, 'booking writes the first event');
select throws_ok($$update public.repair_bookings set status = 'confirmed'$$, '42501', null, 'customers cannot write bookings');
select throws_ok($$insert into public.repair_events (booking_id, status) values ('7fb00000-0000-0000-0000-000000000001', 'completed')$$,
  '42501', null, 'customers cannot write events');
select throws_ok($$insert into public.repair_bookings (user_id, device_brand, device_model, issue, preferred_date, slot, contact_phone, quote_status)
  values ('7f000000-0000-0000-0000-000000000001', 'Vivo', 'Y20', 'battery', current_date, 'evening', '+919876543210', 'approved')$$,
  '42501', null, 'customers cannot pick a quote status');
select throws_ok($$select public.admin_update_repair('7fb00000-0000-0000-0000-000000000001', 'confirmed')$$, 'P0001', 'FORBIDDEN', 'customers cannot move a booking');
select throws_ok($$select public.admin_set_repair_quote('7fb00000-0000-0000-0000-000000000001', 0, null, true)$$, 'P0001', 'FORBIDDEN', 'customers cannot quote');
select pg_temp.ravi();
select is((select count(*)::int from public.repair_events), 0, 'ravi cannot read asha''s timeline');
select pg_temp.asha();
select is((select count(*)::int from public.repair_events), 2, 'asha reads her timelines');

-- Staff steps -------------------------------------------------------------------

select pg_temp.staff();
select throws_ok($$update public.repair_bookings set status = 'completed'$$, '42501', null, 'staff cannot write bookings directly either');
select throws_ok($$select public.admin_update_repair('7fb00000-0000-0000-0000-000000000001', 'in_progress')$$, 'P0001', 'INVALID_TRANSITION', 'requested -> in_progress refused');
select throws_ok($$select public.admin_update_repair('7fb00000-0000-0000-0000-000000000001', 'ready')$$, 'P0001', 'INVALID_TRANSITION', 'requested -> ready refused');
select throws_ok($$select public.admin_update_repair('7fb00000-0000-0000-0000-000000000001', 'completed')$$, 'P0001', 'INVALID_TRANSITION', 'requested -> completed refused');
select throws_ok($$select public.admin_update_repair(gen_random_uuid(), 'confirmed')$$, 'P0001', 'NOT_FOUND', 'unknown booking');
select lives_ok($$select public.admin_update_repair('7fb00000-0000-0000-0000-000000000001', 'confirmed', 'See you at 5 pm.')$$, 'requested -> confirmed');
select is((select note from public.repair_events where booking_id = '7fb00000-0000-0000-0000-000000000001' order by id desc limit 1),
  'See you at 5 pm.', 'the note goes into the event');
select throws_ok($$select public.admin_update_repair('7fb00000-0000-0000-0000-000000000001', 'in_progress')$$, 'P0001', 'QUOTE_NOT_APPROVED', 'no work without a quote');
select throws_ok($$select public.admin_update_repair('7fb00000-0000-0000-0000-000000000001', 'ready')$$, 'P0001', 'INVALID_TRANSITION', 'confirmed -> ready refused');
select throws_ok($$select public.admin_update_repair('7fb00000-0000-0000-0000-000000000001', 'completed')$$, 'P0001', 'INVALID_TRANSITION', 'confirmed -> completed refused');
select throws_ok($$select public.admin_update_repair('7fb00000-0000-0000-0000-000000000001', 'requested')$$, 'P0001', 'INVALID_TRANSITION', 'confirmed -> requested refused');
select throws_ok($$select public.admin_set_repair_quote('7fb00000-0000-0000-0000-000000000001', -1)$$, 'P0001', 'BAD_REQUEST', 'negative quote refused');
select throws_ok($$select public.admin_set_repair_quote('7fb00000-0000-0000-0000-000000000001', null)$$, 'P0001', 'BAD_REQUEST', 'missing quote refused');
select lives_ok($$select public.admin_set_repair_quote('7fb00000-0000-0000-0000-000000000001', 20000, 'Battery and labour')$$, 'staff quotes ₹200');
select is((select quote_status::text || ' ' || quote_paise from public.repair_bookings where id = '7fb00000-0000-0000-0000-000000000001'),
  'pending 20000', 'the quote waits for the customer');
select is(public.admin_dashboard() ->> 'repairs_awaiting_approval', '1', 'dashboard counts it');
select throws_ok($$select public.admin_update_repair('7fb00000-0000-0000-0000-000000000001', 'in_progress')$$, 'P0001', 'QUOTE_NOT_APPROVED', 'no work while the quote is pending');

-- The customer answers ---------------------------------------------------------------

select pg_temp.ravi();
select throws_ok($$select public.approve_repair_quote('7fb00000-0000-0000-0000-000000000001', 20000)$$, 'P0001', 'NOT_FOUND', 'ravi cannot approve asha''s quote');
select throws_ok($$select public.decline_repair_quote('7fb00000-0000-0000-0000-000000000001')$$, 'P0001', 'NOT_FOUND', 'ravi cannot decline asha''s quote');
select pg_temp.asha();
select throws_ok($$select public.approve_repair_quote('7fb00000-0000-0000-0000-000000000001', 15000)$$, 'P0001', 'QUOTE_CHANGED', 'approving a price she did not see is refused');
select lives_ok($$select public.decline_repair_quote('7fb00000-0000-0000-0000-000000000001', ' Too costly ')$$, 'asha declines');
select is((select quote_status::text from public.repair_bookings where id = '7fb00000-0000-0000-0000-000000000001'), 'declined', 'quote declined');
select is((select note from public.repair_events where booking_id = '7fb00000-0000-0000-0000-000000000001' order by id desc limit 1),
  'Too costly', 'her reason is on the timeline');
select throws_ok($$select public.approve_repair_quote('7fb00000-0000-0000-0000-000000000001', 20000)$$, 'P0001', 'INVALID_TRANSITION', 'no approving a declined quote');
select throws_ok($$select public.decline_repair_quote('7fb00000-0000-0000-0000-000000000001')$$, 'P0001', 'INVALID_TRANSITION', 'no declining twice');
select pg_temp.staff();
select throws_ok($$select public.admin_update_repair('7fb00000-0000-0000-0000-000000000001', 'in_progress')$$, 'P0001', 'QUOTE_NOT_APPROVED', 'no work on a declined quote');
select lives_ok($$select public.admin_set_repair_quote('7fb00000-0000-0000-0000-000000000001', 18000)$$, 'staff quotes again');
select pg_temp.asha();
select lives_ok($$select public.approve_repair_quote('7fb00000-0000-0000-0000-000000000001', 18000)$$, 'asha approves the new price');
select ok((select quote_status = 'approved' and quote_decided_at is not null from public.repair_bookings
           where id = '7fb00000-0000-0000-0000-000000000001'), 'quote approved, with the time');

-- Work ---------------------------------------------------------------------------------

select pg_temp.staff();
select lives_ok($$select public.admin_update_repair('7fb00000-0000-0000-0000-000000000001', 'in_progress')$$, 'confirmed -> in_progress once approved');
select pg_temp.asha();
select throws_ok($$select public.cancel_repair('7fb00000-0000-0000-0000-000000000001')$$, 'P0001', 'INVALID_TRANSITION', 'customers cannot cancel once work starts');
select pg_temp.staff();
select throws_ok($$select public.admin_update_repair('7fb00000-0000-0000-0000-000000000001', 'completed')$$, 'P0001', 'INVALID_TRANSITION', 'in_progress -> completed refused');
select lives_ok($$select public.admin_set_repair_quote('7fb00000-0000-0000-0000-000000000001', 25000, 'The charging port is broken too')$$, 'staff changes the quote mid-repair');
select throws_ok($$select public.admin_update_repair('7fb00000-0000-0000-0000-000000000001', 'ready')$$, 'P0001', 'QUOTE_NOT_APPROVED', 'not ready until the new price is approved');
select lives_ok($$select public.admin_set_repair_quote('7fb00000-0000-0000-0000-000000000001', 25000, null, true)$$, 'she agrees on the phone; staff record it');
select is((select note from public.repair_events where booking_id = '7fb00000-0000-0000-0000-000000000001' order by id desc limit 1),
  'Agreed with the store.', 'the timeline says how it was agreed');
select lives_ok($$select public.admin_update_repair('7fb00000-0000-0000-0000-000000000001', 'ready')$$, 'in_progress -> ready');
select throws_ok($$select public.admin_set_repair_quote('7fb00000-0000-0000-0000-000000000001', 30000)$$, 'P0001', 'INVALID_TRANSITION', 'no new quote once ready');
select throws_ok($$select public.admin_update_repair('7fb00000-0000-0000-0000-000000000001', 'in_progress')$$, 'P0001', 'INVALID_TRANSITION', 'ready -> in_progress refused');
select lives_ok($$select public.admin_update_repair('7fb00000-0000-0000-0000-000000000001', 'completed')$$, 'ready -> completed');
select lives_ok($$select public.admin_update_repair('7fb00000-0000-0000-0000-000000000001', 'completed', '3 months warranty on the battery.')$$, 'a note after completion');
select lives_ok($$select public.admin_update_repair('7fb00000-0000-0000-0000-000000000001', 'completed')$$, 'same status, no note: nothing to do');
select throws_ok($$select public.admin_update_repair('7fb00000-0000-0000-0000-000000000001', 'cancelled')$$, 'P0001', 'INVALID_TRANSITION', 'completed -> cancelled refused');
reset role;
select is(pg_temp.timeline('7fb00000-0000-0000-0000-000000000001'),
  'requested confirmed confirmed/pending confirmed/declined confirmed/pending confirmed/approved in_progress '
  'in_progress/pending in_progress/approved ready completed completed', 'every step is on the timeline');

-- Cancels ------------------------------------------------------------------------------

insert into public.repair_bookings (id, user_id, device_brand, device_model, issue, preferred_date, slot, contact_phone) values
  ('7fb00000-0000-0000-0000-000000000002', '7f000000-0000-0000-0000-000000000001', 'Oppo', 'A5', 'screen', current_date, 'morning', '+919876543210'),
  ('7fb00000-0000-0000-0000-000000000003', '7f000000-0000-0000-0000-000000000001', 'Oppo', 'A6', 'screen', current_date, 'morning', '+919876543210'),
  ('7fb00000-0000-0000-0000-000000000004', '7f000000-0000-0000-0000-000000000002', 'Oppo', 'A7', 'screen', current_date, 'morning', '+919876543211');
select pg_temp.staff();
select lives_ok($$select public.admin_set_repair_quote('7fb00000-0000-0000-0000-000000000002', 90000)$$, 'a quote before confirming');
select pg_temp.asha();
select lives_ok($$select public.cancel_repair('7fb00000-0000-0000-0000-000000000002')$$, 'asha cancels with a quote pending');
select throws_ok($$select public.approve_repair_quote('7fb00000-0000-0000-0000-000000000002', 90000)$$, 'P0001', 'INVALID_TRANSITION', 'no approving a cancelled booking');
select pg_temp.staff();
select is(public.admin_dashboard() ->> 'repairs_awaiting_approval', '0', 'a cancelled booking is not waiting for anyone');
select lives_ok($$select public.admin_update_repair('7fb00000-0000-0000-0000-000000000003', 'cancelled', 'Cancelled by the store: part not available')$$, 'staff cancel with a reason');
select lives_ok($$select public.admin_update_repair('7fb00000-0000-0000-0000-000000000004', 'cancelled')$$, 'staff cancel without one');
reset role;
select is((select string_agg(note, ' | ' order by booking_id) from public.repair_events where status = 'cancelled'),
  'Cancelled by you. | Cancelled by the store: part not available | Cancelled by the store.', 'cancel notes');

-- Walk-ins and anon --------------------------------------------------------------------

select pg_temp.staff();
select lives_ok($$insert into public.repair_bookings (user_id, device_brand, device_model, issue, preferred_date, slot, contact_phone, status, quote_paise)
  values (null, 'Nokia', '105', 'charging', current_date, 'morning', '+919876543212', 'confirmed', 5000)$$,
  'staff book a walk-in with a quote');
reset role;
select is(pg_temp.timeline((select id from public.repair_bookings where device_model = '105')), 'confirmed confirmed/pending',
  'its quote waits like any other');
select pg_temp.staff();
select throws_ok($$select public.admin_update_repair((select id from public.repair_bookings where device_model = '105'), 'in_progress')$$,
  'P0001', 'QUOTE_NOT_APPROVED', 'even a walk-in needs the yes first');
set local role anon;
select throws_ok($$select public.approve_repair_quote('7fb00000-0000-0000-0000-000000000001', 0)$$, '42501', null, 'anon cannot approve');

reset role;
select * from finish();
rollback;
