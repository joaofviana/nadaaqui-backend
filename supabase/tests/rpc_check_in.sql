-- F4 — 6 casos de domínio (nearby + check-in).
-- Rodar no SQL editor como postgres DEPOIS de migrations + seed SP/Ipiranga.
-- Falha = RAISE EXCEPTION (não é NOTICE).
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rpc_check_in.sql

begin;

do $$
declare
  v_uid uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1';
  v_place_in uuid := '11111111-1111-1111-1111-111111111111';
  v_place_out uuid := '22222222-2222-2222-2222-222222222222';
  v_ipiranga uuid := '952f671d-fb18-46eb-a45a-e0897e925650';
  r jsonb;
  n int;
  first_id uuid;
  first_name text;
  id1 uuid;
  id2 uuid;
  active_n int;
begin
  -- 1) nearby Ipiranga ordenado por distância
  select id, name into first_id, first_name
  from public.nearby_places(
    -23.5802452, -46.6058969, 5000,
    null, 'sao-paulo', null, null, 10, 0
  )
  limit 1;

  if first_id is null then
    raise exception 'F4.1 FAIL: nearby_places vazio (seed Ipiranga aplicado?)';
  end if;
  if first_id is distinct from v_ipiranga
     and first_name not ilike '%ipiranga%'
     and first_name not ilike '%ypiranga%'
     and first_name not ilike '%sesc%' then
    raise exception 'F4.1 FAIL: primeiro nearby não parece Ipiranga (% / %)', first_id, first_name;
  end if;
  raise notice 'F4.1 PASS nearby → % (%)', first_name, first_id;

  -- user de teste em auth.users (idempotente)
  begin
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, confirmation_token, recovery_token
    ) values (
      '00000000-0000-0000-0000-000000000000',
      v_uid,
      'authenticated', 'authenticated',
      'f4-tester@nadaaqui.app',
      crypt('f4-test-pass', gen_salt('bf')),
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{"display_name":"F4 Tester"}'::jsonb,
      now(), now(), '', ''
    )
    on conflict (id) do nothing;
  exception
    when others then
      raise notice 'F4: insert auth.users falhou (%). Tentando profiles direto.', sqlerrm;
  end;

  insert into public.profiles (id, display_name)
  values (v_uid, 'F4 Tester')
  on conflict (id) do nothing;

  perform set_config('request.jwt.claim.sub', v_uid::text, true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_uid, 'role', 'authenticated', 'email', 'f4-tester@nadaaqui.app')::text,
    true);

  -- limpa check-ins do tester
  delete from public.check_ins where user_id = v_uid;

  -- 2) OUT_OF_RANGE (place OUT, GPS do IN)
  r := public.create_check_in(
    v_place_out, -23.5505, -46.6333, 10, now(), true
  );
  if r #>> '{error,code}' is distinct from 'OUT_OF_RANGE' then
    raise exception 'F4.2 FAIL: esperado OUT_OF_RANGE, veio %', r;
  end if;
  if (r #>> '{error,details,distanceMeters}') is null then
    raise exception 'F4.2 FAIL: details.distanceMeters ausente';
  end if;
  raise notice 'F4.2 PASS OUT_OF_RANGE';

  -- 3) LOCATION_STALE
  r := public.create_check_in(
    v_place_in, -23.5505, -46.6333, 10, now() - interval '10 minutes', true
  );
  if r #>> '{error,code}' is distinct from 'LOCATION_STALE' then
    raise exception 'F4.3 FAIL: esperado LOCATION_STALE, veio %', r;
  end if;
  raise notice 'F4.3 PASS LOCATION_STALE';

  -- 4) mesmo place = idempotente
  r := public.create_check_in(
    v_place_in, -23.5505, -46.6333, 10, now(), true
  );
  if r #>> '{error,code}' is not null then
    raise exception 'F4.4 FAIL: primeiro check-in IN falhou %', r;
  end if;
  id1 := (r #>> '{checkIn,id}')::uuid;

  r := public.create_check_in(
    v_place_in, -23.5505, -46.6333, 10, now(), true
  );
  id2 := (r #>> '{checkIn,id}')::uuid;
  if id1 is distinct from id2 then
    raise exception 'F4.4 FAIL: idempotência quebrou (% vs %)', id1, id2;
  end if;
  raise notice 'F4.4 PASS idempotente id=%', id1;

  -- 5) outro place + end_previous=true encerra o anterior
  -- place Ipiranga está ~4km do GPS QA → OUT_OF_RANGE.
  -- Usa o próprio place OUT com GPS do OUT.
  r := public.create_check_in(
    v_place_out, -23.5540, -46.6350, 10, now(), true
  );
  if r #>> '{error,code}' is not null then
    raise exception 'F4.5 FAIL: check-in OUT com GPS local falhou %', r;
  end if;
  if (r #>> '{endedPreviousCheckInId}') is distinct from id1::text then
    raise exception 'F4.5 FAIL: não encerrou o anterior (ended=%)', r -> 'endedPreviousCheckInId';
  end if;
  id2 := (r #>> '{checkIn,id}')::uuid;
  raise notice 'F4.5 PASS end_previous encerrou %', id1;

  -- 6) outro place + end_previous=false → ALREADY_CHECKED_IN
  r := public.create_check_in(
    v_place_in, -23.5505, -46.6333, 10, now(), false
  );
  if r #>> '{error,code}' is distinct from 'ALREADY_CHECKED_IN' then
    raise exception 'F4.6 FAIL: esperado ALREADY_CHECKED_IN, veio %', r;
  end if;
  raise notice 'F4.6 PASS ALREADY_CHECKED_IN';

  -- unique index: no máximo 1 active por user
  select count(*) into active_n
  from public.check_ins
  where user_id = v_uid and status = 'active';
  if active_n <> 1 then
    raise exception 'F4.unique FAIL: % ativos (esperado 1)', active_n;
  end if;

  begin
    insert into public.check_ins (
      user_id, place_id, lat, lng, distance_meters, expires_at, status
    ) values (
      v_uid, v_place_in, -23.5505, -46.6333, 10, now() + interval '3 hours', 'active'
    );
    raise exception 'F4.unique FAIL: segundo active inseriu (índice ausente?)';
  exception
    when unique_violation then
      raise notice 'F4.unique PASS índice one_active_per_user';
  end;

  -- expire: força expires_at no passado
  update public.check_ins
  set expires_at = now() - interval '1 minute'
  where id = id2;

  n := public.expire_check_ins();
  if n < 1 then
    raise exception 'F4.expire FAIL: expire_check_ins retornou %', n;
  end if;
  if exists (select 1 from public.check_ins where id = id2 and status = 'active') then
    raise exception 'F4.expire FAIL: status ainda active';
  end if;
  raise notice 'F4.expire PASS ended n=%', n;

  -- cleanup tester
  delete from public.check_ins where user_id = v_uid;
  raise notice 'F4 ALL PASS';
end;
$$;

rollback;
