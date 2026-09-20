-- Social RPCs: profile, stats, follows, comments, notifications
-- RPCs para funcionalidades sociais com dados reais

begin;

-- RPC para buscar perfil de usuário
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
  
  -- Contar followers
  select count(*) into v_followers_count
  from public.follows
  where following_id = p_user_id;
  
  -- Contar following
  select count(*) into v_following_count
  from public.follows
  where follower_id = p_user_id;
  
  -- Atualizar contadores no perfil
  update public.profiles
  set followers_count = v_followers_count,
      following_count = v_following_count
  where id = p_user_id;
  
  -- Retornar com contadores atualizados
  v_profile := v_profile || jsonb_build_object(
    'followers_count', coalesce(v_followers_count, 0),
    'following_count', coalesce(v_following_count, 0)
  );
  
  return v_profile;
end;
$$;

grant execute on function public.get_user_profile to authenticated;

-- RPC para buscar stats de usuário (para Streak Counter)
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
  v_sessions int;
  v_minutes int;
  v_meters int;
  v_places int;
  v_streak_days int;
  v_posts int;
  v_days_list date[];
  v_streak int;
  v_current_date date;
  v_prev_date date;
begin
  -- Contar sessões (check-ins completos)
  select count(*) into v_sessions
  from public.check_ins
  where user_id = p_user_id
    and status = 'ended';
  
  -- Calcular minutos totais
  select sum(extract(epoch from (ended_at - started_at)) / 60)::int into v_minutes
  from public.check_ins
  where user_id = p_user_id
    and status = 'ended';
  
  -- Contar lugares únicos
  select count(distinct place_id) into v_places
  from public.check_ins
  where user_id = p_user_id
    and status = 'ended';
  
  -- Contar posts
  select count(*) into v_posts
  from public.posts
  where user_id = p_user_id;
  
  -- Calcular streak (dias consecutivos com check-in)
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
  
  v_streak_days := v_streak;
  
  -- Calcular metros (estimado: 30m por minuto como média)
  v_meters := coalesce(v_minutes * 30, 0);
  
  return jsonb_build_object(
    'sessions', v_sessions,
    'minutes', coalesce(v_minutes, 0),
    'meters', v_meters,
    'places', v_places,
    'streak_days', v_streak_days,
    'posts', v_posts
  );
end;
$$;

grant execute on function public.get_user_stats to authenticated;

-- RPC para seguir usuário
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
begin
  if p_follower_id = p_following_id then
    return jsonb_build_object('error', 'Cannot follow yourself');
  end if;
  
  insert into public.follows (follower_id, following_id)
  values (p_follower_id, p_following_id)
  on conflict (follower_id, following_id) do nothing;
  
  -- Atualizar contadores
  update public.profiles
  set following_count = following_count + 1
  where id = p_follower_id;
  
  update public.profiles
  set followers_count = followers_count + 1
  where id = p_following_id;
  
  return jsonb_build_object('success', true);
end;
$$;

grant execute on function public.follow_user to authenticated;

-- RPC para deixar de seguir
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
begin
  delete from public.follows
  where follower_id = p_follower_id
    and following_id = p_following_id;
  
  -- Atualizar contadores
  update public.profiles
  set following_count = greatest(following_count - 1, 0)
  where id = p_follower_id;
  
  update public.profiles
  set followers_count = greatest(followers_count - 1, 0)
  where id = p_following_id;
  
  return jsonb_build_object('success', true);
end;
$$;

grant execute on function public.unfollow_user to authenticated;

-- RPC para verificar se segue
create or replace function public.is_following(
  p_follower_id uuid,
  p_following_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.follows
    where follower_id = p_follower_id
      and following_id = p_following_id
  );
$$;

grant execute on function public.is_following to authenticated;

-- RPC para listar comentários de um post
create or replace function public.list_comments(
  p_post_id uuid
)
returns table (
  id uuid,
  post_id uuid,
  user_id uuid,
  display_name text,
  avatar_url text,
  text text,
  likes int,
  created_at timestamptz,
  liked boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return query
  select
    c.id,
    c.post_id,
    c.user_id,
    p.display_name,
    p.avatar_url,
    c.text,
    c.likes,
    c.created_at,
    exists (
      select 1 from public.comment_likes cl
      where cl.comment_id = c.id
        and cl.user_id = auth.uid()
    ) as liked
  from public.comments c
  join public.profiles p on c.user_id = p.id
  where c.post_id = p_post_id
  order by c.created_at asc;
end;
$$;

grant execute on function public.list_comments to authenticated;

-- RPC para criar comentário
create or replace function public.create_comment(
  p_post_id uuid,
  p_text text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_comment_id uuid;
begin
  insert into public.comments (post_id, user_id, text)
  values (p_post_id, auth.uid(), p_text)
  returning id into v_comment_id;
  
  -- Incrementar contador de posts do usuário
  update public.profiles
  set posts_count = posts_count + 1
  where id = auth.uid();
  
  return jsonb_build_object(
    'id', v_comment_id,
    'success', true
  );
end;
$$;

grant execute on function public.create_comment to authenticated;

-- RPC para dar like em comentário
create or replace function public.toggle_comment_like(
  p_comment_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_liked boolean;
begin
  v_liked := exists (
    select 1 from public.comment_likes
    where comment_id = p_comment_id
      and user_id = auth.uid()
  );
  
  if v_liked then
    -- Remover like
    delete from public.comment_likes
    where comment_id = p_comment_id
      and user_id = auth.uid();
    
    update public.comments
    set likes = greatest(likes - 1, 0)
    where id = p_comment_id;
  else
    -- Adicionar like
    insert into public.comment_likes (comment_id, user_id)
    values (p_comment_id, auth.uid());
    
    update public.comments
    set likes = likes + 1
    where id = p_comment_id;
  end if;
  
  return jsonb_build_object(
    'liked', not v_liked,
    'likes', (select likes from public.comments where id = p_comment_id)
  );
end;
$$;

grant execute on function public.toggle_comment_like to authenticated;

-- RPC para listar notificações
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
begin
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
  where n.user_id = coalesce(p_user_id, auth.uid())
  order by n.created_at desc
  limit 50;
end;
$$;

grant execute on function public.list_notifications to authenticated;

-- RPC para marcar notificação como lida
create or replace function public.mark_notification_read(
  p_notification_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  update public.notifications
  set read = true
  where id = p_notification_id
    and user_id = auth.uid();
  
  return jsonb_build_object('success', true);
end;
$$;

grant execute on function public.mark_notification_read to authenticated;

-- RPC para marcar todas notificações como lidas
create or replace function public.mark_all_notifications_read()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  update public.notifications
  set read = true
  where user_id = auth.uid();
  
  return jsonb_build_object('success', true);
end;
$$;

grant execute on function public.mark_all_notifications_read to authenticated;

-- Trigger function para incrementar posts_count quando post é criado
create or replace function public.increment_posts_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles
  set posts_count = posts_count + 1
  where id = new.user_id;
  return new;
end;
$$;

grant execute on function public.increment_posts_count to authenticated;

-- Trigger para incrementar posts_count quando post é criado
create trigger trg_posts_count_increment
after insert on public.posts
for each row
execute procedure public.increment_posts_count();

commit;
