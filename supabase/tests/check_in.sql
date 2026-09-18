-- F4: casos de check-in. Rode no SQL editor como postgres / service_role
-- depois de seed_sao_paulo.sql (UUIDs QA).
-- Place IN:  11111111-1111-1111-1111-111111111111  (~80 m de -23.5505,-46.6333)
-- Place OUT: 22222222-2222-2222-2222-222222222222  (~450 m)
--
-- Este script NÃO cria auth.users. Substitua :uid pelo uuid de um perfil de teste.
-- Checklist manual:
-- 1. set request.jwt.claim.sub = :uid  (ou teste via app autenticado)
-- 2. create_check_in IN → checkIn.status = active
-- 3. create_check_in IN de novo → mesmo id (idempotente)
-- 4. create_check_in OUT → error.code = OUT_OF_RANGE + distanceMeters
-- 5. captured_at = now() - interval '10 minutes' → LOCATION_STALE
-- 6. outro place + p_end_previous=false → ALREADY_CHECKED_IN
-- 7. outro place + p_end_previous=true → anterior ended, novo active
-- 8. select count(*) from check_ins where user_id=:uid and status='active' = 1
-- 9. como anon: select * from check_ins → 0 linhas (F2)
-- 10. expire_check_ins() em row com expires_at < now() → ended

-- Smoke nearby (não precisa auth):
select id, name, distance_meters
from public.nearby_places(
  p_lat := -23.5505,
  p_lng := -46.6333,
  p_radius_meters := 5000,
  p_city_slug := 'sao-paulo',
  p_limit := 20,
  p_offset := 0
);
