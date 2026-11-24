-- =====================================================================
-- berrah.app — who opened which lesson PDF (per student)
-- Run once in Supabase → SQL Editor (project exouvznkkgptvgqanawf).
-- Safe to run again.
-- =====================================================================

-- 1) One row per student per lesson (first/last open + number of opens)
create table if not exists public.lesson_views (
  id            bigserial primary key,
  course_id     uuid        not null,
  auth_user_id  uuid        not null default auth.uid(),
  first_at      timestamptz not null default now(),
  last_at       timestamptz not null default now(),
  opens         int         not null default 1,
  unique (course_id, auth_user_id)
);

alter table public.lesson_views enable row level security;

drop policy if exists lesson_views_select on public.lesson_views;
create policy lesson_views_select on public.lesson_views
  for select using (
    auth_user_id = auth.uid()
    or exists (select 1 from public.users u where u.auth_user_id = auth.uid() and u.is_teacher)
  );

-- 2) Called by a logged-in student when they open a lesson
create or replace function public.record_lesson_view(p_course_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then return jsonb_build_object('ok', false, 'reason', 'not_logged_in'); end if;
  insert into lesson_views (course_id, auth_user_id) values (p_course_id, v_uid)
  on conflict (course_id, auth_user_id)
  do update set last_at = now(), opens = lesson_views.opens + 1;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.record_lesson_view(uuid) from public, anon;
grant execute on function public.record_lesson_view(uuid) to authenticated;

-- 3) Teacher: number of distinct students per lesson
create or replace function public.get_lesson_view_counts()
returns table (course_id uuid, students bigint, opens bigint)
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from users where auth_user_id = auth.uid() and is_teacher) then
    raise exception 'teacher only';
  end if;
  return query
    select v.course_id, count(*)::bigint, coalesce(sum(v.opens),0)::bigint
    from lesson_views v group by v.course_id;
end $$;
revoke all on function public.get_lesson_view_counts() from public, anon;
grant execute on function public.get_lesson_view_counts() to authenticated;

-- 4) Teacher: the students who opened one lesson
create or replace function public.get_lesson_viewers(p_course_id uuid)
returns table (name text, lastname text, phone text, level text, first_at timestamptz, last_at timestamptz, opens int)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not exists (select 1 from users where auth_user_id = auth.uid() and is_teacher) then
    raise exception 'teacher only';
  end if;
  return query
    select u.name::text, u.lastname::text, u.phone::text, u.level::text, v.first_at, v.last_at, v.opens
    from lesson_views v join users u on u.auth_user_id = v.auth_user_id
    where v.course_id = p_course_id
    order by v.last_at desc;
end $$;
revoke all on function public.get_lesson_viewers(uuid) from public, anon;
grant execute on function public.get_lesson_viewers(uuid) to authenticated;
