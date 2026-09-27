-- Clubes de natação + eventos (estilo Strava Clubs / GymRats community)
-- Tabelas: clubs, club_members, club_events, club_event_rsvps
-- RPCs: create_club, list_clubs, get_club, join_club, leave_club,
--        create_club_event, list_club_events, rsvp_club_event

create table if not exists public.clubs (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 3 and 80),
  description text check (description is null or char_length(description) <= 500),
  city text,
  is_public boolean not null default true,
  owner_id uuid not null references public.profiles (id) on delete cascade,
  member_count int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists clubs_owner_idx on public.clubs (owner_id);
create index if not exists clubs_public_idx on public.clubs (is_public, member_count desc);

create table if not exists public.club_members (
  club_id uuid not null references public.clubs (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'member')),
  joined_at timestamptz not null default now(),
  primary key (club_id, user_id)
);

create index if not exists club_members_user_idx on public.club_members (user_id);

create table if not exists public.club_events (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs (id) on delete cascade,
  created_by uuid not null references public.profiles (id) on delete cascade,
  title text not null check (char_length(title) between 3 and 125),
  description text check (description is null or char_length(description) <= 1000),
  event_type text not null default 'workout'
    check (event_type in ('workout', 'social', 'competition')),
  starts_at timestamptz not null,
  place_id uuid references public.places (id) on delete set null,
  place_name text,
  capacity int check (capacity is null or capacity >= 2),
  rsvp_count int not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists club_events_club_idx on public.club_events (club_id, starts_at);
create index if not exists club_events_starts_idx on public.club_events (starts_at);

create table if not exists public.club_event_rsvps (
  event_id uuid not null references public.club_events (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'going' check (status in ('going', 'maybe', 'declined')),
  created_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

alter table public.clubs enable row level security;
alter table public.club_members enable row level security;
alter table public.club_events enable row level security;
alter table public.club_event_rsvps enable row level security;

-- Leitura ampla via RPCs (security definer). Policies mínimas.
drop policy if exists clubs_select on public.clubs;
create policy clubs_select on public.clubs for select using (true);

drop policy if exists club_members_select on public.club_members;
create policy club_members_select on public.club_members for select using (true);

drop policy if exists club_events_select on public.club_events;
create policy club_events_select on public.club_events for select using (true);

drop policy if exists club_event_rsvps_select on public.club_event_rsvps;
create policy club_event_rsvps_select on public.club_event_rsvps for select using (true);

-- ─── create_club ─────────────────────────────────────────────
create or replace function public.create_club(
  p_name text,
  p_description text default null,
  p_city text default null,
  p_is_public boolean default true
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  c public.clubs%rowtype;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  if p_name is null or char_length(trim(p_name)) < 3 then
    raise exception 'name required (min 3 chars)';
  end if;

  insert into public.clubs (name, description, city, is_public, owner_id, member_count)
  values (
    trim(p_name),
    nullif(trim(coalesce(p_description, '')), ''),
    nullif(trim(coalesce(p_city, '')), ''),
    coalesce(p_is_public, true),
    uid,
    1
  )
  returning * into c;

  insert into public.club_members (club_id, user_id, role)
  values (c.id, uid, 'owner');

  return json_build_object(
    'id', c.id,
    'name', c.name,
    'description', c.description,
    'city', c.city,
    'isPublic', c.is_public,
    'memberCount', c.member_count,
    'isMember', true,
    'role', 'owner',
    'createdAt', c.created_at
  );
end;
$$;

-- ─── list_clubs ──────────────────────────────────────────────
create or replace function public.list_clubs(
  p_mine_only boolean default false,
  p_limit int default 30
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  lim int := least(greatest(coalesce(p_limit, 30), 1), 50);
begin
  return (
    select coalesce(json_agg(row_to_json(x)), '[]'::json)
    from (
      select
        c.id,
        c.name,
        c.description,
        c.city,
        c.is_public as "isPublic",
        c.member_count as "memberCount",
        (cm.user_id is not null) as "isMember",
        cm.role,
        c.created_at as "createdAt",
        (
          select json_build_object(
            'id', e.id,
            'title', e.title,
            'startsAt', e.starts_at,
            'rsvpCount', e.rsvp_count
          )
          from public.club_events e
          where e.club_id = c.id and e.starts_at >= now()
          order by e.starts_at asc
          limit 1
        ) as "nextEvent"
      from public.clubs c
      left join public.club_members cm
        on cm.club_id = c.id and cm.user_id = uid
      where
        case
          when p_mine_only then cm.user_id is not null
          else (c.is_public or cm.user_id is not null)
        end
      order by
        (cm.user_id is not null) desc,
        c.member_count desc,
        c.created_at desc
      limit lim
    ) x
  );
end;
$$;

-- ─── get_club ────────────────────────────────────────────────
create or replace function public.get_club(p_club_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  c public.clubs%rowtype;
  r text;
begin
  select * into c from public.clubs where id = p_club_id;
  if not found then
    raise exception 'club not found';
  end if;

  select role into r from public.club_members
  where club_id = p_club_id and user_id = uid;

  return json_build_object(
    'id', c.id,
    'name', c.name,
    'description', c.description,
    'city', c.city,
    'isPublic', c.is_public,
    'memberCount', c.member_count,
    'isMember', r is not null,
    'role', r,
    'createdAt', c.created_at,
    'ownerId', c.owner_id
  );
end;
$$;

-- ─── join_club / leave_club ──────────────────────────────────
create or replace function public.join_club(p_club_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  c public.clubs%rowtype;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into c from public.clubs where id = p_club_id;
  if not found then raise exception 'club not found'; end if;
  if not c.is_public then
    raise exception 'club is private';
  end if;

  insert into public.club_members (club_id, user_id, role)
  values (p_club_id, uid, 'member')
  on conflict do nothing;

  update public.clubs set member_count = (
    select count(*)::int from public.club_members where club_id = p_club_id
  ), updated_at = now()
  where id = p_club_id
  returning * into c;

  return public.get_club(p_club_id);
end;
$$;

create or replace function public.leave_club(p_club_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  r text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select role into r from public.club_members
  where club_id = p_club_id and user_id = uid;
  if r is null then raise exception 'not a member'; end if;
  if r = 'owner' then raise exception 'owner cannot leave; transfer ownership first'; end if;

  delete from public.club_members where club_id = p_club_id and user_id = uid;
  update public.clubs set member_count = (
    select count(*)::int from public.club_members where club_id = p_club_id
  ), updated_at = now()
  where id = p_club_id;

  return public.get_club(p_club_id);
end;
$$;

-- ─── create_club_event ───────────────────────────────────────
create or replace function public.create_club_event(
  p_club_id uuid,
  p_title text,
  p_starts_at timestamptz,
  p_event_type text default 'workout',
  p_description text default null,
  p_place_id uuid default null,
  p_place_name text default null,
  p_capacity int default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  r text;
  e public.club_events%rowtype;
  et text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if p_title is null or char_length(trim(p_title)) < 3 then
    raise exception 'title required';
  end if;
  if p_starts_at is null or p_starts_at < now() - interval '1 hour' then
    raise exception 'starts_at must be in the future';
  end if;

  select role into r from public.club_members
  where club_id = p_club_id and user_id = uid;
  if r is null or r not in ('owner', 'admin', 'member') then
    raise exception 'must be club member to create event';
  end if;

  et := coalesce(nullif(trim(p_event_type), ''), 'workout');
  if et not in ('workout', 'social', 'competition') then
    et := 'workout';
  end if;

  insert into public.club_events (
    club_id, created_by, title, description, event_type,
    starts_at, place_id, place_name, capacity, rsvp_count
  ) values (
    p_club_id,
    uid,
    trim(p_title),
    nullif(trim(coalesce(p_description, '')), ''),
    et,
    p_starts_at,
    p_place_id,
    nullif(trim(coalesce(p_place_name, '')), ''),
    p_capacity,
    1
  )
  returning * into e;

  -- criador já entra como going
  insert into public.club_event_rsvps (event_id, user_id, status)
  values (e.id, uid, 'going');

  return json_build_object(
    'id', e.id,
    'clubId', e.club_id,
    'title', e.title,
    'description', e.description,
    'eventType', e.event_type,
    'startsAt', e.starts_at,
    'placeId', e.place_id,
    'placeName', e.place_name,
    'capacity', e.capacity,
    'rsvpCount', e.rsvp_count,
    'myStatus', 'going'
  );
end;
$$;

-- ─── list_club_events ────────────────────────────────────────
create or replace function public.list_club_events(
  p_club_id uuid default null,
  p_upcoming_only boolean default true,
  p_limit int default 30
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  lim int := least(greatest(coalesce(p_limit, 30), 1), 50);
begin
  return (
    select coalesce(json_agg(row_to_json(x)), '[]'::json)
    from (
      select
        e.id,
        e.club_id as "clubId",
        c.name as "clubName",
        e.title,
        e.description,
        e.event_type as "eventType",
        e.starts_at as "startsAt",
        e.place_id as "placeId",
        e.place_name as "placeName",
        e.capacity,
        e.rsvp_count as "rsvpCount",
        r.status as "myStatus"
      from public.club_events e
      join public.clubs c on c.id = e.club_id
      left join public.club_event_rsvps r
        on r.event_id = e.id and r.user_id = uid
      where
        (p_club_id is null or e.club_id = p_club_id)
        and (not p_upcoming_only or e.starts_at >= now() - interval '2 hours')
      order by e.starts_at asc
      limit lim
    ) x
  );
end;
$$;

-- ─── rsvp_club_event ─────────────────────────────────────────
create or replace function public.rsvp_club_event(
  p_event_id uuid,
  p_status text default 'going'
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  e public.club_events%rowtype;
  st text;
  cnt int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into e from public.club_events where id = p_event_id;
  if not found then raise exception 'event not found'; end if;

  st := coalesce(nullif(trim(p_status), ''), 'going');
  if st not in ('going', 'maybe', 'declined') then
    st := 'going';
  end if;

  if st = 'declined' then
    delete from public.club_event_rsvps
    where event_id = p_event_id and user_id = uid;
  else
    if e.capacity is not null and st = 'going' then
      select count(*) into cnt from public.club_event_rsvps
      where event_id = p_event_id and status = 'going'
        and user_id <> uid;
      if cnt >= e.capacity then
        raise exception 'event is full';
      end if;
    end if;

    insert into public.club_event_rsvps (event_id, user_id, status)
    values (p_event_id, uid, st)
    on conflict (event_id, user_id) do update set status = excluded.status;
  end if;

  update public.club_events set rsvp_count = (
    select count(*)::int from public.club_event_rsvps
    where event_id = p_event_id and status = 'going'
  )
  where id = p_event_id
  returning * into e;

  return json_build_object(
    'id', e.id,
    'rsvpCount', e.rsvp_count,
    'myStatus', st,
    'capacity', e.capacity
  );
end;
$$;

grant execute on function public.create_club(text, text, text, boolean) to authenticated;
grant execute on function public.list_clubs(boolean, int) to anon, authenticated;
grant execute on function public.get_club(uuid) to anon, authenticated;
grant execute on function public.join_club(uuid) to authenticated;
grant execute on function public.leave_club(uuid) to authenticated;
grant execute on function public.create_club_event(uuid, text, timestamptz, text, text, uuid, text, int) to authenticated;
grant execute on function public.list_club_events(uuid, boolean, int) to anon, authenticated;
grant execute on function public.rsvp_club_event(uuid, text) to authenticated;
