-- Seed para piscinas em Mooca, Vila Prudente e Sacoma
-- Coordenadas aproximadas dos bairros em São Paulo

begin;

-- MOOCA (aprox. -23.5500, -46.6000)

-- Piscina do Clube Heliópolis - Mooca
insert into public.places (
  id, name, place_type, description, address, location,
  price_type, total_pass, price_note, opening_hours, photos,
  rating_avg, rating_count, city_slug, is_published
) values (
  '44444444-4444-4444-4444-444444444444',
  'Piscina Clube Heliópolis',
  'pool',
  'Piscina olímpica aquecida no coração da Mooca. 50m de comprimento.',
  'Rua da Mooca 500, Mooca, São Paulo - SP',
  ST_SetSRID(ST_MakePoint(-46.6020, -23.5510), 4326)::geography,
  'paid',
  'yes',
  'Total Pass ~R$ 50/mês',
  '{"mon-fri":"06:00-22:00","sat-sun":"08:00-18:00"}'::jsonb,
  '{}',
  4.20,
  45,
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

-- Complexo Esportivo Mooca
insert into public.places (
  id, name, place_type, description, address, location,
  price_type, total_pass, price_note, opening_hours, photos,
  rating_avg, rating_count, city_slug, is_published
) values (
  '55555555-5555-5555-5555-555555555555',
  'Complexo Esportivo Mooca',
  'pool',
  'Piscina semi-olímpica coberta e aquecida. Aulas de natação para todas as idades.',
  'Rua Silva Bueno 350, Mooca, São Paulo - SP',
  ST_SetSRID(ST_MakePoint(-46.5980, -23.5490), 4326)::geography,
  'paid',
  'no',
  'Diária ~R$ 35',
  '{"mon-fri":"06:00-21:00","sat-sun":"07:00-19:00"}'::jsonb,
  '{}',
  4.50,
  62,
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

-- VILA PRUDENTE (aprox. -23.5600, -46.5900)

-- Piscina do Ibirapuera - Vila Prudente
insert into public.places (
  id, name, place_type, description, address, location,
  price_type, total_pass, price_note, opening_hours, photos,
  rating_avg, rating_count, city_slug, is_published
) values (
  '66666666-6666-6666-6666-666666666666',
  'Piscina do Ibirapuera Vila Prudente',
  'pool',
  'Piscina olímpica 50m com aquecimento solar. Ótima para treinos.',
  'Rua Vila Prudente 800, Vila Prudente, São Paulo - SP',
  ST_SetSRID(ST_MakePoint(-46.5920, -23.5610), 4326)::geography,
  'paid',
  'yes',
  'Total Pass ~R$ 60/mês',
  '{"mon-fri":"05:30-22:00","sat-sun":"07:00-20:00"}'::jsonb,
  '{}',
  4.70,
  89,
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

-- Clube Paulistano - Unidade Vila Prudente
insert into public.places (
  id, name, place_type, description, address, location,
  price_type, total_pass, price_note, opening_hours, photos,
  rating_avg, rating_count, city_slug, is_published
) values (
  '77777777-7777-7777-7777-777777777777',
  'Clube Paulistano Vila Prudente',
  'pool',
  'Piscina olímpica coberta e aquecida. Infraestrutura completa.',
  'Rua do Oratório 1200, Vila Prudente, São Paulo - SP',
  ST_SetSRID(ST_MakePoint(-46.5880, -23.5590), 4326)::geography,
  'paid',
  'yes',
  'Total Pass ~R$ 80/mês',
  '{"mon-fri":"06:00-22:00","sat-sun":"08:00-21:00"}'::jsonb,
  '{}',
  4.80,
  156,
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

-- SACOMA (aprox. -23.6300, -46.6900)

-- Piscina do Sacomê
insert into public.places (
  id, name, place_type, description, address, location,
  price_type, total_pass, price_note, opening_hours, photos,
  rating_avg, rating_count, city_slug, is_published
) values (
  '88888888-8888-8888-8888-888888888888',
  'Piscina do Sacomê',
  'pool',
  'Piscina municipal com aquecimento. Ideal para treinos de resistência.',
  'Rua do Sacomê 400, Sacoma, São Paulo - SP',
  ST_SetSRID(ST_MakePoint(-46.6920, -23.6310), 4326)::geography,
  'paid',
  'no',
  'Diária ~R$ 25',
  '{"mon-fri":"06:00-20:00","sat-sun":"08:00-18:00"}'::jsonb,
  '{}',
  4.30,
  34,
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

-- Complexo Esportivo Sacoma
insert into public.places (
  id, name, place_type, description, address, location,
  price_type, total_pass, price_note, opening_hours, photos,
  rating_avg, rating_count, city_slug, is_published
) values (
  '99999999-9999-9999-9999-999999999999',
  'Complexo Esportivo Sacoma',
  'pool',
  'Piscina semi-olímpica 25m coberta. Aulas de hidroginástica e natação.',
  'Av. Sacoma 1500, Sacoma, São Paulo - SP',
  ST_SetSRID(ST_MakePoint(-46.6880, -23.6290), 4326)::geography,
  'paid',
  'no',
  'Diária ~R$ 30',
  '{"mon-fri":"07:00-21:00","sat-sun":"08:00-20:00"}'::jsonb,
  '{}',
  4.40,
  28,
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

-- ADICIONAL: Tanque de Ipiranga já existe no seed_ipiranga_piscinas.sql
-- Este arquivo foca em Mooca, Vila Prudente e Sacoma

commit;