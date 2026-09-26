-- Debug nearby_places to find the real cause of 400 error
-- Check if function exists and what parameters it accepts

-- 1. Check function definition
select pg_get_functiondef(oid) as definition
from pg_proc
where proname = 'nearby_places'
  and pronamespace = 'public'::regnamespace;

-- 2. Test with minimal parameters (no GPS, no city)
select * from public.nearby_places(
  p_limit => 5
);

-- 3. Test with city only
select * from public.nearby_places(
  p_city_slug => 'sao-paulo',
  p_limit => 5
);

-- 4. Check if there are any published places
select count(*) as total_places,
       city_slug
from public.places
where is_published = true
group by city_slug;

-- 5. Check app_config
select * from public.app_config;

-- 6. Check if there are any syntax errors in the function
\df public.nearby_places
