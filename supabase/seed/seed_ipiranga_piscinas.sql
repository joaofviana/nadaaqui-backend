-- Seed Ipiranga (piscinas) — curadoria Po + revisão Backend
-- Fotos = placeholders (Wikimedia/Unsplash/Sesc). Produção: Google Places Photo API (não hotlinkar tiles Maps).
-- Clube Ipiranga: NÃO publicar até confirmar endereço SP (site citado é RS).
begin;

insert into public.places (
  id, name, place_type, description, address, location,
  price_type, total_pass, photos, city_slug, is_published
) values (
  'aaaaaaaa-1111-4111-8111-111111111101',
  'Clube Atlético Ypiranga (CAY)',
  'club',
  'Complexo aquático aquecido; piscinas adulto/infantil. Sócios. Foto: placeholder Wikimedia (região) — trocar por Places Photo API.',
  'Rua do Manifesto, 475 - Ipiranga, São Paulo - SP, 04209-000',
  ST_SetSRID(ST_MakePoint(-46.6095, -23.5855), 4326)::geography,
  'paid',
  'unknown',
  ARRAY["https://upload.wikimedia.org/wikipedia/commons/thumb/8/8f/Parque_da_Independ%C3%AAncia.jpg/1280px-Parque_da_Independ%C3%AAncia.jpg"]::text[],
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
  city_slug = excluded.city_slug,
  is_published = excluded.is_published,
  updated_at = now();


insert into public.places (
  id, name, place_type, description, address, location,
  price_type, total_pass, photos, city_slug, is_published
) values (
  'aaaaaaaa-1111-4111-8111-111111111102',
  'Sesc Ipiranga — Piscina',
  'other',
  'STATUS (set/2026): piscina TEMPORARIAMENTE FECHADA p/ manutenção estrutural no túnel técnico (fonte: sescsp.org.br). Credencial Plena quando reabrir. Foto: Sesc SP (preferir Places Photo API).',
  'Rua Bom Pastor, 822 - Ipiranga, São Paulo - SP, 04203-000',
  ST_SetSRID(ST_MakePoint(-46.6108, -23.5852), 4326)::geography,
  'paid',
  'no',
  ARRAY["https://www.sescsp.org.br/wp-content/uploads/2022/07/sesc-ipiranga-fachada.jpg"]::text[],
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
  city_slug = excluded.city_slug,
  is_published = excluded.is_published,
  updated_at = now();


insert into public.places (
  id, name, place_type, description, address, location,
  price_type, total_pass, photos, city_slug, is_published
) values (
  'aaaaaaaa-1111-4111-8111-111111111103',
  'CE Ipiranga — Balneário Carlos Joel Nelli',
  'pool',
  'Piscina pública SEME (formato feijão, climatizada). Carteirinha gratuita. Ter–Dom 8–12 e 13–17. Foto: placeholder Wikimedia.',
  'Praça Nami Jafet, 45 - Ipiranga, São Paulo - SP, 04205-050',
  ST_SetSRID(ST_MakePoint(-46.6098, -23.5889), 4326)::geography,
  'free',
  'no',
  ARRAY["https://upload.wikimedia.org/wikipedia/commons/thumb/4/4e/Museu_do_Ipiranga_2022.jpg/1280px-Museu_do_Ipiranga_2022.jpg"]::text[],
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
  city_slug = excluded.city_slug,
  is_published = excluded.is_published,
  updated_at = now();


insert into public.places (
  id, name, place_type, description, address, location,
  price_type, total_pass, photos, city_slug, is_published
) values (
  'aaaaaaaa-1111-4111-8111-111111111104',
  'Clube Ipiranga (PENDENTE)',
  'club',
  'REVISÃO PO: site citado (ipirangafw.com.br) NÃO é SP. Sem endereço oficial SP encontrado. is_published=false até confirmar ou remover.',
  'ENDEREÇO NÃO CONFIRMADO EM SP — ipirangafw.com.br é Frederico Westphalen/RS (Rua Piratini, 890)',
  ST_SetSRID(ST_MakePoint(-46.612, -23.5905), 4326)::geography,
  'paid',
  'unknown',
  ARRAY["https://upload.wikimedia.org/wikipedia/commons/thumb/8/8f/Parque_da_Independ%C3%AAncia.jpg/1280px-Parque_da_Independ%C3%AAncia.jpg"]::text[],
  'sao-paulo',
  false
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
  city_slug = excluded.city_slug,
  is_published = excluded.is_published,
  updated_at = now();


insert into public.places (
  id, name, place_type, description, address, location,
  price_type, total_pass, photos, city_slug, is_published
) values (
  'aaaaaaaa-1111-4111-8111-111111111105',
  'Academia Acqua Raciness',
  'other',
  'Piscina, hidro, natação. Foto: Unsplash genérica — trocar por Places Photo.',
  'Rua Agostinho Gomes, 3197 - Ipiranga, São Paulo - SP',
  ST_SetSRID(ST_MakePoint(-46.6015, -23.5928), 4326)::geography,
  'paid',
  'unknown',
  ARRAY["https://images.unsplash.com/photo-1519315901367-f34ff2716bc8?w=1200"]::text[],
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
  city_slug = excluded.city_slug,
  is_published = excluded.is_published,
  updated_at = now();


insert into public.places (
  id, name, place_type, description, address, location,
  price_type, total_pass, photos, city_slug, is_published
) values (
  'aaaaaaaa-1111-4111-8111-111111111106',
  'Training Up Academia',
  'other',
  'Piscina semiolímpica / natação (confirmar oferta atual). Foto: Unsplash genérica — trocar por Places Photo.',
  'Rua Agostinho Gomes, 1928 - Ipiranga, São Paulo - SP',
  ST_SetSRID(ST_MakePoint(-46.6055, -23.591), 4326)::geography,
  'paid',
  'unknown',
  ARRAY["https://images.unsplash.com/photo-1576013551627-0cc20b96c2a7?w=1200"]::text[],
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
  city_slug = excluded.city_slug,
  is_published = excluded.is_published,
  updated_at = now();

commit;