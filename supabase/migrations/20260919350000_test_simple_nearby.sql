-- Test simplified version of nearby_places without array parameters
-- This will help isolate if the 400 error is caused by array type handling

begin;

create or replace function public.nearby_places_simple(
  p_lat double precision default null,
  p_lng double precision default null,
  p_radius_meters int default 5000,
  p_city_slug text default null,
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
      and (
        v_origin is null
        or ST_DWithin(pl.location, v_origin, coalesce(p_radius_meters, 5000))
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
    case
      when v_origin is not null then c.distance_meters
      else 0
    end asc nulls last,
    c.name asc
  limit p_limit
  offset p_offset;
end;
$$;

grant execute on function public.nearby_places_simple to anon, authenticated;

commit;
