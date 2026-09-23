-- Live ainda retorna 42702 column reference "id" is ambiguous.
-- Causa: RETURNS TABLE(id ...) + SELECT pl.id colide com variável de saída.
-- Fix: aliases internos (place_id, place_name, ...) como em 20260918001000.

begin;

create or replace function public.nearby_places(
  p_lat double precision default null,
  p_lng double precision default null,
  p_radius_meters int default 5000,
  p_bbox text default null,
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
  v_limit int := coalesce(p_limit, 50);
  v_offset int := coalesce(p_offset, 0);
begin
  if v_limit < 1 then v_limit := 50; end if;
  if v_limit > 100 then v_limit := 100; end if;
  if v_offset < 0 then v_offset := 0; end if;

  select c.city_slug into v_city from public.app_config c where c.id = 1;
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
      pl.id as place_id,
      pl.name as place_name,
      pl.place_type as pt,
      ST_Y(pl.location::geometry) as plat,
      ST_X(pl.location::geometry) as plng,
      pl.price_type as pprice,
      pl.total_pass as ppass,
      case when v_origin is not null then ST_Distance(pl.location, v_origin)::int else null end as dist,
      case when cardinality(pl.photos) > 0 then pl.photos[1] else null end as thumb
    from public.places pl
    where pl.is_published = true
      and pl.city_slug = v_city
      and (p_price_types is null or pl.price_type = any (p_price_types))
      and (p_total_pass is null or pl.total_pass = any (p_total_pass))
      and (v_origin is null or ST_DWithin(pl.location, v_origin, coalesce(p_radius_meters, 5000)))
      and (
        v_min_lng is null
        or pl.location && ST_MakeEnvelope(v_min_lng, v_min_lat, v_max_lng, v_max_lat, 4326)::geography
      )
  ),
  counted as (
    select f.*, count(*) over() as cnt from filtered f
  )
  select
    c.place_id,
    c.place_name,
    c.pt,
    c.plat,
    c.plng,
    c.pprice,
    c.ppass,
    c.dist,
    c.thumb,
    c.cnt
  from counted c
  order by
    case when c.dist is null then 1 else 0 end,
    c.dist nulls last,
    c.place_name
  limit v_limit offset v_offset;
end;
$$;

grant execute on function public.nearby_places(
  double precision, double precision, int, text, text,
  public.price_type[], public.total_pass[], int, int
) to anon, authenticated;

commit;
