-- QA place ~220 m for amber chip smoke (synthetic)
begin;
insert into public.places (
  id, name, place_type, description, address, location,
  price_type, total_pass, photos, city_slug, is_published
) values (
  '33333333-3333-3333-3333-333333333333',
  'Piscina QA Âmbar (~220 m)',
  'pool',
  'Place sintético só pra chip âmbar (150 < d ≤ 300). Não é local real.',
  'QA smoke — ~220 m do GPS mock (-23.5505,-46.6333)',
  ST_SetSRID(ST_MakePoint(-46.6333, -23.54852), 4326)::geography,
  'paid',
  'unknown',
  '{}',
  'sao-paulo',
  true
)
on conflict (id) do update set
  name = excluded.name,
  location = excluded.location,
  description = excluded.description,
  updated_at = now();
commit;
