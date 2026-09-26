-- Social: códigos de erro do contrato + privacidade no get_user_stats.
--
-- 1) list_notifications / follow_user / unfollow_user: os erros passam a usar
--    errcode P0001 (contrato em docs/contrato-rpc.md), com as mensagens exatas
--    'UNAUTHORIZED' e 'FORBIDDEN' (o app lê a mensagem). Antes era 42501, que
--    se confunde com "permission denied" do próprio Postgres.
-- 2) follow_user com alvo null ou inexistente: erro P0001 'VALIDATION_ERROR'
--    (antes respondia 'Cannot follow yourself' para null e estourava FK para
--    id inexistente). 'Cannot follow yourself' fica só para seguir a si mesmo.
-- 3) get_user_stats respeita a privacidade do perfil:
--    - o dono sempre vê tudo;
--    - para outros usuários, se profiles.privacy_show_meters = false, as chaves
--      'meters' e 'minutes' são omitidas (meters é calculado a partir de minutes,
--      então mostrar minutes vazaria os metros);
--    - sessions, places, streak_days e posts continuam visíveis (o perfil público
--      já mostra check-ins/lugares e os posts são públicos no feed).
--    - só authenticated chama (grant já feito); sem sessão → UNAUTHORIZED;
--      p_user_id null → VALIDATION_ERROR; usuário inexistente → null.
-- O cálculo dos números em si não mudou.
-- Assinaturas mantidas (create or replace preserva os grants).

begin;

create or replace function public.list_notifications(
  p_user_id uuid default null
)
returns table (
  id uuid,
  type text,
  title text,
  body text,
  actor_id uuid,
  actor_name text,
  actor_avatar_url text,
  post_id uuid,
  place_id uuid,
  read boolean,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'UNAUTHORIZED' using errcode = 'P0001';
  end if;

  if p_user_id is not null and p_user_id <> v_uid then
    raise exception 'FORBIDDEN' using errcode = 'P0001';
  end if;

  return query
  select
    n.id,
    n.type,
    n.title,
    n.body,
    n.actor_id,
    p.display_name as actor_name,
    p.avatar_url as actor_avatar_url,
    n.post_id,
    n.place_id,
    n.read,
    n.created_at
  from public.notifications n
  left join public.profiles p on n.actor_id = p.id
  where n.user_id = v_uid
  order by n.created_at desc
  limit 50;
end;
$$;

create or replace function public.follow_user(
  p_follower_id uuid,
  p_following_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_rows int;
begin
  if v_uid is null then
    raise exception 'UNAUTHORIZED' using errcode = 'P0001';
  end if;

  if p_follower_id is not null and p_follower_id <> v_uid then
    raise exception 'FORBIDDEN' using errcode = 'P0001';
  end if;

  if p_following_id is null
     or not exists (select 1 from public.profiles where id = p_following_id) then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001';
  end if;

  if p_following_id = v_uid then
    return jsonb_build_object('error', 'Cannot follow yourself');
  end if;

  insert into public.follows (follower_id, following_id)
  values (v_uid, p_following_id)
  on conflict (follower_id, following_id) do nothing;

  get diagnostics v_rows = row_count;

  if v_rows > 0 then
    update public.profiles
    set following_count = following_count + 1
    where id = v_uid;

    update public.profiles
    set followers_count = followers_count + 1
    where id = p_following_id;
  end if;

  return jsonb_build_object('success', true);
end;
$$;

create or replace function public.unfollow_user(
  p_follower_id uuid,
  p_following_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_rows int;
begin
  if v_uid is null then
    raise exception 'UNAUTHORIZED' using errcode = 'P0001';
  end if;

  if p_follower_id is not null and p_follower_id <> v_uid then
    raise exception 'FORBIDDEN' using errcode = 'P0001';
  end if;

  delete from public.follows
  where follower_id = v_uid
    and following_id = p_following_id;

  get diagnostics v_rows = row_count;

  if v_rows > 0 then
    update public.profiles
    set following_count = greatest(following_count - 1, 0)
    where id = v_uid;

    update public.profiles
    set followers_count = greatest(followers_count - 1, 0)
    where id = p_following_id;
  end if;

  return jsonb_build_object('success', true);
end;
$$;

create or replace function public.get_user_stats(
  p_user_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_is_self boolean;
  v_show_meters boolean;
  v_sessions int;
  v_minutes int;
  v_meters int;
  v_places int;
  v_posts int;
  v_days_list date[];
  v_streak int;
  v_current_date date;
  v_prev_date date;
  v_out jsonb;
begin
  if v_uid is null then
    raise exception 'UNAUTHORIZED' using errcode = 'P0001';
  end if;

  if p_user_id is null then
    raise exception 'VALIDATION_ERROR' using errcode = 'P0001';
  end if;

  select pr.privacy_show_meters into v_show_meters
  from public.profiles pr
  where pr.id = p_user_id;

  if not found then
    return null;
  end if;

  v_is_self := (p_user_id = v_uid);

  -- sessões (check-ins encerrados), minutos e lugares únicos
  select count(*),
         sum(extract(epoch from (ended_at - started_at)) / 60)::int,
         count(distinct place_id)
    into v_sessions, v_minutes, v_places
  from public.check_ins
  where user_id = p_user_id
    and status = 'ended';

  select count(*) into v_posts
  from public.posts
  where user_id = p_user_id;

  -- streak: dias consecutivos com check-in encerrado (últimos 60 dias)
  select array_agg(date(started_at)::date order by started_at desc) into v_days_list
  from public.check_ins
  where user_id = p_user_id
    and status = 'ended'
    and started_at >= current_date - interval '60 days';

  v_streak := 0;
  if array_length(v_days_list, 1) > 0 then
    v_current_date := v_days_list[1];
    v_streak := 1;

    for i in 2..array_length(v_days_list, 1) loop
      v_prev_date := v_days_list[i];
      if v_prev_date = v_current_date - interval '1 day' then
        v_streak := v_streak + 1;
        v_current_date := v_prev_date;
      else
        exit;
      end if;
    end loop;
  end if;

  -- metros estimados: 30 m por minuto
  v_meters := coalesce(v_minutes * 30, 0);

  v_out := jsonb_build_object(
    'sessions', v_sessions,
    'places', v_places,
    'streak_days', v_streak,
    'posts', v_posts
  );

  if v_is_self or v_show_meters then
    v_out := v_out || jsonb_build_object(
      'minutes', coalesce(v_minutes, 0),
      'meters', v_meters
    );
  end if;

  return v_out;
end;
$$;

commit;
