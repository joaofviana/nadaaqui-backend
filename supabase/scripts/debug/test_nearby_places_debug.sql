-- Test nearby_places RPC to debug 400 error
-- Run this in Supabase SQL Editor

-- Test with minimal parameters
select * from public.nearby_places(
  p_limit => 50,
  p_offset => 0
);

-- Test with city slug
select * from public.nearby_places(
  p_city_slug => 'sao-paulo',
  p_limit => 50,
  p_offset => 0
);

-- Test with GPS
select * from public.nearby_places(
  p_lat => -23.5505,
  p_lng => -46.6333,
  p_limit => 50,
  p_offset => 0
);
