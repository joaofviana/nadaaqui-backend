-- Permissões das RPCs (EXECUTE) no schema public.
--
-- Antes: toda função nova no public ganhava EXECUTE para PUBLIC/anon/authenticated
-- (padrão do Postgres + default privileges do Supabase). Ou seja, qualquer um com a
-- anon key conseguia chamar quase todas as RPCs, inclusive funções de trigger e
-- helpers internos (ex.: _workout_plan_json, handle_new_user).
--
-- Agora:
-- 1) Tira EXECUTE de PUBLIC e anon de TODAS as funções do public criadas pelas
--    nossas migrations (funções de extensão como PostGIS/pg_trgm ficam de fora:
--    são do supabase_admin e nearby_places/get_place, que são SECURITY INVOKER,
--    precisam delas para o anon).
-- 2) anon só executa: get_remote_config, nearby_places, get_place e, por enquanto,
--    who_is_here, place_board e place_hourly_heat (o app instalado hoje pode chamar
--    essas três sem login). Essas três saem do anon na migration 20260926140100,
--    que só vai para produção depois do app novo nas lojas.
-- 3) authenticated continua executando as RPCs que o app usa (grant explícito,
--    não depende mais de PUBLIC).
-- 4) Funções de trigger e helpers internos: ninguém do app executa
--    (nem PUBLIC, nem anon, nem authenticated). Trigger dispara normalmente
--    sem EXECUTE para quem faz o INSERT/UPDATE.
-- 5) expire_check_ins continua só service_role (e o dono postgres, que é quem
--    roda o job do pg_cron).
-- 6) Default privileges: funções novas criadas pelo postgres no public nascem
--    SEM EXECUTE para PUBLIC e anon. Quem criar RPC nova para o app precisa dar
--    `grant execute ... to authenticated` (e anon, se for pública) na migration.
--    Obs.: o default "PUBLIC executa funções" do Postgres é global (não por
--    schema), então o revoke de PUBLIC é feito sem `in schema` — vale para
--    funções que o postgres criar em qualquer schema. Funções criadas pelo
--    supabase_admin (extensões) não são afetadas.
--    service_role e authenticated mantêm o default do Supabase.

begin;

-- ---------------------------------------------------------------------------
-- 1) Fecha tudo para PUBLIC e anon (menos funções de extensão)
-- ---------------------------------------------------------------------------
do $$
declare
  f regprocedure;
begin
  for f in
    select p.oid::regprocedure
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.prokind in ('f', 'p')
      and not exists (
        select 1 from pg_depend d
        where d.classid = 'pg_proc'::regclass
          and d.objid = p.oid
          and d.deptype = 'e'
      )
  loop
    execute format('revoke execute on function %s from public, anon', f);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2) Funções de trigger e helpers internos: também fora do authenticated
-- ---------------------------------------------------------------------------
do $$
declare
  f regprocedure;
begin
  for f in
    select p.oid::regprocedure
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.prorettype = 'trigger'::regtype
      and not exists (
        select 1 from pg_depend d
        where d.classid = 'pg_proc'::regclass
          and d.objid = p.oid
          and d.deptype = 'e'
      )
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
  end loop;
end;
$$;

-- helpers chamados só de dentro de RPCs security definer
revoke execute on function public._workout_plan_json(uuid) from public, anon, authenticated;
revoke execute on function public.profile_stats(uuid) from public, anon, authenticated;
-- job do pg_cron (roda como postgres, dono da função)
revoke execute on function public.expire_check_ins() from public, anon, authenticated;
grant execute on function public.expire_check_ins() to service_role;

-- ---------------------------------------------------------------------------
-- 3) authenticated: RPCs do app (grant explícito)
-- ---------------------------------------------------------------------------
-- lugares / config / presença
grant execute on function public.get_remote_config() to authenticated;
grant execute on function public.nearby_places(
  double precision, double precision, integer, text, text,
  public.price_type[], public.total_pass[], integer, integer
) to authenticated;
grant execute on function public.get_place(uuid) to authenticated;
grant execute on function public.who_is_here(uuid) to authenticated;
-- check-in / nado
grant execute on function public.create_check_in(
  uuid, double precision, double precision, double precision, timestamptz, boolean
) to authenticated;
grant execute on function public.checkout_check_in(uuid) to authenticated;
grant execute on function public.finish_swim(uuid, integer, text) to authenticated;
-- feed / sessões / tanque
grant execute on function public.create_feed_post(text, public.post_kind, uuid, integer) to authenticated;
grant execute on function public.toggle_kudo(uuid) to authenticated;
grant execute on function public.list_feed(integer, integer) to authenticated;
grant execute on function public.list_my_sessions(integer, integer) to authenticated;
grant execute on function public.place_board(uuid, integer) to authenticated;
grant execute on function public.place_hourly_heat(uuid) to authenticated;
-- perfil
grant execute on function public.get_my_profile() to authenticated;
grant execute on function public.get_public_profile(text, uuid) to authenticated;
grant execute on function public.update_my_profile(jsonb) to authenticated;
grant execute on function public.list_profile_public_check_ins(uuid, integer, integer) to authenticated;
-- social
grant execute on function public.get_user_profile(uuid) to authenticated;
grant execute on function public.get_user_stats(uuid) to authenticated;
grant execute on function public.follow_user(uuid, uuid) to authenticated;
grant execute on function public.unfollow_user(uuid, uuid) to authenticated;
grant execute on function public.is_following(uuid, uuid) to authenticated;
grant execute on function public.list_comments(uuid) to authenticated;
grant execute on function public.create_comment(uuid, text) to authenticated;
grant execute on function public.toggle_comment_like(uuid) to authenticated;
grant execute on function public.list_notifications(uuid) to authenticated;
grant execute on function public.mark_notification_read(uuid) to authenticated;
grant execute on function public.mark_all_notifications_read() to authenticated;
-- treinos
grant execute on function public.save_workout_plan(
  text, public.pool_length, public.workout_focus, jsonb, uuid
) to authenticated;
grant execute on function public.list_my_workouts(integer, integer) to authenticated;
grant execute on function public.get_workout_plan(uuid) to authenticated;
grant execute on function public.delete_workout_plan(uuid) to authenticated;
grant execute on function public.start_workout(uuid, uuid, integer, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- 4) anon: só o que o visitante (sem conta) usa
-- ---------------------------------------------------------------------------
grant execute on function public.get_remote_config() to anon;
grant execute on function public.nearby_places(
  double precision, double precision, integer, text, text,
  public.price_type[], public.total_pass[], integer, integer
) to anon;
grant execute on function public.get_place(uuid) to anon;
-- temporário: saem na migration 20260926140100 (depois do app novo nas lojas).
-- Para mover uma delas de arquivo, basta mover a linha correspondente.
grant execute on function public.who_is_here(uuid) to anon;
grant execute on function public.place_board(uuid, integer) to anon;
grant execute on function public.place_hourly_heat(uuid) to anon;

-- ---------------------------------------------------------------------------
-- 5) Funções futuras nascem fechadas para PUBLIC e anon
-- ---------------------------------------------------------------------------
alter default privileges for role postgres revoke execute on functions from public;
alter default privileges for role postgres in schema public revoke execute on functions from public, anon;

commit;
