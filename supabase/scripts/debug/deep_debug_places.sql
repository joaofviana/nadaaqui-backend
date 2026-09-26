-- Deep debug: check if there are any published places at all
-- This will help us understand if the problem is data-related

-- 1. Check total places
select count(*) as total_places,
       count(*) filter (where is_published = true) as published_places
from public.places;

-- 2. Check places by city
select city_slug,
       count(*) as total,
       count(*) filter (where is_published = true) as published
from public.places
group by city_slug;

-- 3. Check app_config
select * from public.app_config;

-- 4. Test nearby_places_simple with explicit city
select * from public.nearby_places_simple(
  p_city_slug => 'sao-paulo',
  p_limit => 5
);

-- 5. Check if there are any syntax errors in the function
select pg_get_functiondef(oid) as definition
from pg_proc
where proname = 'nearby_places_simple'
  and pronamespace = 'public'::regnamespace;

-- 6. Check if the function has proper grants
select grantee, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
  and routine_name = 'nearby_places_simple';
