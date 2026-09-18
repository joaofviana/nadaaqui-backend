-- Stub seed — cidade piloto São Paulo (city_slug = sao-paulo)
-- IDs alinhados ao mock WireMock/Mockoon para QA contínuo.
-- GPS de teste do app: -23.550500, -46.633300

begin;

update public.app_config
set
  check_in_radius_meters = 150,
  location_max_age_seconds = 60,
  check_in_ttl_seconds = 10800,
  presence_poll_seconds = 30,
  city_slug = 'sao-paulo',
  updated_at = now()
where id = 1;

-- Place IN (~80 m do GPS de teste)
insert into public.places (
  id, name, place_type, description, address, location,
  price_type, total_pass, price_note, opening_hours, photos,
  rating_avg, rating_count, city_slug, is_published
) values (
  '11111111-1111-1111-1111-111111111111',
  'Piscina Clube Centro',
  'pool',
  'Piscina olímpica — local DENTRO do raio de check-in no mock QA.',
  'Rua Exemplo 100, Centro, São Paulo - SP',
  ST_SetSRID(ST_MakePoint(-46.6335, -23.5509), 4326)::geography,
  'paid',
  'yes',
  'Diária ~R$ 40',
  '{"mon-fri":"06:00-22:00","sat-sun":"08:00-20:00"}'::jsonb,
  '{}',
  4.50,
  12,
  'sao-paulo',
  true
)
on conflict (id) do update set
  name = excluded.name,
  location = excluded.location,
  price_type = excluded.price_type,
  total_pass = excluded.total_pass,
  city_slug = excluded.city_slug,
  is_published = true,
  updated_at = now();

-- Place OUT (~450 m)
insert into public.places (
  id, name, place_type, description, address, location,
  price_type, total_pass, price_note, opening_hours, photos,
  rating_avg, rating_count, city_slug, is_published
) values (
  '22222222-2222-2222-2222-222222222222',
  'Praia Artificial Parque',
  'beach',
  'Local gratuito — FORA do raio (espera OUT_OF_RANGE no check-in).',
  'Av. Parque 500, São Paulo - SP',
  ST_SetSRID(ST_MakePoint(-46.6350, -23.5540), 4326)::geography,
  'free',
  'no',
  null,
  null,
  '{}',
  null,
  0,
  'sao-paulo',
  true
)
on conflict (id) do update set
  name = excluded.name,
  location = excluded.location,
  price_type = excluded.price_type,
  total_pass = excluded.total_pass,
  city_slug = excluded.city_slug,
  is_published = true,
  updated_at = now();

-- Extras stub (expandir curadoria depois) — Total Pass unknown para testar filtro
insert into public.places (
  id, name, place_type, description, address, location,
  price_type, total_pass, city_slug, is_published
) values (
  '33333333-3333-3333-3333-333333333333',
  'Lagoa do Parque Ibirapuera (stub)',
  'lake',
  'Stub curadoria — total_pass unknown (não entra em Aceita/Não aceita).',
  'Parque Ibirapuera, São Paulo - SP',
  ST_SetSRID(ST_MakePoint(-46.6576, -23.5874), 4326)::geography,
  'free',
  'unknown',
  'sao-paulo',
  true
)
on conflict (id) do nothing;

commit;
