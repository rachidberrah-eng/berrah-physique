-- =====================================================================
-- berrah.app — login by phone still works after a student adds a real email
-- Run once in Supabase → SQL Editor (project exouvznkkgptvgqanawf).
-- Safe to run again.
--
-- A student's Supabase Auth account starts with the address {phone}@berrah-physique.netlify.app.
-- When they add their own email (to recover a forgotten password), the Auth address changes,
-- so login-by-phone must find it. This function returns that address ONLY when the
-- password is correct, so it never reveals anyone's email.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

create or replace function public.resolve_login_email(p_phone text, p_password text)
returns text
language plpgsql security definer set search_path = public, extensions, auth as $$
declare
  v_email text;
  v_hash  text;
begin
  select a.email, a.encrypted_password into v_email, v_hash
  from public.users u join auth.users a on a.id = u.auth_user_id
  where u.phone = p_phone
  limit 1;
  if v_email is null or v_hash is null then return null; end if;
  if extensions.crypt(p_password, v_hash) = v_hash then return v_email; end if;
  return null;
end $$;
revoke all on function public.resolve_login_email(text, text) from public;
grant execute on function public.resolve_login_email(text, text) to anon, authenticated;

-- The student's real email (null while they still use the phone-only address)
create or replace function public.get_my_email()
returns text language sql security definer set search_path = public, auth as $$
  select case when a.email like '%@berrah-physique.netlify.app' then null else a.email end
  from auth.users a where a.id = auth.uid();
$$;
revoke all on function public.get_my_email() from public, anon;
grant execute on function public.get_my_email() to authenticated;
