-- Rollback: restore original limits for nearby_places RPC
-- Revert default limit from 100 to 50, max from 200 to 100

begin;

-- Restore original nearby_places function with original limits
create or replace function public.nearby_places(
  p_lat double precision default null,
  p_lng double precision default null,
  p_radius_meters int default 5000,
  p_bbox text default null,           -- 'minLng,minLat,maxLng,maxLat'
  p_city_slug text default null,
  p_price_types public.price_type[] default null,
  p_total_pass public.total_pass[] default null,
  p_limit int default 50,
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
  if p_limit is null or p_limit < 1 then p_limit := 50; end if;
  if p_limit > 100 then p_limit := 100; end if;
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
        p_bbox is null
        or (
          ST_Within(
            pl.location::geometry,
            ST_MakeBox(
              ST_MakePoint(v_min_lng, v_min_lat),
              ST_MakePoint(v_max_lng, v_max_lat)
            )
          )
        )
      )
  ),
  counted as (
    select
      *,
      count(*) over () as total_count
    from filtered
  )
  select
    id,
    name,
    place_type,
    lat,
    lng,
    price_type,
    total_pass,
    distance_meters,
    thumbnail_url,
    total_count
  from counted
  order by
    case
      when v_origin is not null then distance_meters
      else 0
    end asc nulls last,
    name asc
  limit p_limit
  offset p_offset;
end;
$$;

grant execute on function public.nearby_places to anon, authenticated;

commit;
