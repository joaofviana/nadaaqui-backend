-- NadaAqui — sessão / feed / kudos / ranking (Strava-lite)

create type public.post_kind as enum ('text', 'photo', 'check_in', 'review', 'session');

alter table public.posts
  add column if not exists kind public.post_kind not null default 'text',
  add column if not exists stars int check (stars is null or stars between 1 and 5),
  add column if not exists duration_seconds int check (duration_seconds is null or duration_seconds >= 0),
  add column if not exists meters int check (meters is null or meters >= 0),
  add column if not exists check_in_id uuid references public.check_ins (id) on delete set null;

alter table public.posts
  drop constraint if exists posts_body_check;

alter table public.posts
  add constraint posts_body_check check (char_length(body) <= 500);

create table if not exists public.post_kudos (
  post_id uuid not null references public.posts (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table if not exists public.swim_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  place_id uuid not null references public.places (id) on delete cascade,
  check_in_id uuid references public.check_ins (id) on delete set null,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  duration_seconds int not null check (duration_seconds >= 0),
  meters int check (meters is null or meters >= 0),
  created_at timestamptz not null default now()
);

create index if not exists swim_sessions_user_ended_idx
  on public.swim_sessions (user_id, ended_at desc);
create index if not exists swim_sessions_place_ended_idx
  on public.swim_sessions (place_id, ended_at desc);
create index if not exists posts_created_idx on public.posts (created_at desc);

alter table public.post_kudos enable row level security;
alter table public.swim_sessions enable row level security;

create policy post_kudos_select on public.post_kudos
  for select to anon, authenticated using (true);
create policy post_kudos_own on public.post_kudos
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy swim_sessions_select_own on public.swim_sessions
  for select to authenticated
  using (user_id = auth.uid());
create policy swim_sessions_insert_own on public.swim_sessions
  for insert to authenticated
  with check (user_id = auth.uid());

-- Encerrar nado: checkout + sessão + post no feed
create or replace function public.finish_swim(
  p_check_in_id uuid,
  p_meters int default null,
  p_body text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_ci public.check_ins%rowtype;
  v_place public.places%rowtype;
  v_profile public.profiles%rowtype;
  v_session public.swim_sessions%rowtype;
  v_post public.posts%rowtype;
  v_dur int;
  v_body text;
begin
  if v_uid is null then
    raise exception 'UNAUTHORIZED' using errcode = 'P0001';
  end if;

  update public.check_ins
  set status = 'ended', ended_at = now()
  where id = p_check_in_id and user_id = v_uid and status = 'active'
  returning * into v_ci;

  if not found then
    raise exception 'NOT_FOUND' using errcode = 'P0001';
  end if;

  select * into v_place from public.places where id = v_ci.place_id;
  select * into v_profile from public.profiles where id = v_uid;

  v_dur := greatest(0, extract(epoch from (v_ci.ended_at - v_ci.started_at))::int);

  insert into public.swim_sessions (
    user_id, place_id, check_in_id, started_at, ended_at, duration_seconds, meters
  ) values (
    v_uid, v_ci.place_id, v_ci.id, v_ci.started_at, v_ci.ended_at, v_dur, p_meters
  ) returning * into v_session;

  v_body := nullif(trim(coalesce(p_body, '')), '');
  if v_body is null then
    v_body := format(
      'Nadou %s min%s em %s',
      greatest(1, v_dur / 60),
      case when p_meters is not null then format(' · %s m', p_meters) else '' end,
      v_place.name
    );
  end if;

  insert into public.posts (
    user_id, place_id, body, kind, duration_seconds, meters, check_in_id, city_slug
  ) values (
    v_uid, v_ci.place_id, left(v_body, 500), 'session', v_dur, p_meters, v_ci.id, v_place.city_slug
  ) returning * into v_post;

  return jsonb_build_object(
    'session', jsonb_build_object(
      'id', v_session.id,
      'placeId', v_session.place_id,
      'placeName', v_place.name,
      'startedAt', v_session.started_at,
      'endedAt', v_session.ended_at,
      'durationSeconds', v_session.duration_seconds,
      'meters', v_session.meters
    ),
    'post', jsonb_build_object(
      'id', v_post.id,
      'kind', v_post.kind,
      'body', v_post.body,
      'placeId', v_post.place_id,
      'placeName', v_place.name,
      'durationSeconds', v_post.duration_seconds,
      'meters', v_post.meters,
      'createdAt', v_post.created_at,
      'likes', 0,
      'liked', false,
      'author', jsonb_build_object(
        'id', v_profile.id,
        'displayName', v_profile.display_name,
        'avatarUrl', v_profile.avatar_url
      )
    ),
    'checkIn', jsonb_build_object(
      'id', v_ci.id,
      'status', v_ci.status,
      'endedAt', v_ci.ended_at
    )
  );
end;
$$;

grant execute on function public.finish_swim(uuid, int, text) to authenticated;

create or replace function public.create_feed_post(
  p_body text,
  p_kind public.post_kind default 'text',
  p_place_id uuid default null,
  p_stars int default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_city text;
  v_place public.places%rowtype;
  v_profile public.profiles%rowtype;
  v_post public.posts%rowtype;
  v_kind public.post_kind := coalesce(p_kind, 'text');
begin
  if v_uid is null then
    raise exception 'UNAUTHORIZED' using errcode = 'P0001';
  end if;
  if p_body is null or length(trim(p_body)) = 0 then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001';
  end if;
  if v_kind = 'review' and (p_stars is null or p_stars < 1) then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001';
  end if;

  select * into v_profile from public.profiles where id = v_uid;
  select city_slug into v_city from public.app_config where id = 1;

  if p_place_id is not null then
    select * into v_place from public.places where id = p_place_id and is_published;
    if found then
      v_city := v_place.city_slug;
    end if;
  end if;

  insert into public.posts (user_id, place_id, body, kind, stars, city_slug)
  values (v_uid, p_place_id, left(trim(p_body), 500), v_kind, p_stars, v_city)
  returning * into v_post;

  if v_kind = 'review' and p_place_id is not null then
    update public.places pl
    set rating_count = sub.n,
        rating_avg = sub.avg_stars
    from (
      select count(*)::int as n, avg(stars)::numeric(3,2) as avg_stars
      from public.posts
      where place_id = p_place_id and kind = 'review' and stars is not null
    ) sub
    where pl.id = p_place_id;
  end if;

  return jsonb_build_object(
    'id', v_post.id,
    'kind', v_post.kind,
    'body', v_post.body,
    'stars', v_post.stars,
    'placeId', v_post.place_id,
    'placeName', v_place.name,
    'createdAt', v_post.created_at,
    'likes', 0,
    'liked', false,
    'author', jsonb_build_object(
      'id', v_profile.id,
      'displayName', v_profile.display_name,
      'avatarUrl', v_profile.avatar_url
    )
  );
end;
$$;

grant execute on function public.create_feed_post(text, public.post_kind, uuid, int) to authenticated;

create or replace function public.toggle_kudo(p_post_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_liked boolean;
  v_count int;
begin
  if v_uid is null then
    raise exception 'UNAUTHORIZED' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.posts where id = p_post_id) then
    raise exception 'NOT_FOUND' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.post_kudos where post_id = p_post_id and user_id = v_uid
  ) then
    delete from public.post_kudos where post_id = p_post_id and user_id = v_uid;
    v_liked := false;
  else
    insert into public.post_kudos (post_id, user_id) values (p_post_id, v_uid);
    v_liked := true;
  end if;

  select count(*) into v_count from public.post_kudos where post_id = p_post_id;
  return jsonb_build_object('postId', p_post_id, 'liked', v_liked, 'likes', v_count);
end;
$$;

grant execute on function public.toggle_kudo(uuid) to authenticated;

create or replace function public.list_feed(
  p_limit int default 30,
  p_offset int default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_items jsonb;
begin
  if p_limit is null or p_limit < 1 then p_limit := 30; end if;
  if p_limit > 50 then p_limit := 50; end if;
  if p_offset is null or p_offset < 0 then p_offset := 0; end if;

  select coalesce(jsonb_agg(item order by created_at desc), '[]'::jsonb)
  into v_items
  from (
    select jsonb_build_object(
      'id', po.id,
      'kind', po.kind,
      'body', po.body,
      'stars', po.stars,
      'placeId', po.place_id,
      'placeName', pl.name,
      'durationSeconds', po.duration_seconds,
      'meters', po.meters,
      'createdAt', po.created_at,
      'likes', (select count(*) from public.post_kudos k where k.post_id = po.id),
      'liked', case
        when v_uid is null then false
        else exists (
          select 1 from public.post_kudos k
          where k.post_id = po.id and k.user_id = v_uid
        )
      end,
      'author', jsonb_build_object(
        'id', pr.id,
        'displayName', pr.display_name,
        'avatarUrl', pr.avatar_url
      )
    ) as item,
    po.created_at
    from public.posts po
    join public.profiles pr on pr.id = po.user_id
    left join public.places pl on pl.id = po.place_id
    order by po.created_at desc
    limit p_limit offset p_offset
  ) q;

  return jsonb_build_object('items', v_items);
end;
$$;

grant execute on function public.list_feed(int, int) to anon, authenticated;

create or replace function public.list_my_sessions(
  p_limit int default 30,
  p_offset int default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_items jsonb;
  v_stats jsonb;
begin
  if v_uid is null then
    raise exception 'UNAUTHORIZED' using errcode = 'P0001';
  end if;

  select coalesce(jsonb_agg(item order by ended_at desc), '[]'::jsonb)
  into v_items
  from (
    select jsonb_build_object(
      'id', s.id,
      'placeId', s.place_id,
      'placeName', pl.name,
      'startedAt', s.started_at,
      'endedAt', s.ended_at,
      'durationSeconds', s.duration_seconds,
      'meters', s.meters
    ) as item,
    s.ended_at
    from public.swim_sessions s
    join public.places pl on pl.id = s.place_id
    where s.user_id = v_uid
    order by s.ended_at desc
    limit p_limit offset p_offset
  ) q;

  select jsonb_build_object(
    'sessions', count(*),
    'minutes', coalesce(sum(duration_seconds) / 60, 0),
    'meters', coalesce(sum(meters), 0),
    'places', count(distinct place_id)
  )
  into v_stats
  from public.swim_sessions
  where user_id = v_uid;

  return jsonb_build_object('items', v_items, 'stats', v_stats);
end;
$$;

grant execute on function public.list_my_sessions(int, int) to authenticated;

create or replace function public.place_board(p_place_id uuid, p_limit int default 10)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_items jsonb;
begin
  if not exists (select 1 from public.places where id = p_place_id and is_published) then
    return null;
  end if;

  select coalesce(jsonb_agg(row_order), '[]'::jsonb)
  into v_items
  from (
    select jsonb_build_object(
      'userId', s.user_id,
      'displayName', pr.display_name,
      'sessions', s.n,
      'minutes', s.mins,
      'you', s.user_id = auth.uid()
    ) as row_order
    from (
      select user_id,
             count(*)::int as n,
             (sum(duration_seconds) / 60)::int as mins
      from public.swim_sessions
      where place_id = p_place_id
        and ended_at >= date_trunc('month', now())
      group by user_id
    ) s
    join public.profiles pr on pr.id = s.user_id
    order by s.mins desc, s.n desc
    limit coalesce(p_limit, 10)
  ) q;

  return jsonb_build_object('placeId', p_place_id, 'items', v_items);
end;
$$;

grant execute on function public.place_board(uuid, int) to anon, authenticated;

create or replace function public.place_hourly_heat(p_place_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_hours jsonb;
begin
  if not exists (select 1 from public.places where id = p_place_id and is_published) then
    return null;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('hour', h, 'count', c) order by h), '[]'::jsonb)
  into v_hours
  from (
    select extract(hour from started_at)::int as h, count(*)::int as c
    from public.check_ins
    where place_id = p_place_id
      and started_at >= now() - interval '28 days'
    group by 1
  ) t;

  return jsonb_build_object('placeId', p_place_id, 'hours', v_hours);
end;
$$;

grant execute on function public.place_hourly_heat(uuid) to anon, authenticated;
