-- =====================================================================
-- berrah.app — Zoom attendance (Phase 1)
-- Run once in Supabase → SQL Editor (project exouvznkkgptvgqanawf).
-- Safe to run again: everything is "if not exists" / "or replace".
-- =====================================================================

-- 1) One row per student per live session (first join wins)
create table if not exists public.live_attendance (
  id            bigserial primary key,
  session_id    text        not null,
  auth_user_id  uuid        not null default auth.uid(),
  joined_at     timestamptz not null default now(),
  status        text        not null check (status in ('present','late')),
  late_minutes  int         not null default 0,
  unique (session_id, auth_user_id)
);

alter table public.live_attendance enable row level security;

-- Students see only their own rows; the teacher sees everything.
drop policy if exists live_attendance_select on public.live_attendance;
create policy live_attendance_select on public.live_attendance
  for select using (
    auth_user_id = auth.uid()
    or exists (select 1 from public.users u where u.auth_user_id = auth.uid() and u.is_teacher)
  );
-- No direct insert/update/delete: writes go through the function below.

-- Helper: does a session target this student's level/stream?
create or replace function public._live_session_targets(s_level text, s_stream text, u_level text, u_stream text)
returns boolean language sql immutable as $$
  select (s_level is null or s_level = 'all' or s_level = u_level)
     and (s_stream is null or s_stream = '' or s_stream = 'all' or u_stream is null or s_stream = u_stream)
$$;

-- 2) Called when a logged-in student presses "join" on a live session.
--    Present if they join up to 5 min after the start, otherwise late.
create or replace function public.record_live_attendance(p_session_id text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_start timestamptz;
  v_late int;
  v_status text;
begin
  if v_uid is null then return jsonb_build_object('ok', false, 'reason', 'not_logged_in'); end if;

  select scheduled_at into v_start from live_sessions where id::text = p_session_id;
  if v_start is null then return jsonb_build_object('ok', false, 'reason', 'no_session'); end if;

  -- Only count joins inside the window the link is open (30 min before → 2 h after)
  if now() < v_start - interval '30 minutes' or now() > v_start + interval '2 hours' then
    return jsonb_build_object('ok', false, 'reason', 'outside_window');
  end if;

  v_late := greatest(0, floor(extract(epoch from (now() - v_start)) / 60)::int);
  v_status := case when v_late <= 5 then 'present' else 'late' end;

  insert into live_attendance (session_id, auth_user_id, status, late_minutes)
  values (p_session_id, v_uid, v_status, case when v_status = 'late' then v_late else 0 end)
  on conflict (session_id, auth_user_id) do nothing;

  return jsonb_build_object('ok', true, 'status', v_status, 'late_minutes', v_late);
end $$;

-- 3) A student's own attendance: every past session of their level since they joined
create or replace function public.get_my_attendance()
returns table (session_id text, title text, scheduled_at timestamptz, status text, late_minutes int)
language sql security definer set search_path = public as $$
  with me as (
    select level, stream, created_at from users where auth_user_id = auth.uid() limit 1
  )
  select s.id::text, s.title, s.scheduled_at,
         coalesce(a.status, 'absent') as status,
         coalesce(a.late_minutes, 0)  as late_minutes
  from live_sessions s
  cross join me
  left join live_attendance a on a.session_id = s.id::text and a.auth_user_id = auth.uid()
  where s.scheduled_at < now() - interval '15 minutes'
    and s.scheduled_at >= coalesce(me.created_at, now() - interval '365 days') - interval '1 day'
    and _live_session_targets(s.level, s.stream, me.level, me.stream)
  order by s.scheduled_at desc
  limit 200
$$;

-- 4) Teacher: the full list for one session (present / late / absent)
create or replace function public.get_session_attendance(p_session_id text)
returns table (name text, phone text, status text, late_minutes int, joined_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare s record;
begin
  if not exists (select 1 from users where auth_user_id = auth.uid() and is_teacher) then
    raise exception 'teacher only';
  end if;
  select * into s from live_sessions where id::text = p_session_id;
  if s is null then return; end if;

  return query
  select trim(coalesce(u.name,'') || ' ' || coalesce(u.lastname,'')) as name,
         u.phone,
         coalesce(a.status, 'absent'),
         coalesce(a.late_minutes, 0),
         a.joined_at
  from users u
  left join live_attendance a on a.auth_user_id = u.auth_user_id and a.session_id = p_session_id
  where not coalesce(u.is_teacher, false)
    and (a.id is not null
         or (_live_session_targets(s.level, s.stream, u.level, u.stream)
             and coalesce(u.has_active_subscription, false)))
  order by case coalesce(a.status,'absent') when 'present' then 0 when 'late' then 1 else 2 end, name;
end $$;

revoke all on function public.record_live_attendance(text) from public;
revoke all on function public.get_my_attendance() from public;
revoke all on function public.get_session_attendance(text) from public;
grant execute on function public.record_live_attendance(text) to authenticated;
grant execute on function public.get_my_attendance() to authenticated;
grant execute on function public.get_session_attendance(text) to authenticated;
