-- Sign-in is a phone number and a password now (docs/SPEC.md "Auth"), with no code to wait for: phone confirmations
-- are off (config.toml) and nothing is sent by SMS. Forgotten passwords are reset by the shop (reset-password).

-- Access token hook: any account with a phone number may use its password. Email + password stays limited to the
-- domains in private.password_sign_in_domains (the local dev logins and the client-demo accounts), so a stranger's
-- self-registered email account still never gets a session. Sessions from the old code sign-in pass unchanged.
create or replace function private.custom_access_token_hook(event jsonb) returns jsonb
language sql stable set search_path = '' as $$
  select case
    when event -> 'claims' -> 'amr' @> '[{"method": "password"}]' and not exists (
      select 1 from auth.users u
      where u.id = (event ->> 'user_id')::uuid
        and (coalesce(u.phone, '') <> ''
             or exists (select 1 from private.password_sign_in_domains d where d.domain = split_part(u.email, '@', 2))))
    then jsonb_build_object('error', jsonb_build_object('http_code', 403, 'message', 'Sign in with your phone number and password.'))
    else event
  end;
$$;

-- A temporary password from the shop comes with app_metadata.must_change_password (the app then asks for the
-- customer's own). The customer's next password change clears it. reset-password sets the password and the flag in
-- two separate updates, so a password change that leaves app_metadata as it was is always someone choosing a new one.
create function private.clear_must_change_password() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.encrypted_password is distinct from old.encrypted_password
     and new.raw_app_meta_data is not distinct from old.raw_app_meta_data then
    new.raw_app_meta_data := new.raw_app_meta_data - 'must_change_password';
  end if;
  return new;
end $$;

create trigger clear_must_change_password before update of encrypted_password on auth.users
for each row when (old.raw_app_meta_data ? 'must_change_password')
execute function private.clear_must_change_password();

revoke execute on function private.clear_must_change_password() from public, anon, authenticated;

-- reset-password (Edge Function, secret key) looks up the account a number signs in with, so staff see whose
-- password they are about to reset. Auth stores phones without the '+'. Null when no account uses the number.
create function public.account_by_phone(p_phone text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'user_id', u.id,
    'full_name', p.full_name,
    'staff', exists (select 1 from public.admins a where a.user_id = u.id),
    'created_at', u.created_at)
  from auth.users u
  left join public.profiles p on p.id = u.id
  where p_phone ~ '^\+91[6-9][0-9]{9}$' and u.phone = ltrim(p_phone, '+')
$$;

revoke execute on function public.account_by_phone(text) from public, anon, authenticated;
grant execute on function public.account_by_phone(text) to service_role;
