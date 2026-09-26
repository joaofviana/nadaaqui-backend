-- Check if there are any published places
-- This will tell us if the problem is data-related

-- Count total and published places
select 
  count(*) as total_places,
  count(*) filter (where is_published = true) as published_places,
  count(*) filter (where city_slug = 'sao-paulo') as sao_paulo_places
from public.places;

-- List some published places
select id, name, city_slug, is_published
from public.places
where is_published = true
limit 10;
