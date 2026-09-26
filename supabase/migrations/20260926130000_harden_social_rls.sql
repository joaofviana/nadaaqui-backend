-- Social: fecha buracos de segurança.
-- 1) RLS em follows, comments, comment_likes e notifications (antes estavam abertas pela API).
-- 2) list_notifications só devolve notificações de quem está logado.
-- 3) Contadores do perfil (followers/following/posts) não podem ser editados direto pelo app.
-- 4) follow_user/unfollow_user só agem em nome de quem está logado e não inflam contadores.
-- 5) get_user_profile não faz mais UPDATE (era STABLE e quebrava com erro).
-- O app só escreve nessas tabelas pelas RPCs security definer, então não há policy de escrita direta.

begin;

-- ---------------------------------------------------------------------------
-- 1) RLS + privilégios nas tabelas sociais
-- ---------------------------------------------------------------------------
alter table public.follows enable row level security;
alter table public.comments enable row level security;
alter table public.comment_likes enable row level security;
alter table public.notifications enable row level security;

-- anon: nada. authenticated: só leitura (escrita pelas RPCs).
revoke all on table public.follows, public.comments, public.comment_likes, public.notifications
  from anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.follows, public.comments, public.comment_likes, public.notifications
  from authenticated;
grant select on table public.follows, public.comments, public.comment_likes, public.notifications
  to authenticated;
-- notificação: o dono pode marcar como lida direto (só a coluna read).
grant update (read) on table public.notifications to authenticated;

drop policy if exists follows_select_authenticated on public.follows;
create policy follows_select_authenticated on public.follows
  for select to authenticated
  using (true);

drop policy if exists comments_select_authenticated on public.comments;
create policy comments_select_authenticated on public.comments
  for select to authenticated
  using (true);

drop policy if exists comment_likes_select_authenticated on public.comment_likes;
create policy comment_likes_select_authenticated on public.comment_likes
  for select to authenticated
  using (true);

drop policy if exists notifications_select_own on public.notifications;
create policy notifications_select_own on public.notifications
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own on public.notifications
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- 2) Contadores do perfil protegidos
-- security invoker de propósito: current_user é o papel do cliente (anon/authenticated)
-- quando o UPDATE vem direto da API, e o dono (postgres) quando vem de RPC security definer.
-- ---------------------------------------------------------------------------
create or replace function public.protect_profile_counters()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if current_user in ('anon', 'authenticated') then
    new.followers_count := old.followers_count;
    new.following_count := old.following_count;
    new.posts_count := old.posts_count;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_protect_counters on public.profiles;
create trigger profiles_protect_counters
  before update on public.profiles
  for each row execute function public.protect_profile_counters();

-- ---------------------------------------------------------------------------
-- 3) list_notifications: sempre auth.uid(). Mantém a assinatura (p_user_id opcional);
-- se vier outro usuário, recusa.
-- ---------------------------------------------------------------------------
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
    raise exception 'UNAUTHORIZED' using errcode = '42501';
  end if;

  if p_user_id is not null and p_user_id <> v_uid then
    raise exception 'FORBIDDEN' using errcode = '42501';
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

-- ---------------------------------------------------------------------------
-- 4) follow_user / unfollow_user: só em nome de auth.uid(); contador só muda
-- se a linha foi mesmo criada/apagada (antes, chamar várias vezes inflava).
-- Assinatura mantida; p_follower_id pode ser null (= eu) ou igual a auth.uid().
-- ---------------------------------------------------------------------------
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
    raise exception 'UNAUTHORIZED' using errcode = '42501';
  end if;

  if p_follower_id is not null and p_follower_id <> v_uid then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if p_following_id is null or p_following_id = v_uid then
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
    raise exception 'UNAUTHORIZED' using errcode = '42501';
  end if;

  if p_follower_id is not null and p_follower_id <> v_uid then
    raise exception 'FORBIDDEN' using errcode = '42501';
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

-- ---------------------------------------------------------------------------
-- 5) get_user_profile: era STABLE com UPDATE dentro (dava erro sempre) e deixava
-- qualquer um reescrever contadores de qualquer perfil. Agora só lê.
-- ---------------------------------------------------------------------------
create or replace function public.get_user_profile(
  p_user_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_profile jsonb;
  v_followers_count int;
  v_following_count int;
begin
  select jsonb_build_object(
    'id', p.id,
    'display_name', p.display_name,
    'avatar_url', p.avatar_url,
    'bio', coalesce(p.bio, ''),
    'followers_count', coalesce(p.followers_count, 0),
    'following_count', coalesce(p.following_count, 0),
    'posts_count', coalesce(p.posts_count, 0)
  ) into v_profile
  from public.profiles p
  where p.id = p_user_id;

  if v_profile is null then
    return null;
  end if;

  -- contagem real a partir de follows (sem gravar no perfil)
  select count(*) into v_followers_count
  from public.follows
  where following_id = p_user_id;

  select count(*) into v_following_count
  from public.follows
  where follower_id = p_user_id;

  return v_profile || jsonb_build_object(
    'followers_count', coalesce(v_followers_count, 0),
    'following_count', coalesce(v_following_count, 0)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 6) Execução das RPCs sociais: só authenticated (o default do Supabase dava
-- EXECUTE também para anon/public).
-- ---------------------------------------------------------------------------
revoke execute on function public.get_user_profile(uuid) from public, anon;
revoke execute on function public.get_user_stats(uuid) from public, anon;
revoke execute on function public.follow_user(uuid, uuid) from public, anon;
revoke execute on function public.unfollow_user(uuid, uuid) from public, anon;
revoke execute on function public.is_following(uuid, uuid) from public, anon;
revoke execute on function public.list_comments(uuid) from public, anon;
revoke execute on function public.create_comment(uuid, text) from public, anon;
revoke execute on function public.toggle_comment_like(uuid) from public, anon;
revoke execute on function public.list_notifications(uuid) from public, anon;
revoke execute on function public.mark_notification_read(uuid) from public, anon;
revoke execute on function public.mark_all_notifications_read() from public, anon;

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

-- Funções de trigger não são para chamar pela API.
revoke execute on function public.increment_posts_count() from public, anon, authenticated;
revoke execute on function public.protect_profile_counters() from public, anon, authenticated;

commit;
