-- Google sign-in support for berrah.app
-- 1) The phone-signup trigger (handle_new_user) only fires when the new auth user
--    carries a phone in its metadata, so Google sign-ups never fail on a missing phone.
do $$
declare t record; newdef text;
begin
  for t in
    select tgname, pg_get_triggerdef(oid) as def
    from pg_trigger
    where tgrelid = 'auth.users'::regclass
      and tgfoid = 'public.handle_new_user'::regproc
      and not tgisinternal
  loop
    if t.def !~* '\mWHEN\M' then
      newdef := replace(t.def, 'FOR EACH ROW', 'FOR EACH ROW WHEN (new.raw_user_meta_data ? ''phone'')');
      execute format('drop trigger %I on auth.users', t.tgname);
      execute newdef;
    end if;
  end loop;
end $$;

-- 2) After the first Google login the student completes his profile once.
create or replace function public.complete_oauth_profile(
  p_name text, p_lastname text, p_phone text, p_level text, p_wilaya text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid := auth.uid();
begin
  if uid is null then return json_build_object('ok', false, 'error', 'not_logged_in'); end if;
  if coalesce(trim(p_name),'') = '' or coalesce(trim(p_lastname),'') = ''
     or coalesce(p_phone,'') !~ '^[0-9]{8,15}$'
     or p_level not in ('1as','2as','3as') then
    return json_build_object('ok', false, 'error', 'invalid');
  end if;
  if exists (select 1 from public.users where phone = p_phone and auth_user_id is distinct from uid) then
    return json_build_object('ok', false, 'error', 'phone_taken');
  end if;
  if exists (select 1 from public.users where auth_user_id = uid) then
    update public.users
       set name = trim(p_name), lastname = trim(p_lastname), phone = p_phone,
           level = p_level, wilaya = p_wilaya, updated_at = now()
     where auth_user_id = uid;
  else
    insert into public.users (auth_user_id, name, lastname, phone, level, wilaya, is_teacher)
    values (uid, trim(p_name), trim(p_lastname), p_phone, p_level, p_wilaya, false);
  end if;
  return json_build_object('ok', true);
end $$;

revoke all on function public.complete_oauth_profile(text,text,text,text,text) from public, anon;
grant execute on function public.complete_oauth_profile(text,text,text,text,text) to authenticated;
