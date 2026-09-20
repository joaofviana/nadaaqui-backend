-- NadaAqui Sprint 1 — RPCs alinhados ao OpenAPI /v1

create or replace function public.get_remote_config()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'checkInRadiusMeters', check_in_radius_meters,
    'locationMaxAgeSeconds', location_max_age_seconds,
    'checkInTtlSeconds', check_in_ttl_seconds,
    'presencePollSeconds', presence_poll_seconds,
    'citySlug', city_slug
  )
  from public.app_config
  where id = 1;
$$;

grant execute on function public.get_remote_config() to anon, authenticated;

-- Lista places por proximidade / city / filtros
create or replace function public.nearby_places(
  p_lat double precision default null,
  p_lng double precision default null,
  p_radius_meters int default 5000,
  p_bbox text default null,           -- 'minLng,minLat,maxLng,maxLat'
  p_city_slug text default null,
  p_price_types public.price_type[] default null,
  p_total_pass public.total_pass[] default null,
  p_limit int default 100,
  p_offset int default 0
)
returns table (
  id uuid,
  name text,
  place_type public.place_type,
  lat double precision,
  lng double precision,
  price_type public.price_type,
  total_pass public.total_pass,
  distance_meters int,
  thumbnail_url text,
  total_count bigint
)
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_origin geography;
  v_min_lng double precision;
  v_min_lat double precision;
  v_max_lng double precision;
  v_max_lat double precision;
  v_city text;
begin
  if p_limit is null or p_limit < 1 then p_limit := 100; end if;
  if p_limit > 200 then p_limit := 200; end if;
  if p_offset is null or p_offset < 0 then p_offset := 0; end if;

  select city_slug into v_city from public.app_config where id = 1;
  if p_city_slug is not null and length(trim(p_city_slug)) > 0 then
    v_city := p_city_slug;
  end if;

  if p_lat is not null and p_lng is not null then
    v_origin := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;
  end if;

  if p_bbox is not null and length(trim(p_bbox)) > 0 then
    v_min_lng := split_part(p_bbox, ',', 1)::double precision;
    v_min_lat := split_part(p_bbox, ',', 2)::double precision;
    v_max_lng := split_part(p_bbox, ',', 3)::double precision;
    v_max_lat := split_part(p_bbox, ',', 4)::double precision;
  end if;

  return query
  with filtered as (
    select
      pl.id,
      pl.name,
      pl.place_type,
      ST_Y(pl.location::geometry) as lat,
      ST_X(pl.location::geometry) as lng,
      pl.price_type,
      pl.total_pass,
      case
        when v_origin is not null then ST_Distance(pl.location, v_origin)::int
        else null
      end as distance_meters,
      case when cardinality(pl.photos) > 0 then pl.photos[1] else null end as thumbnail_url
    from public.places pl
    where pl.is_published = true
      and pl.city_slug = v_city
      and (p_price_types is null or pl.price_type = any (p_price_types))
      and (
        p_total_pass is null
        or pl.total_pass = any (p_total_pass)
      )
      and (
        v_origin is null
        or ST_DWithin(pl.location, v_origin, coalesce(p_radius_meters, 5000))
      )
      and (
        v_min_lng is null
        or pl.location && ST_MakeEnvelope(v_min_lng, v_min_lat, v_max_lng, v_max_lat, 4326)::geography
      )
  ),
  counted as (
    select f.*, count(*) over() as total_count
    from filtered f
  )
  select
    c.id, c.name, c.place_type, c.lat, c.lng, c.price_type, c.total_pass,
    c.distance_meters, c.thumbnail_url, c.total_count
  from counted c
  order by
    case when c.distance_meters is null then 1 else 0 end,
    c.distance_meters nulls last,
    c.name
  limit p_limit offset p_offset;
end;
$$;

grant execute on function public.nearby_places(
  double precision, double precision, int, text, text,
  public.price_type[], public.total_pass[], int, int
) to anon, authenticated;

-- Ficha
create or replace function public.get_place(p_place_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  r record;
begin
  select
    pl.id, pl.name, pl.place_type,
    ST_Y(pl.location::geometry) as lat,
    ST_X(pl.location::geometry) as lng,
    pl.price_type, pl.total_pass, pl.address, pl.description,
    pl.price_note, pl.opening_hours, pl.photos, pl.rating_avg,
    pl.rating_count, pl.city_slug
  into r
  from public.places pl
  where pl.id = p_place_id and pl.is_published = true;

  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'id', r.id,
    'name', r.name,
    'placeType', r.place_type,
    'lat', r.lat,
    'lng', r.lng,
    'priceType', r.price_type,
    'totalPass', r.total_pass,
    'distanceMeters', null,
    'thumbnailUrl', case when cardinality(r.photos) > 0 then r.photos[1] else null end,
    'address', r.address,
    'description', r.description,
    'priceNote', r.price_note,
    'openingHours', r.opening_hours,
    'photos', to_jsonb(r.photos),
    'ratingAvg', r.rating_avg,
    'ratingCount', r.rating_count,
    'citySlug', r.city_slug
  );
end;
$$;

grant execute on function public.get_place(uuid) to anon, authenticated;

-- Check-in
create or replace function public.create_check_in(
  p_place_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_accuracy_meters double precision,
  p_captured_at timestamptz,
  p_end_previous boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_cfg public.app_config%rowtype;
  v_place public.places%rowtype;
  v_origin geography;
  v_distance int;
  v_age_seconds int;
  v_profile public.profiles%rowtype;
  v_active public.check_ins%rowtype;
  v_ended_id uuid;
  v_new public.check_ins%rowtype;
begin
  if v_uid is null then
    raise exception 'UNAUTHORIZED' using errcode = 'P0001';
  end if;

  select * into v_cfg from public.app_config where id = 1;
  select * into v_profile from public.profiles where id = v_uid;
  select * into v_place from public.places where id = p_place_id and is_published = true;
  if not found then
    raise exception 'NOT_FOUND' using errcode = 'P0001';
  end if;

  v_age_seconds := extract(epoch from (now() - p_captured_at))::int;
  if v_age_seconds > v_cfg.location_max_age_seconds or v_age_seconds < -30 then
    return jsonb_build_object(
      'error', jsonb_build_object(
        'code', 'LOCATION_STALE',
        'message', 'Sua localização está desatualizada. Atualize o GPS e tente de novo.',
        'details', jsonb_build_object('maxAgeSeconds', v_cfg.location_max_age_seconds)
      )
    );
  end if;

  v_origin := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;
  v_distance := ST_Distance(v_place.location, v_origin)::int;

  if v_distance > v_cfg.check_in_radius_meters then
    return jsonb_build_object(
      'error', jsonb_build_object(
        'code', 'OUT_OF_RANGE',
        'message', 'Você precisa estar mais perto do local para fazer check-in.',
        'details', jsonb_build_object(
          'distanceMeters', v_distance,
          'radiusMeters', v_cfg.check_in_radius_meters,
          'placeId', p_place_id
        )
      )
    );
  end if;

  select * into v_active
  from public.check_ins
  where user_id = v_uid and status = 'active'
  limit 1;

  if found then
    if v_active.place_id = p_place_id then
      -- idempotente
      return jsonb_build_object(
        'checkIn', jsonb_build_object(
          'id', v_active.id,
          'placeId', v_active.place_id,
          'userId', v_active.user_id,
          'status', v_active.status,
          'startedAt', v_active.started_at,
          'expiresAt', v_active.expires_at,
          'endedAt', v_active.ended_at,
          'distanceMeters', v_active.distance_meters,
          'visibleInPresence', v_active.visible_in_presence
        ),
        'endedPreviousCheckInId', null
      );
    end if;

    if not coalesce(p_end_previous, true) then
      return jsonb_build_object(
        'error', jsonb_build_object(
          'code', 'ALREADY_CHECKED_IN',
          'message', 'Você já tem um check-in ativo em outro local.',
          'details', jsonb_build_object(
            'activePlaceId', v_active.place_id,
            'activeCheckInId', v_active.id
          )
        )
      );
    end if;

    update public.check_ins
    set status = 'ended', ended_at = now()
    where id = v_active.id;
    v_ended_id := v_active.id;
  end if;

  insert into public.check_ins (
    user_id, place_id, lat, lng, accuracy_meters, distance_meters,
    expires_at, visible_in_presence, status
  ) values (
    v_uid, p_place_id, p_lat, p_lng, p_accuracy_meters, v_distance,
    now() + make_interval(secs => v_cfg.check_in_ttl_seconds),
    v_profile.show_in_presence,
    'active'
  )
  returning * into v_new;

  return jsonb_build_object(
    'checkIn', jsonb_build_object(
      'id', v_new.id,
      'placeId', v_new.place_id,
      'userId', v_new.user_id,
      'status', v_new.status,
      'startedAt', v_new.started_at,
      'expiresAt', v_new.expires_at,
      'endedAt', v_new.ended_at,
      'distanceMeters', v_new.distance_meters,
      'visibleInPresence', v_new.visible_in_presence
    ),
    'endedPreviousCheckInId', v_ended_id
  );
end;
$$;

grant execute on function public.create_check_in(
  uuid, double precision, double precision, double precision, timestamptz, boolean
) to authenticated;

create or replace function public.checkout_check_in(p_check_in_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.check_ins%rowtype;
begin
  if v_uid is null then
    raise exception 'UNAUTHORIZED' using errcode = 'P0001';
  end if;

  update public.check_ins
  set status = 'ended', ended_at = now()
  where id = p_check_in_id and user_id = v_uid and status = 'active'
  returning * into v_row;

  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'id', v_row.id,
    'placeId', v_row.place_id,
    'userId', v_row.user_id,
    'status', v_row.status,
    'startedAt', v_row.started_at,
    'expiresAt', v_row.expires_at,
    'endedAt', v_row.ended_at,
    'distanceMeters', v_row.distance_meters,
    'visibleInPresence', v_row.visible_in_presence
  );
end;
$$;

grant execute on function public.checkout_check_in(uuid) to authenticated;

-- Presence
create or replace function public.who_is_here(p_place_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_visible int;
  v_hidden int;
  v_people jsonb;
begin
  if not exists (select 1 from public.places where id = p_place_id and is_published) then
    return null;
  end if;

  select
    count(*) filter (where visible_in_presence),
    count(*) filter (where not visible_in_presence)
  into v_visible, v_hidden
  from public.check_ins
  where place_id = p_place_id
    and status = 'active'
    and expires_at > now();

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'userId', c.user_id,
      'displayName', p.display_name,
      'avatarUrl', p.avatar_url,
      'checkedInAt', c.started_at
    )
    order by c.started_at desc
  ), '[]'::jsonb)
  into v_people
  from public.check_ins c
  join public.profiles p on p.id = c.user_id
  where c.place_id = p_place_id
    and c.status = 'active'
    and c.expires_at > now()
    and c.visible_in_presence = true;

  return jsonb_build_object(
    'placeId', p_place_id,
    'visibleCount', coalesce(v_visible, 0),
    'hiddenCount', coalesce(v_hidden, 0),
    'people', v_people
  );
end;
$$;

grant execute on function public.who_is_here(uuid) to anon, authenticated;

-- Expirar check-ins (chamar via pg_cron a cada 5–10 min)
create or replace function public.expire_check_ins()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  n int;
begin
  with u as (
    update public.check_ins
    set status = 'ended', ended_at = now()
    where status = 'active' and expires_at < now()
    returning 1
  )
  select count(*) into n from u;
  return n;
end;
$$;

grant execute on function public.expire_check_ins() to service_role;

-- Sync privacy toggle → check-in ativo
create or replace function public.sync_presence_visibility()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.show_in_presence is distinct from old.show_in_presence then
    update public.check_ins
    set visible_in_presence = new.show_in_presence
    where user_id = new.id and status = 'active';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_sync_presence on public.profiles;
create trigger profiles_sync_presence
  after update of show_in_presence on public.profiles
  for each row execute function public.sync_presence_visibility();
