-- Seed Ipiranga v2 (Po curadoria) — 7 publicados + limpeza v1
-- Não publicar: Dentro D'Água. Opcional entorno (Run2Fit, Acqua Mooca) fora deste seed.
begin;

-- Remove seed Ipiranga v1 ids
delete from public.places where id = 'aaaaaaaa-1111-4111-8111-111111111101';
delete from public.places where id = 'aaaaaaaa-1111-4111-8111-111111111102';
delete from public.places where id = 'aaaaaaaa-1111-4111-8111-111111111103';
delete from public.places where id = 'aaaaaaaa-1111-4111-8111-111111111104';
delete from public.places where id = 'aaaaaaaa-1111-4111-8111-111111111105';
delete from public.places where id = 'aaaaaaaa-1111-4111-8111-111111111106';


insert into public.places (
  id, name, place_type, description, address, location,
  price_type, total_pass, photos, city_slug, is_published
) values (
  '952f671d-fb18-46eb-a45a-e0897e925650',
  'Centro Esportivo Ipiranga – Balneário Carlos Joel Nelli',
  'pool',
  'Piscina pública coberta/climatizada (formato feijão). Acesso gratuito com carteirinha SEME (RG, foto 3x4, comprovante de residência). Horário típico da piscina: ter–dom ~8h–12h e 13h–17h; confirmar no local. Tel. (11) 2273-1302. Confidence: high. Foto: Estadão Expresso (cobertura da revitalização, jun/2025).',
  'Praça Nami Jafet, 45 – Ipiranga, São Paulo – SP, 04205-050',
  ST_SetSRID(ST_MakePoint(-46.6058969, -23.5802452), 4326)::geography,
  'free',
  'no',
  ARRAY["https://expresso.estadao.com.br/sao-paulo/wp-content/uploads/2025/06/20250616_Centro_Espirtivo_Ipiranga_SB-21-scaled.jpg"]::text[],
  'sao-paulo',
  true
)
on conflict (id) do update set
  name = excluded.name,
  place_type = excluded.place_type,
  description = excluded.description,
  address = excluded.address,
  location = excluded.location,
  price_type = excluded.price_type,
  total_pass = excluded.total_pass,
  photos = excluded.photos,
  city_slug = 'sao-paulo',
  is_published = true,
  updated_at = now();


insert into public.places (
  id, name, place_type, description, address, location,
  price_type, total_pass, photos, city_slug, is_published
) values (
  'b90aa544-aa3c-4d59-a3e8-ff0869b709f0',
  'Sesc Ipiranga',
  'other',
  'Piscina coberta e aquecida; exige Credencial Plena Sesc + exame dermatológico. Em 2025/2026 o site da unidade sinalizou fechamento temporário por manutenção estrutural no túnel técnico — confirmar reabertura antes de ir. Tel. (11) 3340-2000. Confidence: high. Foto: Sesc São Paulo (site oficial / Divulgação).',
  'Rua Bom Pastor, 822 – Ipiranga, São Paulo – SP, 04203-000',
  ST_SetSRID(ST_MakePoint(-46.6080109, -23.5841383), 4326)::geography,
  'paid',
  'no',
  ARRAY["https://www.sescsp.org.br/wp-content/uploads/2023/11/Piscina-do-Sesc-Ipiranga-Divulgacao.png"]::text[],
  'sao-paulo',
  true
)
on conflict (id) do update set
  name = excluded.name,
  place_type = excluded.place_type,
  description = excluded.description,
  address = excluded.address,
  location = excluded.location,
  price_type = excluded.price_type,
  total_pass = excluded.total_pass,
  photos = excluded.photos,
  city_slug = 'sao-paulo',
  is_published = true,
  updated_at = now();


insert into public.places (
  id, name, place_type, description, address, location,
  price_type, total_pass, photos, city_slug, is_published
) values (
  '63657e49-38cc-4622-af36-0e3809d41d21',
  'Clube Atlético Ypiranga (CAY)',
  'club',
  'Clube histórico (1906) com piscinas e aulas de natação (sócios e alunos não-sócios com matrícula). Contato natação: (11) 3386-3386 ramal 3392. Confidence: high. Foto: cay.com.br (site oficial do clube).',
  'Rua do Manifesto, 475 – Ipiranga, São Paulo – SP, 04209-000',
  ST_SetSRID(ST_MakePoint(-46.6020269, -23.5767225), 4326)::geography,
  'paid',
  'unknown',
  ARRAY["https://cay.com.br/wp-content/uploads/2026/07/DSC0060-1-scaled.jpg"]::text[],
  'sao-paulo',
  true
)
on conflict (id) do update set
  name = excluded.name,
  place_type = excluded.place_type,
  description = excluded.description,
  address = excluded.address,
  location = excluded.location,
  price_type = excluded.price_type,
  total_pass = excluded.total_pass,
  photos = excluded.photos,
  city_slug = 'sao-paulo',
  is_published = true,
  updated_at = now();


insert into public.places (
  id, name, place_type, description, address, location,
  price_type, total_pass, photos, city_slug, is_published
) values (
  '553d0911-92dd-41d6-a63c-04c3b156d995',
  'Aqua School (Go Now Alto do Ipiranga)',
  'other',
  'Escola de natação desde ~2011; piscina ~15 m aquecida (~30–31,5 °C). Bebês, infantil, adulto e hidroginástica. No Wellhub aparece como Go Now – Alto do Ipiranga (mesmo endereço/telefone). Tel. (11) 2063-5108 / WhatsApp (11) 99011-2710. Alguns diretórios listam nº 212 — preferir 192 (site oficial). Confidence: high. Foto: aquaschool.com.br (site oficial).',
  'Rua Ribeiro do Amaral, 192 – Ipiranga / Alto do Ipiranga, São Paulo – SP, 04268-000',
  ST_SetSRID(ST_MakePoint(-46.6086734, -23.5958421), 4326)::geography,
  'paid',
  'unknown',
  ARRAY["https://www.aquaschool.com.br/wp-content/uploads/2025/04/estrutura2.jpg"]::text[],
  'sao-paulo',
  true
)
on conflict (id) do update set
  name = excluded.name,
  place_type = excluded.place_type,
  description = excluded.description,
  address = excluded.address,
  location = excluded.location,
  price_type = excluded.price_type,
  total_pass = excluded.total_pass,
  photos = excluded.photos,
  city_slug = 'sao-paulo',
  is_published = true,
  updated_at = now();


insert into public.places (
  id, name, place_type, description, address, location,
  price_type, total_pass, photos, city_slug, is_published
) values (
  'c93fcb17-14f5-4483-adce-288fff2a8f07',
  'Academia Training UP',
  'other',
  'Academia com piscina semi-olímpica (~25 m) aquecida; natação e hidroginástica além de musculação/artes marciais. Tel. (11) 2215-2415 / WhatsApp (11) 96352-0145. Instagram @academiatrainingup. Foto pública estável não encontrada no momento. Confidence: high.',
  'Rua Agostinho Gomes, 1928 – Ipiranga, São Paulo – SP, 04206-001',
  ST_SetSRID(ST_MakePoint(-46.6041896, -23.5874195), 4326)::geography,
  'paid',
  'unknown',
  '{}'::text[],
  'sao-paulo',
  true
)
on conflict (id) do update set
  name = excluded.name,
  place_type = excluded.place_type,
  description = excluded.description,
  address = excluded.address,
  location = excluded.location,
  price_type = excluded.price_type,
  total_pass = excluded.total_pass,
  photos = excluded.photos,
  city_slug = 'sao-paulo',
  is_published = true,
  updated_at = now();


insert into public.places (
  id, name, place_type, description, address, location,
  price_type, total_pass, photos, city_slug, is_published
) values (
  'c6d37240-a27f-494c-ad94-b8c752acaec8',
  'Soul Beach Arena',
  'other',
  'Arena de esportes de areia com day use (areia + piscina), bar/restaurante e quadras. Também listada no Wellhub. Página TotalPass sem parceria ativa no momento da pesquisa. Confidence: high. Foto: arenasoulbeach.com.br (site oficial).',
  'Av. Dom Pedro I, 700 – Vila Monumento / Ipiranga, São Paulo – SP, 01552-000',
  ST_SetSRID(ST_MakePoint(-46.6112691, -23.5713643), 4326)::geography,
  'paid',
  'no',
  ARRAY["https://arenasoulbeach.com.br/img/arena-soul-beach-esporte-comida-servico-3.jpg"]::text[],
  'sao-paulo',
  true
)
on conflict (id) do update set
  name = excluded.name,
  place_type = excluded.place_type,
  description = excluded.description,
  address = excluded.address,
  location = excluded.location,
  price_type = excluded.price_type,
  total_pass = excluded.total_pass,
  photos = excluded.photos,
  city_slug = 'sao-paulo',
  is_published = true,
  updated_at = now();


insert into public.places (
  id, name, place_type, description, address, location,
  price_type, total_pass, photos, city_slug, is_published
) values (
  'fc042c45-03a5-4bf6-a860-f5f40d43b0b2',
  'Centro Esportivo Vila Carioca – Balneário Princesa Isabel',
  'pool',
  'Centro esportivo municipal na Subprefeitura Ipiranga (bairro Vila Carioca, vizinho). Piscina listada pela SEME (ter–dom ~8h–12h e 13h–17h). Carteirinha municipal gratuita. Tel. (11) 2215-5299. Coords aproximadas (geocode da rua; confirmar pin). Confidence: high (existência); medium (coords exatas).',
  'Rua Campante, 100 – Vila Carioca, São Paulo – SP, 04214-040',
  ST_SetSRID(ST_MakePoint(-46.5917089, -23.5989841), 4326)::geography,
  'free',
  'no',
  '{}'::text[],
  'sao-paulo',
  true
)
on conflict (id) do update set
  name = excluded.name,
  place_type = excluded.place_type,
  description = excluded.description,
  address = excluded.address,
  location = excluded.location,
  price_type = excluded.price_type,
  total_pass = excluded.total_pass,
  photos = excluded.photos,
  city_slug = 'sao-paulo',
  is_published = true,
  updated_at = now();

commit;