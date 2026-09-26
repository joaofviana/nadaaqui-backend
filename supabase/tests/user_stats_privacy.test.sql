-- pgTAP: get_user_stats respeita a privacidade do perfil.
-- Mapeamento: profiles.privacy_show_meters = false esconde 'meters' e 'minutes'
-- para outros usuários. O dono sempre vê tudo. sessions/places/streak_days/posts
-- ficam visíveis. Só authenticated executa.
-- Usuários: A (quem olha), B (escondeu metros), C (padrão, mostra tudo).

begin;

select plan(14);

-- ---------------------------------------------------------------------------
-- Dados de teste (como postgres)
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('aaaaaaaa-1111-4000-8000-00000000000a', 'a-stats@teste.local', '{"display_name":"Ana"}'),
  ('bbbbbbbb-1111-4000-8000-00000000000b', 'b-stats@teste.local', '{"display_name":"Bia"}'),
  ('cccccccc-1111-4000-8000-00000000000c', 'c-stats@teste.local', '{"display_name":"Caio"}');

update public.profiles set privacy_show_meters = false
where id = 'bbbbbbbb-1111-4000-8000-00000000000b';

insert into public.places (id, name, location, city_slug)
values ('dddddddd-1111-4000-8000-0000000000d1', 'Piscina Teste',
        'SRID=4326;POINT(-46.6 -23.6)'::public.geography, 'sao-paulo');

-- 1 nado encerrado de 60 min ontem para B e para C
insert into public.check_ins (user_id, place_id, lat, lng, distance_meters,
                              started_at, expires_at, ended_at, status)
select u, 'dddddddd-1111-4000-8000-0000000000d1', -23.6, -46.6, 10,
       date_trunc('day', now()) - interval '1 day' + interval '8 hours',
       date_trunc('day', now()) - interval '1 day' + interval '11 hours',
       date_trunc('day', now()) - interval '1 day' + interval '9 hours',
       'ended'
from unnest(array['bbbbbbbb-1111-4000-8000-00000000000b',
                  'cccccccc-1111-4000-8000-00000000000c']::uuid[]) u;

insert into public.posts (user_id, body, city_slug)
values ('bbbbbbbb-1111-4000-8000-00000000000b', 'post da Bia', 'sao-paulo');

-- ---------------------------------------------------------------------------
-- Permissão
-- ---------------------------------------------------------------------------
select ok(
  not has_function_privilege('anon', 'public.get_user_stats(uuid)', 'execute'),
  'anon não executa get_user_stats');
select ok(
  has_function_privilege('authenticated', 'public.get_user_stats(uuid)', 'execute'),
  'authenticated executa get_user_stats');

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';
select throws_ok(
  $$select public.get_user_stats('bbbbbbbb-1111-4000-8000-00000000000b')$$,
  '42501', null, 'anon chamando get_user_stats é negado');
reset role;

-- ---------------------------------------------------------------------------
-- A olhando B (escondeu metros) e C (mostra tudo)
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-1111-4000-8000-00000000000a","role":"authenticated"}';

select is(
  (select array_agg(k order by k)
     from jsonb_object_keys(public.get_user_stats('bbbbbbbb-1111-4000-8000-00000000000b')) k),
  array['places', 'posts', 'sessions', 'streak_days'],
  'A vê só sessions/places/streak_days/posts do B (sem meters/minutes)');
select ok(
  not (public.get_user_stats('bbbbbbbb-1111-4000-8000-00000000000b') ? 'meters'),
  'meters do B escondido para A');
select ok(
  not (public.get_user_stats('bbbbbbbb-1111-4000-8000-00000000000b') ? 'minutes'),
  'minutes do B escondido para A (metros saem dos minutos)');
select is(
  public.get_user_stats('bbbbbbbb-1111-4000-8000-00000000000b')
    - 'streak_days',
  '{"sessions": 1, "places": 1, "posts": 1}'::jsonb,
  'campos visíveis do B com os valores certos');
select is(
  public.get_user_stats('cccccccc-1111-4000-8000-00000000000c'),
  jsonb_build_object('sessions', 1, 'places', 1, 'streak_days', 1, 'posts', 0,
                     'minutes', 60, 'meters', 1800),
  'A vê tudo do C (privacidade padrão)');
select throws_ok(
  $$select public.get_user_stats(null)$$,
  'P0001', 'VALIDATION_ERROR', 'get_user_stats(null) dá VALIDATION_ERROR');
select is(
  public.get_user_stats('99999999-1111-4000-8000-000000000099'),
  null::jsonb,
  'get_user_stats de usuário inexistente devolve null');

reset role;

-- ---------------------------------------------------------------------------
-- B olhando os próprios números: vê tudo
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-1111-4000-8000-00000000000b","role":"authenticated"}';

select is(
  public.get_user_stats('bbbbbbbb-1111-4000-8000-00000000000b'),
  jsonb_build_object('sessions', 1, 'places', 1, 'streak_days', 1, 'posts', 1,
                     'minutes', 60, 'meters', 1800),
  'B (dono) vê meters/minutes mesmo com privacy_show_meters = false');

-- B volta a mostrar metros pelo update_my_profile; A passa a ver
select lives_ok(
  $$select public.update_my_profile('{"privacy": {"showMeters": true}}'::jsonb)$$,
  'B liga showMeters de novo');

reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-1111-4000-8000-00000000000a","role":"authenticated"}';
select is(
  (public.get_user_stats('bbbbbbbb-1111-4000-8000-00000000000b')->>'meters')::int,
  1800,
  'depois de showMeters = true, A vê meters do B');
reset role;

-- ---------------------------------------------------------------------------
-- authenticated sem usuário no JWT
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"role":"authenticated"}';
select throws_ok(
  $$select public.get_user_stats('bbbbbbbb-1111-4000-8000-00000000000b')$$,
  'P0001', 'UNAUTHORIZED', 'get_user_stats sem usuário dá UNAUTHORIZED');
reset role;

select * from finish();

rollback;
