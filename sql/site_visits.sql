-- Daily visitor counter for berrah.app
-- One row per (day, anonymous visitor, page). No IP, no personal data.
-- Run once in the Supabase SQL editor.

create table if not exists public.site_visits (
  visit_day  date        not null default ((now() at time zone 'Africa/Algiers')::date),
  visitor_id text        not null,
  page       text        not null,
  views      integer     not null default 1,
  is_user    boolean     not null default false,
  first_at   timestamptz not null default now(),
  last_at    timestamptz not null default now(),
  primary key (visit_day, visitor_id, page)
);

create index if not exists site_visits_day_idx on public.site_visits (visit_day);

-- No direct access: everything goes through the two functions below.
alter table public.site_visits enable row level security;
revoke all on public.site_visits from anon, authenticated;

-- Called by every visitor (logged in or not)
create or replace function public.track_visit(p_visitor text, p_page text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_page text := lower(coalesce(nullif(trim(p_page), ''), 'home'));
  v_user boolean := auth.uid() is not null;
begin
  if p_visitor is null or p_visitor !~ '^[A-Za-z0-9-]{8,64}$' then
    return;
  end if;
  if v_page !~ '^[a-z0-9_-]{1,40}$' then
    v_page := 'other';
  end if;
  -- the teacher's own visits are not counted
  if v_user and exists (select 1 from users u where u.auth_user_id = auth.uid() and coalesce(u.is_teacher, false)) then
    return;
  end if;

  insert into site_visits (visitor_id, page, is_user)
  values (p_visitor, v_page, v_user)
  on conflict (visit_day, visitor_id, page) do update
    set views   = least(site_visits.views + 1, 500),
        is_user = site_visits.is_user or excluded.is_user,
        last_at = now();
end;
$$;

revoke all on function public.track_visit(text, text) from public;
grant execute on function public.track_visit(text, text) to anon, authenticated;

-- Teacher-only statistics
create or replace function public.get_visit_stats(p_days integer default 30)
returns json
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
  v_from date := ((now() at time zone 'Africa/Algiers')::date) - (v_days - 1);
  v_result json;
begin
  if not exists (select 1 from users where auth_user_id = auth.uid() and is_teacher) then
    raise exception 'not_allowed';
  end if;

  select json_build_object(
    'today', ((now() at time zone 'Africa/Algiers')::date),
    'days', coalesce((
      select json_agg(d order by d.day)
      from (
        select g.day::date as day,
               count(distinct v.visitor_id)                          as visitors,
               coalesce(sum(v.views), 0)                             as views,
               count(distinct v.visitor_id) filter (where v.is_user) as users
        from generate_series(v_from, ((now() at time zone 'Africa/Algiers')::date), interval '1 day') g(day)
        left join site_visits v on v.visit_day = g.day::date
        group by g.day
      ) d
    ), '[]'::json),
    'pages', coalesce((
      select json_agg(p order by p.visitors desc)
      from (
        select page, count(distinct visitor_id) as visitors, sum(views) as views
        from site_visits
        where visit_day >= v_from
        group by page
        order by 2 desc
        limit 8
      ) p
    ), '[]'::json),
    'period_visitors', (select count(distinct visitor_id) from site_visits where visit_day >= v_from)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_visit_stats(integer) from public;
grant execute on function public.get_visit_stats(integer) to authenticated;
