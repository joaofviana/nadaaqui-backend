-- NadaAqui Sprint 1 — schema

create type public.price_type as enum ('free', 'paid', 'unknown');
create type public.total_pass as enum ('yes', 'no', 'unknown');
create type public.place_type as enum ('pool', 'beach', 'lake', 'river', 'club', 'other');
create type public.check_in_status as enum ('active', 'ended');
create type public.suggestion_status as enum ('pending', 'approved', 'rejected');
create type public.suggestion_kind as enum ('new_place', 'correction');

-- App remote config (single row)
create table public.app_config (
  id int primary key default 1 check (id = 1),
  check_in_radius_meters int not null default 150 check (check_in_radius_meters between 50 and 500),
  location_max_age_seconds int not null default 60 check (location_max_age_seconds between 10 and 600),
  check_in_ttl_seconds int not null default 10800 check (check_in_ttl_seconds between 600 and 86400),
  presence_poll_seconds int not null default 30,
  city_slug text not null default 'sao-paulo',
  updated_at timestamptz not null default now()
);

insert into public.app_config (id) values (1);

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null,
  avatar_url text,
  show_in_presence boolean not null default true,
  is_curator boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.places (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  place_type public.place_type not null default 'other',
  description text,
  address text,
  location geography(point, 4326) not null,
  price_type public.price_type not null default 'unknown',
  total_pass public.total_pass not null default 'unknown',
  price_note text,
  opening_hours jsonb,
  photos text[] not null default '{}',
  rating_avg numeric(3,2),
  rating_count int not null default 0,
  city_slug text not null,
  is_published boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index places_location_gix on public.places using gist (location);
create index places_city_published_idx on public.places (city_slug, is_published);
create index places_price_type_idx on public.places (price_type);
create index places_total_pass_idx on public.places (total_pass);
create index places_name_trgm_idx on public.places using gin (name gin_trgm_ops);

create table public.check_ins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  place_id uuid not null references public.places (id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  accuracy_meters double precision,
  distance_meters int not null,
  started_at timestamptz not null default now(),
  expires_at timestamptz not null,
  ended_at timestamptz,
  visible_in_presence boolean not null default true,
  status public.check_in_status not null default 'active',
  created_at timestamptz not null default now()
);

create index check_ins_place_active_idx
  on public.check_ins (place_id, status, expires_at)
  where status = 'active';

create unique index check_ins_one_active_per_user
  on public.check_ins (user_id)
  where status = 'active';

-- P2 stubs (tables exist; Sprint 1 não depende)
create table public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  place_id uuid references public.places (id) on delete set null,
  body text not null check (char_length(body) between 1 and 500),
  photo_url text,
  city_slug text not null,
  created_at timestamptz not null default now()
);

create table public.favorites (
  user_id uuid not null references public.profiles (id) on delete cascade,
  place_id uuid not null references public.places (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, place_id)
);

create table public.place_suggestions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  kind public.suggestion_kind not null,
  place_id uuid references public.places (id) on delete set null,
  payload jsonb not null,
  status public.suggestion_status not null default 'pending',
  reviewer_id uuid references public.profiles (id),
  review_note text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);

-- Auto profile on signup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1), 'Nadador')
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();
create trigger places_updated_at before update on public.places
  for each row execute function public.set_updated_at();
