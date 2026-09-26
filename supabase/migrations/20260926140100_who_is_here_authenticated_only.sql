-- ATENÇÃO (produção): aplicar SOMENTE depois que a versão nova do app — que não
-- chama who_is_here / place_board / place_hourly_heat sem sessão — estiver
-- publicada nas lojas (App Store e Google Play). Se aplicar antes, as telas de
-- presença e do tanque quebram para quem ainda usa o app antigo sem login (visitante).
--
-- O que faz: essas três RPCs passam a ser só para usuário logado (authenticated).
-- Depois desta migration, anon executa apenas get_remote_config, nearby_places e get_place.

begin;

revoke execute on function public.who_is_here(uuid) from public, anon;
revoke execute on function public.place_board(uuid, integer) from public, anon;
revoke execute on function public.place_hourly_heat(uuid) from public, anon;

grant execute on function public.who_is_here(uuid) to authenticated;
grant execute on function public.place_board(uuid, integer) to authenticated;
grant execute on function public.place_hourly_heat(uuid) to authenticated;

commit;
